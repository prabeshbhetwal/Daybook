import Foundation

extension SessionEngine {

    // MARK: - Transition table (§3.1)

    func transition(on event: SessionEvent) {
        transitionRevision &+= 1
        lastLongAwayTransition = nil
        let previous = state
        var forceEmit = false

        // Each handler returns whether to emit without a state change, or nil
        // when it has already reported and the transition stops there.
        let emits: Bool?
        switch state {
        case .idle: emits = transitionFromIdle(on: event)
        case .running: emits = transitionFromRunning(on: event)
        case .paused: emits = transitionFromPaused(on: event)
        case .awaitingUserDecision: emits = transitionFromAwaitingDecision(on: event)
        }
        guard let emits else { return }
        forceEmit = emits

        if case .refused = lastLongAwayTransition?.outcome { forceEmit = true }
        if state != previous || forceEmit {
            persist()
            onStateChanged?(state)
        }
        if case .awaitingUserDecision(let away, let app) = state, state != previous {
            onNeedsDecision?(away, app)
        }
    }

    /// §3.1 rows for `.idle`.
    func transitionFromIdle(on event: SessionEvent) -> Bool? {
        var forceEmit = false
        switch (state, event) {

        // .idle
        case (.idle, .launch):
            beginFreshSession()
        case (.idle, .appActivated(let bundleID, let name)):
            recordApp(bundleID: bundleID, name: name)
            // Only the explicitly enabled legacy heuristic owns activation-
            // based starts. Rule automation waits for its evidenced deadline;
            // all-off records foreground use without starting focus.
            if store.automationMode == .legacyHeuristic,
               categories.category(for: bundleID) == .work { beginFreshSession() }
        case (.idle, .resetSession):
            beginFreshSession()
            forceEmit = true
        case (.idle, .markedAway), (.idle, .idleObserved):
            break // nothing to pause; the coordinator still stops recording
        case (.idle, _):
            break // documented no-op: nothing runs before the session starts
        default:
            break // unreachable: every row for this state is listed above
        }
        return forceEmit
    }

    /// §3.1 rows for `.running`.
    func transitionFromRunning(on event: SessionEvent) -> Bool? {
        var forceEmit = false
        switch (state, event) {

        // .running
        case (.running, .awayBegan(let trigger)):
            recordAway(trigger)
        case (.running, .awayEnded):
            resolveAway()
        case (.running, .appActivated(let bundleID, let name)):
            if isSelf(bundleID) { break }   // our own alert must not cancel a dwell
            recordApp(bundleID: bundleID, name: name)
            cancelDwell()
            if categories.category(for: bundleID) == .breakTime, let bundleID {
                scheduleDwell(for: bundleID)
            }
        case (.running, .dwellExpired(let bundleID)):
            if currentAppBundleID == bundleID,
               categories.category(for: bundleID) == .breakTime {
                enterPause(reason: .distractionApp(bundleID: bundleID))
            }
        case (.running, .overrideApplied(let bundleID)):
            if currentAppBundleID == bundleID,
               categories.category(for: bundleID) == .breakTime {
                cancelDwell()
                enterPause(reason: .distractionApp(bundleID: bundleID))
            }
        case (.running, .manualPause):
            enterPause(reason: .manual)
        case (.running, .markedAway):
            enterPause(reason: .away)
        case (.running, .idleObserved(let seconds)):
            if seconds < FocusConstants.awayDebounce, awayInterval != nil {
                // Confirmed input with an absence open: the person is back.
                // This is the only trustworthy end an unlocked absence has —
                // wakes are the machine's.
                resolveAway()
            } else if seconds >= store.idlePauseThreshold {
                enterPause(reason: .idle, at: now().addingTimeInterval(-seconds))
            }
        case (.running, .watchingObserved(let seconds)):
            // Quiet, but watched: something on screen is keeping the display
            // awake. Nobody left, so this is never an absence to ask about. In
            // a session whose work is attending — Meetings, Learning — it is
            // the work; anywhere else the clock stops quietly, back-dated to
            // the last input like an idle pause.
            if seconds >= store.idlePauseThreshold, !activeWorkType.countsWhileWatching {
                enterPause(reason: .watching, at: now().addingTimeInterval(-seconds))
            }
        case (.running, .resetSession):
            guard archiveCurrentSession() else { onStateChanged?(state); return nil }
            beginFreshSession()
            forceEmit = true
        case (.running, .launch), (.running, .manualResume), (.running, .decision):
            break // documented no-op: already running
        default:
            break // unreachable: every row for this state is listed above
        }
        return forceEmit
    }

    /// §3.1 rows for `.awaitingUserDecision`: record, never transition (D10).
    func transitionFromAwaitingDecision(on event: SessionEvent) -> Bool? {
        var forceEmit = false
        switch (state, event) {

        // .awaitingUserDecision — record, never transition (D10)
        case (.awaitingUserDecision, .decision(let decision)):
            apply(decision)
        case (.awaitingUserDecision, .resetSession):
            guard archiveCurrentSession() else { onStateChanged?(state); return nil }
            beginFreshSession()
            forceEmit = true
        case (.awaitingUserDecision, .appActivated(let bundleID, let name)):
            if isSelf(bundleID) { break }
            recordApp(bundleID: bundleID, name: name)
        case (.awaitingUserDecision, .awayBegan(let trigger)):
            // Once the stretch is held at a second absence past the cap,
            // nothing after it belongs to the session.
            if pauseStartDate == nil { recordAway(trigger) }
        case (.awaitingUserDecision, .awayEnded):
            // The card owns the pending question, but a second absence that
            // ends while it is up is a fact about time, not about the question
            // — bank it so `apply` can exclude it from whichever session
            // continues. Past the cap there is no session left to continue:
            // it is held there until the answer, which is still kept.
            if secondAbsenceOutgrewCap() != nil {
                holdSecondAbsence()
            } else if let interval = awayInterval {
                shadowAway += self.interval(from: interval.start)
                awayInterval = nil
                persist()
            }
        case (.awaitingUserDecision, .markedAway):
            // Saying "I am away" answers the pending question in the same breath:
            // the gap was a break, and this one is too.
            apply(.continueSession)
            if state == .running { enterPause(reason: .away) }
        case (.awaitingUserDecision, .manualResume):
            // Manual escape hatch: if the alert was suppressed (D10) or dismissed
            // without an answer, the menu must still be able to free the session.
            // Resuming by hand is the conservative reading — the break is discarded.
            apply(.continueSession)
        case (.awaitingUserDecision, .idleObserved(let seconds)):
            noteQuietWhileAwaiting(seconds)
        case (.awaitingUserDecision, .watchingObserved(let seconds)):
            if !activeWorkType.countsWhileWatching { noteQuietWhileAwaiting(seconds) }
        case (.awaitingUserDecision, .launch),
             (.awaitingUserDecision, .dwellExpired), (.awaitingUserDecision, .manualPause),
             (.awaitingUserDecision, .overrideApplied):
            break // documented no-op: the alert owns the next transition
        default:
            break // unreachable: every row for this state is listed above
        }
        return forceEmit
    }
}
