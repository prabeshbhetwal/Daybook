import Foundation

/// Turns frontmost-app changes into usage sessions. Driven entirely by the
/// notifications `EventMonitor` already receives — no polling, no new
/// permissions, bundle identifiers and localised names only. Window titles, URLs
/// and keystrokes are never read.
///
/// Tracking can be switched off; when off, nothing is recorded at all.
final class AppUsageTracker {

    private struct ActiveSegment {
        let id: UUID
        let bundleID: String
        let appName: String
        let start: Date
        var lastPersistedEnd: Date
    }

    private struct ResumeCandidate {
        let bundleID: String
        let appName: String
    }

    private enum TrackingState {
        case stopped
        case active(ActiveSegment)
        case waitingForPresence(ResumeCandidate)
    }

    private let archive: AppUsageArchive
    private let now: () -> Date
    private let ownBundleID: String?
    private let idle: IdleMonitor
    private var state: TrackingState = .stopped

    private(set) var isEnabled: Bool

    init(archive: AppUsageArchive,
         ownBundleID: String? = Bundle.main.bundleIdentifier,
         isEnabled: Bool = true,
         idle: IdleMonitor = IdleMonitor(),
         now: @escaping () -> Date = Date.init) {
        self.archive = archive
        self.ownBundleID = ownBundleID
        self.isEnabled = isEnabled
        self.idle = idle
        self.now = now
    }

    /// After this much input-free time, the machine is not being used and the
    /// open stretch stops accruing. Screen Time is criticised for exactly the
    /// opposite: counting an app as in use whenever it is frontmost, even when
    /// nobody is at the keyboard.
    static let idleCutoff: TimeInterval = 180

    /// The instant the open stretch should end, and whether idle trimmed it.
    ///
    /// The clock is sampled **once**: comparing a trimmed end against a freshly
    /// sampled `now()` was always true by microseconds, which labelled every
    /// stretch `.idle` and made grouping apply the 15-minute away bridge where
    /// the 5-minute gap belonged.
    private func effectiveEnd() -> (end: Date, trimmed: Bool) {
        let moment = now()
        let idleFor = idle.idleSeconds()
        guard idleFor >= AppUsageTracker.idleCutoff else { return (moment, false) }
        return (moment.addingTimeInterval(-idleFor), true)
    }

    /// The app that is frontmost right now, if tracking is running.
    var currentBundleID: String? {
        guard case .active(let segment) = state else { return nil }
        return segment.bundleID
    }

    /// Whether the tracker has an active stretch that should keep the store's
    /// cosmetic ticker alive. Waiting for a confirmed return is deliberately
    /// not observing: idle and away time must not restart a timer by itself.
    var isObserving: Bool {
        if case .active = state { return true }
        return false
    }

    /// How long the in-flight stretch has run, idle-trimmed exactly as a real
    /// close would trim it. Lets the menu bar show a live "at the Mac" figure
    /// without writing a record every second: the archive only learns about an
    /// open stretch when something forces a flush, and between flushes the total
    /// stood visibly still — five minutes of "0m" after a boot, in one measured
    /// case, because nothing had happened yet to trigger a write.
    func currentStretchSeconds() -> TimeInterval {
        guard case .active(let segment) = state else { return 0 }
        return max(0, effectiveEnd().end.timeIntervalSince(segment.start))
    }

    /// The portion of the active stretch not already represented by its stable
    /// archive checkpoint. Combining this with `usage.totalToday()` therefore
    /// never counts a saved prefix twice.
    func unpersistedSeconds() -> TimeInterval {
        guard case .active(let segment) = state else { return 0 }
        return max(0, effectiveEnd().end.timeIntervalSince(segment.lastPersistedEnd))
    }

    /// Compatibility for existing callers while they migrate to the two
    /// deliberate measures above. `openSeconds` remains the whole live stretch.
    func openSeconds() -> TimeInterval { currentStretchSeconds() }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        if !enabled { closeActiveSegment(reason: .systemLock) }
        isEnabled = enabled
    }

    /// A new app came to the front. Closes the previous stretch and opens one.
    func appActivated(bundleID: String?, name: String) {
        guard isEnabled else { return }
        // Our own popover taking focus must not chop the user's session in two.
        if let bundleID, bundleID == ownBundleID { return }
        guard let bundleID else { return }
        // The lock screen is not an app the user chose to use. Closing the open
        // stretch but opening none means the absence records as a gap, which is
        // what it was.
        if AppUsageArchive.systemProcesses.contains(bundleID) {
            closeActiveSegment(reason: .systemLock)
            return
        }
        if case .active(let segment) = state, segment.bundleID == bundleID { return }

        closeActiveSegment(reason: .appSwitch)
        begin(bundleID: bundleID, name: name, at: now())
    }

    /// The user went away — lock, sleep or power off. Time spent away is not
    /// usage, so the stretch ends here rather than running until they return.
    func suspend() {
        closeActiveSegment(reason: .systemLock)
    }

    private func closeActiveSegment(reason: UsageEndReason) {
        guard case .active(let segment) = state else { return }
        state = .stopped
        let (candidate, wasTrimmed) = effectiveEnd()
        // Idle trimming outranks the nominal reason: the stretch really ended
        // when input stopped, not when the app changed.
        archive.checkpoint(AppUsageSession(id: segment.id,
                                           bundleID: segment.bundleID,
                                           appName: segment.appName,
                                           start: segment.start,
                                           end: max(segment.start, candidate),
                                           endReason: wasTrimmed ? .idle : reason))
    }

    /// Flushes the in-flight stretch so queries include it. Called before the
    /// menu bar reads its data, and on terminate.
    func flush() {
        guard case .active(var segment) = state else { return }
        let (candidate, wasTrimmed) = effectiveEnd()
        let end = max(segment.start, candidate)
        archive.checkpoint(AppUsageSession(id: segment.id,
                                           bundleID: segment.bundleID,
                                           appName: segment.appName,
                                           start: segment.start,
                                           end: end,
                                           endReason: wasTrimmed ? .idle : .stillOpen))
        if wasTrimmed {
            state = .waitingForPresence(ResumeCandidate(bundleID: segment.bundleID,
                                                         appName: segment.appName))
            return
        }
        // A rejected sub-five-second checkpoint has not been saved, so retain
        // the old boundary and present the whole live tail as unpersisted.
        if end.timeIntervalSince(segment.start) >= AppUsageConstants.minimumSegment {
            segment.lastPersistedEnd = end
        }
        state = .active(segment)
    }

    /// True when the open stretch has been accruing long enough that losing it
    /// to a crash would matter. Drives the periodic flush.
    func openSeconds(exceeds limit: TimeInterval) -> Bool {
        unpersistedSeconds() >= limit
    }

    /// Handles an idle sample from the store without creating a wake policy.
    /// Once the cutoff is crossed, correct the active checkpoint back to the
    /// final input moment and retain only a candidate for a later confirmation.
    func observeIdle(seconds: TimeInterval) {
        guard seconds >= AppUsageTracker.idleCutoff,
              case .active(let segment) = state else { return }
        let end = max(segment.start, now().addingTimeInterval(-seconds))
        archive.checkpoint(AppUsageSession(id: segment.id,
                                           bundleID: segment.bundleID,
                                           appName: segment.appName,
                                           start: segment.start,
                                           end: end,
                                           endReason: .idle))
        state = .waitingForPresence(ResumeCandidate(bundleID: segment.bundleID,
                                                     appName: segment.appName))
    }

    /// Records the app waiting behind a wake or idle boundary. The caller must
    /// separately prove user presence before `confirmPresence(at:)` begins a
    /// new UUID; this method intentionally does not make that policy decision.
    func prepareToResume(bundleID: String?, name: String) {
        guard isEnabled, !isObserving, let bundleID, bundleID != ownBundleID,
              !AppUsageArchive.systemProcesses.contains(bundleID) else { return }
        state = .waitingForPresence(ResumeCandidate(bundleID: bundleID,
                                                     appName: name.isEmpty ? bundleID : name))
    }

    /// Starts a fresh, independently correctable stretch after a caller has
    /// established that a person is actually back at the Mac.
    func confirmPresence(at moment: Date) {
        guard isEnabled, case .waitingForPresence(let candidate) = state else { return }
        begin(bundleID: candidate.bundleID, name: candidate.appName, at: moment)
    }

    private func begin(bundleID: String, name: String, at moment: Date) {
        let appName = name.isEmpty ? bundleID : name
        state = .active(ActiveSegment(id: UUID(), bundleID: bundleID,
                                      appName: appName, start: moment,
                                      lastPersistedEnd: moment))
    }

    /// The machine came back. Reopens tracking for whatever is frontmost, because
    /// waking and carrying on in the *same* app posts no activation notification —
    /// that work was simply never recorded.
    func resume(bundleID: String?, name: String) {
        guard isEnabled, !isObserving, let bundleID, bundleID != ownBundleID,
              !AppUsageArchive.systemProcesses.contains(bundleID) else { return }
        begin(bundleID: bundleID, name: name, at: now())
    }
}
