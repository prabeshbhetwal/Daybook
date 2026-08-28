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
    private var transitionChanged = false

    private(set) var isEnabled: Bool
    /// True while a public lifecycle operation is still settling. Archive
    /// callbacks are synchronous, so the store uses this to postpone consuming
    /// their refresh until the tracker publishes its final state.
    private(set) var isTransitioning = false
    var onDidTransition: (() -> Void)?

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

    /// Whether the tracker needs the store's existing ticker to keep sampling.
    /// Waiting for a confirmed return remains observable so same-app input can
    /// reach the presence gate; it still accrues no usage on its own.
    var isObserving: Bool {
        switch state {
        case .active, .waitingForPresence: return true
        case .stopped: return false
        }
    }

    /// How long the in-flight stretch has run, idle-trimmed exactly as a real
    /// close would trim it. Lets the menu bar show a live "at the Mac" figure
    /// without writing a record every second: the archive only learns about an
    /// open stretch when something forces a flush, and between flushes the total
    /// stood visibly still — five minutes of "0m" after a boot, in one measured
    /// case, because nothing had happened yet to trigger a write.
    func currentStretchSeconds() -> TimeInterval {
        guard case .active(let segment) = state else { return 0 }
        let candidate = effectiveEnd()
        let end = safeEnd(for: segment, candidate: candidate.end,
                          permitsRollback: candidate.trimmed)
        return max(0, end.timeIntervalSince(segment.start))
    }

    /// The portion of the active stretch not already represented by its stable
    /// archive checkpoint. Combining this with `usage.totalToday()` therefore
    /// never counts a saved prefix twice.
    func unpersistedSeconds() -> TimeInterval {
        unpersistedSession()?.seconds ?? 0
    }

    /// The live tail not represented by the stable archive checkpoint. Exposing
    /// the interval, rather than only its scalar, lets focused-active reporting
    /// intersect it and lets day totals clip it at local midnight.
    func unpersistedSession() -> AppUsageSession? {
        guard case .active(let segment) = state else { return nil }
        let candidate = effectiveEnd()
        let end = safeEnd(for: segment, candidate: candidate.end,
                          permitsRollback: candidate.trimmed)
        let start = max(segment.start, segment.lastPersistedEnd)
        guard end > start else { return nil }
        return AppUsageSession(id: segment.id, bundleID: segment.bundleID,
                               appName: segment.appName, start: start, end: end,
                               endReason: candidate.trimmed ? .idle : .stillOpen)
    }

    /// The unpersisted tail's literal overlap with one local day.
    func unpersistedSeconds(on day: Date,
                            calendar: Calendar = .current) -> TimeInterval {
        guard let live = unpersistedSession(),
              let bounds = SessionRecord.dayBounds(day, calendar: calendar) else { return 0 }
        let start = max(live.start, bounds.start)
        let end = min(live.end, bounds.end)
        return end > start ? end.timeIntervalSince(start) : 0
    }

    /// Compatibility for existing callers while they migrate to the two
    /// deliberate measures above. `openSeconds` remains the whole live stretch.
    func openSeconds() -> TimeInterval { currentStretchSeconds() }

    func setEnabled(_ enabled: Bool) {
        withTransition { setEnabledNow(enabled) }
    }

    private func setEnabledNow(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        if !enabled { stopTracking(reason: .systemLock) }
        isEnabled = enabled
        markTransition()
    }

    /// A new app came to the front. Closes the previous stretch and opens one.
    func appActivated(bundleID: String?, name: String) {
        withTransition { appActivatedNow(bundleID: bundleID, name: name) }
    }

    private func appActivatedNow(bundleID: String?, name: String) {
        guard isEnabled else { return }
        // Our own popover taking focus must not chop the user's session in two.
        if let bundleID, bundleID == ownBundleID { return }
        guard let bundleID else { return }
        // The lock screen is not an app the user chose to use. Closing the open
        // stretch but opening none means the absence records as a gap, which is
        // what it was.
        if AppUsageArchive.systemProcesses.contains(bundleID) {
            _ = closeActiveSegment(reason: .systemLock)
            return
        }
        if case .waitingForPresence = state {
            setState(.waitingForPresence(ResumeCandidate(
                bundleID: bundleID,
                appName: name.isEmpty ? bundleID : name)))
            return
        }
        if case .active(let segment) = state, segment.bundleID == bundleID { return }

        guard closeActiveSegment(reason: .appSwitch) else { return }
        begin(bundleID: bundleID, name: name, at: now())
    }

    /// The user went away — lock, sleep or power off. Time spent away is not
    /// usage, so the stretch ends here rather than running until they return.
    func suspend() {
        withTransition { stopTracking(reason: .systemLock) }
    }

    private func stopTracking(reason: UsageEndReason) {
        if case .active = state {
            _ = closeActiveSegment(reason: reason)
        } else {
            setState(.stopped)
        }
    }

    @discardableResult
    private func closeActiveSegment(reason: UsageEndReason) -> Bool {
        guard case .active(let segment) = state else { return true }
        let (candidate, wasTrimmed) = effectiveEnd()
        let end = safeEnd(for: segment, candidate: candidate,
                          permitsRollback: wasTrimmed)
        // Idle trimming outranks the nominal reason: the stretch really ended
        // when input stopped, not when the app changed.
        guard archive.checkpoint(AppUsageSession(id: segment.id,
                                                 bundleID: segment.bundleID,
                                                 appName: segment.appName,
                                                 start: segment.start,
                                                 end: end,
                                                 endReason: wasTrimmed ? .idle : reason)) else {
            return false
        }
        setState(.stopped)
        return true
    }

    /// Flushes the in-flight stretch so queries include it. Called before the
    /// menu bar reads its data, and on terminate.
    func flush() {
        withTransition { flushNow() }
    }

    private func flushNow() {
        guard case .active(var segment) = state else { return }
        let (candidate, wasTrimmed) = effectiveEnd()
        let end = safeEnd(for: segment, candidate: candidate,
                          permitsRollback: wasTrimmed)
        guard archive.checkpoint(AppUsageSession(id: segment.id,
                                                 bundleID: segment.bundleID,
                                                 appName: segment.appName,
                                                 start: segment.start,
                                                 end: end,
                                                 endReason: wasTrimmed ? .idle : .stillOpen)) else {
            return
        }
        if wasTrimmed {
            setState(.waitingForPresence(ResumeCandidate(bundleID: segment.bundleID,
                                                         appName: segment.appName)))
            return
        }
        // A rejected sub-five-second checkpoint has not been saved, so retain
        // the old boundary and present the whole live tail as unpersisted.
        if end.timeIntervalSince(segment.start) >= AppUsageConstants.minimumSegment {
            segment.lastPersistedEnd = end
        }
        setState(.active(segment))
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
        withTransition { observeIdleNow(seconds: seconds) }
    }

    private func observeIdleNow(seconds: TimeInterval) {
        guard seconds >= AppUsageTracker.idleCutoff,
              case .active(let segment) = state else { return }
        let end = max(segment.start, now().addingTimeInterval(-seconds))
        guard archive.checkpoint(AppUsageSession(id: segment.id,
                                                 bundleID: segment.bundleID,
                                                 appName: segment.appName,
                                                 start: segment.start,
                                                 end: end,
                                                 endReason: .idle)) else { return }
        setState(.waitingForPresence(ResumeCandidate(bundleID: segment.bundleID,
                                                     appName: segment.appName)))
    }

    /// Records the app waiting behind a wake or idle boundary. The caller must
    /// separately prove user presence before `confirmPresence(at:)` begins a
    /// new UUID; this method intentionally does not make that policy decision.
    func prepareToResume(bundleID: String?, name: String) {
        withTransition { prepareToResumeNow(bundleID: bundleID, name: name) }
    }

    private func prepareToResumeNow(bundleID: String?, name: String) {
        guard isEnabled, let bundleID, bundleID != ownBundleID,
              !AppUsageArchive.systemProcesses.contains(bundleID) else { return }
        if case .waitingForPresence = state {
            setState(.waitingForPresence(ResumeCandidate(
                bundleID: bundleID, appName: name.isEmpty ? bundleID : name)))
            return
        }
        guard !isObserving else { return }
        setState(.waitingForPresence(ResumeCandidate(bundleID: bundleID,
                                                     appName: name.isEmpty ? bundleID : name)))
    }

    /// Starts a fresh, independently correctable stretch after a caller has
    /// established that a person is actually back at the Mac.
    func confirmPresence(at moment: Date) {
        withTransition {
            guard isEnabled, case .waitingForPresence(let candidate) = state else { return }
            begin(bundleID: candidate.bundleID, name: candidate.appName, at: moment)
        }
    }

    private func begin(bundleID: String, name: String, at moment: Date) {
        let appName = name.isEmpty ? bundleID : name
        setState(.active(ActiveSegment(id: UUID(), bundleID: bundleID,
                                      appName: appName, start: moment,
                                      lastPersistedEnd: moment)))
    }

    /// The machine came back. Reopens tracking for whatever is frontmost, because
    /// waking and carrying on in the *same* app posts no activation notification —
    /// that work was simply never recorded.
    func resume(bundleID: String?, name: String) {
        withTransition {
            guard isEnabled, !isObserving, let bundleID, bundleID != ownBundleID,
                  !AppUsageArchive.systemProcesses.contains(bundleID) else { return }
            begin(bundleID: bundleID, name: name, at: now())
        }
    }

    private func setState(_ next: TrackingState) {
        state = next
        markTransition()
    }

    private func markTransition() {
        transitionChanged = true
    }

    /// Wall-clock regression is not evidence that durable usage should shrink.
    /// Only an idle-derived boundary carries explicit evidence of an earlier
    /// end and may move behind the last persisted checkpoint.
    private func safeEnd(for segment: ActiveSegment,
                         candidate: Date,
                         permitsRollback: Bool) -> Date {
        let bounded = max(segment.start, candidate)
        return permitsRollback ? bounded : max(segment.lastPersistedEnd, bounded)
    }

    private func withTransition(_ body: () -> Void) {
        let outermost = !isTransitioning
        if outermost {
            isTransitioning = true
            transitionChanged = false
        }
        body()
        guard outermost else { return }
        let shouldPublish = transitionChanged
        transitionChanged = false
        isTransitioning = false
        if shouldPublish { onDidTransition?() }
    }
}
