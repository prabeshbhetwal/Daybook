import Foundation

extension SessionEngine {
    // MARK: - Side effects

    func beginFreshSession() {
        // Every start from idle comes through here: Start, a quick start,
        // History's Continue, the legacy work-app start. A retired category is
        // offered nowhere new, so none of them may begin one. A stretch that
        // carries on after a break keeps the category it was running under.
        if state == .idle { activeWorkType = activeWorkType.startableOrFallback }
        // A session begun by activation is the user's, not the app's guess.
        activeIsAuto = false
        activeAutomaticAction = nil
        cancelDwell()
        sessionStartDate = now()
        totalPausedDuration = 0
        pausedSpans = []
        pauseStartDate = nil
        awayInterval = nil
        shadowAway = 0
        decisionStartDate = nil
        awayReturnedAt = nil
        pendingDecisionID = nil
        workBeforePendingAway = nil
        activeRecordID = UUID()
        state = .running
    }

    /// - Parameter moment: when the pause really began. Idle pauses are
    ///   backdated to the last keypress, so the interval that proves the user is
    ///   gone is excluded along with the rest of the absence. Clamped forward to
    ///   `now()` so a bad sample can never place a pause in the future.
    func enterPause(reason: PauseReason, at moment: Date? = nil) {
        cancelDwell()
        pauseStartDate = min(moment ?? now(), now())
        state = .paused(reason: reason)
    }

    func leavePause() {
        if let start = pauseStartDate {
            let end = now()
            totalPausedDuration += interval(from: start)
            addPausedSpan(start, end)
        }
        pauseStartDate = nil
        state = .running
    }

    func addPausedSpan(_ start: Date, _ end: Date) {
        guard end > start else { return }
        pausedSpans.append(DateInterval(start: start, end: end))
    }

    func removePausedSpan(startingAt start: Date, duration: TimeInterval) {
        let end = start.addingTimeInterval(duration)
        guard let index = pausedSpans.firstIndex(where: {
            abs($0.start.timeIntervalSince(start)) <= 1 && abs($0.end.timeIntervalSince(end)) <= 1
        }) else {
            pausedSpans = []
            return
        }
        pausedSpans.remove(at: index)
    }

    func trustedPausedSpans(until end: Date) -> [DateInterval]? {
        var spans = pausedSpans
        if let pauseStartDate, end > pauseStartDate {
            spans.append(DateInterval(start: pauseStartDate, end: end))
        }
        let paused = max(0, end.timeIntervalSince(sessionStartDate) - elapsed(endingAt: end))
        return PauseAllocation.isTrusted(spans, start: sessionStartDate, end: end, pausedTotal: paused)
            ? spans : nil
    }

    /// Ends a declared away. The user said they were leaving, so there is
    /// nothing to ask — but an absence long enough to have been asked about is
    /// a break, and a break ends a stretch: the stretch closes where they left,
    /// the gap is written down as "Away", and the work resumes as a new stretch
    /// on the same thread with its clock at zero — exactly what answering "It
    /// was a break" does. Resuming the same stretch instead read "45 minutes"
    /// to someone who had been back for four. A shorter away stays a pause.
    func endDeclaredAway() {
        guard let began = pauseStartDate else {
            state = .running
            return
        }
        let absence = interval(from: began)
        if absence < breakThreshold {
            leavePause()
            return
        }
        let thread = activeThreadID
        // `elapsed` already subtracts the live pause, so the record carries
        // exactly the work done before they left.
        guard archiveCurrentSession(endingAt: began) else { return }
        if absence >= store.minimumRecordedSession {
            // Logged, not put in awayDecisionError: that field means an ending
            // awaits finalisation, and a stale value would start a false retry.
            if let error = archive.append(SessionRecord(name: "Away", workType: .breakTime,
                                                        start: began, end: now(), workSeconds: absence,
                                                        threadID: UUID())) {
                Diagnostics.log("an Away rest could not be saved: \(error)")
            }
        }
        beginFreshSession()
        activeThreadID = thread
    }

    /// Ends a watching pause. Quiet — nobody left, nothing to ask. The stretch
    /// is banked like any pause and, when it lasted at least `breakThreshold`,
    /// written down as a rest named "Watching", so the timeline and the
    /// Sessions card can say where the evening went instead of showing a gap.
    /// `endingAt` closes it earlier than now when the watching stopped a while
    /// ago and the seconds since belong to whatever pause follows.
    func endWatchingPause(endingAt moment: Date? = nil) {
        cancelDwell()
        let end = min(moment ?? now(), now())
        if let began = pauseStartDate {
            let watched = max(0, end.timeIntervalSince(began))
            totalPausedDuration += watched
            addPausedSpan(began, end)
            if watched >= store.breakThreshold {
                if let error = archive.append(SessionRecord(name: "Watching", workType: .breakTime,
                                                            start: began, end: end, workSeconds: watched,
                                                            threadID: UUID())) {
                    Diagnostics.log("a Watching rest could not be saved: \(error)")
                }
            }
        }
        pauseStartDate = nil
        state = .running
    }

    /// Ends an idle pause because input has returned.
    ///
    /// An idle pause is the app's own observation, not the user's act, so its
    /// end is resolved the way any observed absence is — through
    /// `resolve(away:)`: excluded either way, asked about past `breakThreshold`,
    /// ended past the cap (callers judge the cap first). It used to resume
    /// silently at any length, so a forty-minute absence with the screen never
    /// locked was never asked about while the same forty minutes behind a lock
    /// was — and the settings explainer promised the question for both. The
    /// live pause is lifted *without* banking it: `resolve` banks the same
    /// seconds itself.
    func endIdlePause() {
        guard let began = pauseStartDate else {
            state = .running
            return
        }
        let absence = interval(from: began)
        pauseStartDate = nil
        state = .running
        resolve(away: absence, startedAt: began)
    }
}
