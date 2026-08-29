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

    private enum PendingContinuation {
        case stopped
        case waitingForPresence(ResumeCandidate)
        case active(ActiveSegment)
    }

    private struct PendingClose {
        let session: AppUsageSession
        let lastPersistedEnd: Date
    }

    private struct PendingPersistence {
        var closes: [PendingClose]
        var continuation: PendingContinuation
    }

    private enum TrackingState {
        case stopped
        case active(ActiveSegment)
        case pendingPersistence(PendingPersistence)
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
    private func effectiveEnd(at moment: Date) -> (end: Date, trimmed: Bool) {
        let idleFor = idle.idleSeconds()
        guard idleFor >= AppUsageTracker.idleCutoff else { return (moment, false) }
        return (moment.addingTimeInterval(-idleFor), true)
    }

    private func effectiveEnd() -> (end: Date, trimmed: Bool) {
        effectiveEnd(at: now())
    }

    /// The app that is frontmost right now, if tracking is running.
    var currentBundleID: String? {
        switch state {
        case .active(let segment):
            return segment.bundleID
        case .pendingPersistence(let pending):
            guard case .active(let segment) = pending.continuation else { return nil }
            return segment.bundleID
        case .stopped, .waitingForPresence:
            return nil
        }
    }

    /// Whether the tracker needs the store's existing ticker to keep sampling.
    /// Waiting for a confirmed return remains observable so same-app input can
    /// reach the presence gate; it still accrues no usage on its own.
    var isObserving: Bool {
        switch state {
        case .active, .pendingPersistence, .waitingForPresence: return true
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
        let segment: ActiveSegment
        switch state {
        case .active(let active):
            segment = active
        case .pendingPersistence(let pending):
            guard case .active(let active) = pending.continuation else { return 0 }
            segment = active
        case .stopped, .waitingForPresence:
            return 0
        }
        let candidate = effectiveEnd()
        let end = safeEnd(for: segment, candidate: candidate.end,
                          permitsRollback: candidate.trimmed)
        return max(0, end.timeIntervalSince(segment.start))
    }

    /// The portion of the active stretch not already represented by its stable
    /// archive checkpoint. Combining this with `usage.totalToday()` therefore
    /// never counts a saved prefix twice.
    func unpersistedSeconds() -> TimeInterval {
        unpersistedSessions().reduce(0) { $0 + $1.seconds }
    }

    /// The live tail not represented by the stable archive checkpoint. Exposing
    /// the interval, rather than only its scalar, lets focused-active reporting
    /// intersect it and lets day totals clip it at local midnight.
    func unpersistedSession() -> AppUsageSession? {
        unpersistedSessions().last
    }

    /// Every disjoint interval not yet represented by the archive. A storage
    /// outage can leave several frozen tails ahead of the live continuation;
    /// interval consumers must receive all of them rather than only the newest.
    func unpersistedSessions() -> [AppUsageSession] {
        switch state {
        case .active(let segment):
            return liveTail(for: segment).map { [$0] } ?? []
        case .pendingPersistence(let pending):
            var sessions = pending.closes.compactMap(unpersistedTail(for:))
            if case .active(let segment) = pending.continuation,
               let live = liveTail(for: segment) {
                sessions.append(live)
            }
            return sessions
        case .stopped, .waitingForPresence:
            return []
        }
    }

    private func liveTail(for segment: ActiveSegment) -> AppUsageSession? {
        let candidate = effectiveEnd()
        let end = safeEnd(for: segment, candidate: candidate.end,
                          permitsRollback: candidate.trimmed)
        let start = max(segment.start, segment.lastPersistedEnd)
        guard end > start else { return nil }
        return AppUsageSession(id: segment.id, bundleID: segment.bundleID,
                               appName: segment.appName, start: start, end: end,
                               endReason: candidate.trimmed ? .idle : .stillOpen)
    }

    private func unpersistedTail(for pending: PendingClose) -> AppUsageSession? {
        let start = max(pending.session.start, pending.lastPersistedEnd)
        guard pending.session.end > start else { return nil }
        return AppUsageSession(id: pending.session.id,
                               bundleID: pending.session.bundleID,
                               appName: pending.session.appName,
                               start: start, end: pending.session.end,
                               endReason: pending.session.endReason)
    }

    /// The unpersisted tail's literal overlap with one local day.
    func unpersistedSeconds(on day: Date,
                            calendar: Calendar = .current) -> TimeInterval {
        guard let bounds = SessionRecord.dayBounds(day, calendar: calendar) else { return 0 }
        return unpersistedSessions().reduce(0) { total, session in
            let start = max(session.start, bounds.start)
            let end = min(session.end, bounds.end)
            return end > start ? total + end.timeIntervalSince(start) : total
        }
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
            switch state {
            case .active:
                _ = finaliseActiveSegment(reason: .systemLock, at: now(),
                                          continuation: .stopped)
            case .pendingPersistence(let pending):
                if case .active(let segment) = pending.continuation {
                    queuePendingActiveClose(segment, reason: .systemLock, at: now(),
                                            continuation: .stopped)
                } else if case .waitingForPresence = pending.continuation {
                    _ = retryPendingCloses()
                } else {
                    _ = retryPendingCloses()
                }
            case .stopped, .waitingForPresence:
                break
            }
            return
        }
        let candidate = ResumeCandidate(bundleID: bundleID,
                                        appName: name.isEmpty ? bundleID : name)
        if case .pendingPersistence(let pending) = state {
            switch pending.continuation {
            case .waitingForPresence:
                updatePendingContinuation(.waitingForPresence(candidate))
                _ = retryPendingCloses()
            case .stopped:
                updatePendingContinuation(.active(makeActiveSegment(
                    bundleID: candidate.bundleID, name: candidate.appName, at: now())))
                _ = retryPendingCloses()
            case .active(let segment):
                if segment.bundleID == bundleID {
                    _ = retryPendingCloses()
                } else {
                    let moment = now()
                    let next = makeActiveSegment(bundleID: candidate.bundleID,
                                                 name: candidate.appName, at: moment)
                    queuePendingActiveClose(segment, reason: .appSwitch, at: moment,
                                            continuation: .active(next))
                }
            }
            return
        }
        if case .waitingForPresence = state {
            setState(.waitingForPresence(candidate))
            return
        }
        if case .active(let segment) = state, segment.bundleID == bundleID { return }

        if case .active = state {
            let moment = now()
            let next = makeActiveSegment(bundleID: candidate.bundleID,
                                         name: candidate.appName, at: moment)
            _ = finaliseActiveSegment(reason: .appSwitch, at: moment,
                                      continuation: .active(next))
        } else {
            begin(bundleID: bundleID, name: name, at: now())
        }
    }

    /// The user went away — lock, sleep or power off. Time spent away is not
    /// usage, so the stretch ends here rather than running until they return.
    func suspend() {
        withTransition { stopTracking(reason: .systemLock) }
    }

    private func stopTracking(reason: UsageEndReason) {
        switch state {
        case .active:
            _ = finaliseActiveSegment(reason: reason, at: now(),
                                      continuation: .stopped)
        case .pendingPersistence(let pending):
            if case .active(let segment) = pending.continuation {
                queuePendingActiveClose(segment, reason: reason, at: now(),
                                        continuation: .stopped)
            } else {
                updatePendingContinuation(.stopped)
                _ = retryPendingCloses()
            }
        case .stopped, .waitingForPresence:
            setState(.stopped)
        }
    }

    @discardableResult
    private func finaliseActiveSegment(reason: UsageEndReason,
                                       at moment: Date,
                                       continuation: PendingContinuation) -> Bool {
        guard case .active(let segment) = state else { return true }
        let session = terminalSession(for: segment, reason: reason, at: moment)
        guard archive.checkpoint(session) else {
            setState(.pendingPersistence(PendingPersistence(
                closes: [PendingClose(session: session,
                                      lastPersistedEnd: segment.lastPersistedEnd)],
                continuation: continuation)))
            return false
        }
        resolve(continuation)
        return true
    }

    private func terminalSession(for segment: ActiveSegment,
                                 reason: UsageEndReason,
                                 at moment: Date) -> AppUsageSession {
        let (candidate, wasTrimmed) = effectiveEnd(at: moment)
        let end = safeEnd(for: segment, candidate: candidate,
                          permitsRollback: wasTrimmed)
        // Idle trimming outranks the nominal reason: the stretch really ended
        // when input stopped, not when the app changed.
        return AppUsageSession(id: segment.id,
                               bundleID: segment.bundleID,
                               appName: segment.appName,
                               start: segment.start,
                               end: end,
                               endReason: wasTrimmed ? .idle : reason)
    }

    private func queuePendingActiveClose(_ segment: ActiveSegment,
                                         reason: UsageEndReason,
                                         at moment: Date,
                                         continuation: PendingContinuation) {
        guard case .pendingPersistence(var pending) = state else { return }
        pending.closes.append(PendingClose(
            session: terminalSession(for: segment, reason: reason, at: moment),
            lastPersistedEnd: segment.lastPersistedEnd))
        pending.continuation = continuation
        setState(.pendingPersistence(pending))
        _ = retryPendingCloses()
    }

    private func updatePendingContinuation(_ continuation: PendingContinuation) {
        guard case .pendingPersistence(var pending) = state else { return }
        pending.continuation = continuation
        setState(.pendingPersistence(pending))
    }

    @discardableResult
    private func retryPendingCloses() -> Bool {
        guard case .pendingPersistence(var pending) = state else { return true }
        while let next = pending.closes.first {
            guard archive.checkpoint(next.session) else { return false }
            pending.closes.removeFirst()
            setState(.pendingPersistence(pending))
        }
        resolve(pending.continuation)
        return true
    }

    private func resolve(_ continuation: PendingContinuation) {
        guard isEnabled else {
            setState(.stopped)
            return
        }
        switch continuation {
        case .stopped:
            setState(.stopped)
        case .waitingForPresence(let candidate):
            setState(.waitingForPresence(candidate))
        case .active(let segment):
            setState(.active(segment))
        }
    }

    /// Flushes the in-flight stretch so queries include it. Called before the
    /// menu bar reads its data, and on terminate.
    func flush() {
        withTransition { flushNow() }
    }

    private func flushNow() {
        if case .pendingPersistence = state {
            _ = retryPendingCloses()
            return
        }
        guard case .active(var segment) = state else { return }
        let (candidate, wasTrimmed) = effectiveEnd()
        let end = safeEnd(for: segment, candidate: candidate,
                          permitsRollback: wasTrimmed)
        let session = AppUsageSession(id: segment.id,
                                      bundleID: segment.bundleID,
                                      appName: segment.appName,
                                      start: segment.start,
                                      end: end,
                                      endReason: wasTrimmed ? .idle : .stillOpen)
        guard archive.checkpoint(session) else {
            if wasTrimmed {
                setState(.pendingPersistence(PendingPersistence(
                    closes: [PendingClose(session: session,
                                          lastPersistedEnd: segment.lastPersistedEnd)],
                    continuation: .waitingForPresence(ResumeCandidate(
                        bundleID: segment.bundleID, appName: segment.appName)))))
            }
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
        guard seconds >= AppUsageTracker.idleCutoff else { return }
        let segment: ActiveSegment
        let wasPending: Bool
        switch state {
        case .active(let active):
            segment = active
            wasPending = false
        case .pendingPersistence(let pending):
            guard case .active(let active) = pending.continuation else { return }
            segment = active
            wasPending = true
        case .stopped, .waitingForPresence:
            return
        }
        let session = idleSession(for: segment, seconds: seconds, at: now())
        let candidate = ResumeCandidate(bundleID: segment.bundleID,
                                        appName: segment.appName)
        if wasPending {
            guard case .pendingPersistence(var pending) = state else { return }
            pending.closes.append(PendingClose(
                session: session, lastPersistedEnd: segment.lastPersistedEnd))
            pending.continuation = .waitingForPresence(candidate)
            setState(.pendingPersistence(pending))
            _ = retryPendingCloses()
            return
        }
        guard archive.checkpoint(session) else {
            setState(.pendingPersistence(PendingPersistence(
                closes: [PendingClose(session: session,
                                      lastPersistedEnd: segment.lastPersistedEnd)],
                continuation: .waitingForPresence(candidate))))
            return
        }
        setState(.waitingForPresence(candidate))
    }

    private func idleSession(for segment: ActiveSegment,
                             seconds: TimeInterval,
                             at moment: Date) -> AppUsageSession {
        AppUsageSession(id: segment.id,
                        bundleID: segment.bundleID,
                        appName: segment.appName,
                        start: segment.start,
                        end: max(segment.start, moment.addingTimeInterval(-seconds)),
                        endReason: .idle)
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
        let candidate = ResumeCandidate(bundleID: bundleID,
                                        appName: name.isEmpty ? bundleID : name)
        if case .pendingPersistence(let pending) = state {
            if case .active = pending.continuation {
                _ = retryPendingCloses()
                return
            }
            updatePendingContinuation(.waitingForPresence(candidate))
            _ = retryPendingCloses()
            return
        }
        if case .waitingForPresence = state {
            setState(.waitingForPresence(candidate))
            return
        }
        guard !isObserving else { return }
        setState(.waitingForPresence(candidate))
    }

    /// Starts a fresh, independently correctable stretch after a caller has
    /// established that a person is actually back at the Mac.
    func confirmPresence(at moment: Date) {
        withTransition {
            guard isEnabled else { return }
            switch state {
            case .waitingForPresence(let candidate):
                begin(bundleID: candidate.bundleID, name: candidate.appName, at: moment)
            case .pendingPersistence(let pending):
                guard case .waitingForPresence(let candidate) = pending.continuation else { return }
                updatePendingContinuation(.active(makeActiveSegment(
                    bundleID: candidate.bundleID, name: candidate.appName, at: moment)))
                _ = retryPendingCloses()
            case .stopped, .active:
                return
            }
        }
    }

    private func begin(bundleID: String, name: String, at moment: Date) {
        setState(.active(makeActiveSegment(bundleID: bundleID, name: name, at: moment)))
    }

    private func makeActiveSegment(bundleID: String,
                                   name: String,
                                   at moment: Date) -> ActiveSegment {
        let appName = name.isEmpty ? bundleID : name
        return ActiveSegment(id: UUID(), bundleID: bundleID,
                             appName: appName, start: moment,
                             lastPersistedEnd: moment)
    }

    /// The machine came back. Reopens tracking for whatever is frontmost, because
    /// waking and carrying on in the *same* app posts no activation notification —
    /// that work was simply never recorded.
    func resume(bundleID: String?, name: String) {
        withTransition {
            guard isEnabled, let bundleID, bundleID != ownBundleID,
                  !AppUsageArchive.systemProcesses.contains(bundleID) else { return }
            if case .pendingPersistence(let pending) = state {
                if case .active = pending.continuation {
                    _ = retryPendingCloses()
                    return
                }
                let candidate = ResumeCandidate(bundleID: bundleID,
                                                appName: name.isEmpty ? bundleID : name)
                updatePendingContinuation(.active(makeActiveSegment(
                    bundleID: candidate.bundleID, name: candidate.appName, at: now())))
                _ = retryPendingCloses()
                return
            }
            guard !isObserving else { return }
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
