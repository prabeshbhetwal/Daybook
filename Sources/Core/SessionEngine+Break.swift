import Foundation

extension SessionEngine {
    // MARK: - Timed breaks

    /// Whether a break may begin now: none is under way, the away question is
    /// not waiting, and the session is not paused because nobody was here.
    /// The popover and the Session menu ask this to offer Take a break only
    /// where `startBreak` would accept it.
    var canStartBreak: Bool {
        guard activeBreak == nil else { return false }
        switch state {
        case .awaitingUserDecision, .paused(.away), .paused(.idle), .paused(.systemSleep): return false
        case .paused, .idle, .running: return true
        }
    }

    /// Begins a break of `length` seconds. Refused (false) while one is
    /// already under way, while the away question waits, and while the session
    /// is paused because nobody was here (away, idle, asleep): those are
    /// absences with their own accounting, not a break anyone started.
    ///
    /// A running session pauses as `.onBreak`; the pause it was already in
    /// (Pause, a break app, a film) is left first, the way Resume leaves it.
    /// With no session the break stands alone and nothing starts. It does
    /// not emit `onStateChanged`: the caller refreshes, as for a transition.
    @discardableResult
    func startBreak(length: TimeInterval, label: String? = nil) -> Bool {
        guard canStartBreak, length.isFinite, length > 0 else { return false }
        let planned = min(length, BreakLength.maximum)
        if case .paused = state {
            // Not `transition(on:)`: that would announce a running state that
            // lasts no time. A refused save leaves the pause standing.
            _ = transitionFromPaused(on: .manualResume)
            guard state == .running else { return false }
        }
        // What `transition(on:)` does before any event: a new moment, so the
        // result of an earlier long absence is not shown again beside the break.
        transitionRevision &+= 1
        lastLongAwayTransition = nil
        let began = now()
        let typed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        activeBreak = ActiveBreak(start: began, plannedEnd: began.addingTimeInterval(planned),
                                  label: typed?.isEmpty == false ? typed : nil,
                                  threadID: state == .running ? activeThreadID : nil)
        if state == .running { enterPause(reason: .onBreak) }
        persist()
        return true
    }

    /// Adds time to the break, up to `BreakLength.maximum` in all. The
    /// break-over prompt is due again at the new end, so it is no longer
    /// noticed.
    func extendBreak(by seconds: TimeInterval) {
        guard var brk = activeBreak, seconds.isFinite, seconds > 0 else { return }
        // The sum is clamped, not just the input: two huge extensions would
        // add up to infinity, which no snapshot can store.
        let length = min(brk.plannedLength + seconds, BreakLength.maximum)
        guard length > brk.plannedLength else { return }
        brk.plannedEnd = brk.start.addingTimeInterval(length)
        brk.overNoticed = false
        activeBreak = brk
        persist()
    }

    /// Records that the break-over prompt has been shown.
    func markBreakOverNoticed() {
        guard var brk = activeBreak, !brk.overNoticed else { return }
        brk.overNoticed = true
        activeBreak = brk
        persist()
    }

    /// Ends the break at `end` (default now), clamped to the break's own span,
    /// and returns the end used. Nil, with the break kept, when there is none
    /// or the stretch it paused could not be saved.
    ///
    /// The stretch closes where the break began and, like `endDeclaredAway`,
    /// work goes on as a new stretch on the same thread, its clock starting at
    /// `end`. With no session behind the break nothing resumes. Emits nothing:
    /// the caller refreshes, as for a transition.
    @discardableResult
    func endBreak(at end: Date? = nil) -> Date? {
        guard let brk = activeBreak else { return nil }
        let moment = max(brk.start, min(end ?? now(), now()))
        if case .paused(.onBreak) = state {
            let thread = activeThreadID
            // A refusal from an earlier try must not outlive a retry that works.
            awayDecisionError = nil
            guard archiveCurrentSession(endingAt: brk.start) else { return nil }
            closeBreak(brk, at: moment)
            beginFreshSession()
            activeThreadID = thread
            sessionStartDate = moment
        } else {
            closeBreak(brk, at: moment)
        }
        persist()
        return moment
    }

    /// Ends a break nobody came back to: `longAwayCap` after its planned end,
    /// not at the moment this notices. Returns that end; nil when the break is
    /// not yet due. The session it paused ends as any long absence ends it,
    /// archived where the break began, and the engine goes idle. A refused
    /// save keeps the break and tries again on the next call.
    @discardableResult
    func expireBreakIfOutgrown() -> Date? {
        guard let brk = activeBreak else { return nil }
        let capEnd = brk.capEnd(longAwayCap: store.longAwayCap)
        guard now() >= capEnd else { return nil }
        if case .paused(.onBreak) = state {
            awayDecisionError = nil
            guard endAbsentSession().applied else { return nil }
        }
        closeBreak(brk, at: capEnd)
        persist()
        return capEnd
    }

    /// Writes the break down and marks it over. Every end goes through here,
    /// including a discard of the session it paused, so `lastEndedBreak` hears
    /// of each.
    func closeBreak(_ brk: ActiveBreak, at end: Date) {
        recordStartedBreak(brk, endingAt: end)
        activeBreak = nil
        lastEndedBreak = EndedBreak(id: brk.id, start: brk.start, end: end)
    }

    /// Writes a started break down at the length it really had, if that is at
    /// least the shortest recorded session. Under the break's own id, so a
    /// break written twice is one record.
    func recordStartedBreak(_ brk: ActiveBreak, endingAt end: Date) {
        let length = end.timeIntervalSince(brk.start)
        guard length >= store.minimumRecordedSession else { return }
        saveRests(adding: SessionRecord(id: brk.id, name: brk.label ?? "Break", workType: .breakTime,
                                        start: brk.start, end: end, workSeconds: length,
                                        threadID: UUID(), breakOrigin: .started,
                                        plannedLength: brk.plannedLength))
    }
}
