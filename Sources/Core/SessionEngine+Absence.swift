import Foundation

extension SessionEngine {
    /// True when an unattended pause has outgrown `longAwayCap`. A `.manual`
    /// pause used to be exempt, as a deliberate act about a session the user
    /// was still sitting in front of. Past the cap that stops being true: a
    /// Pause left on over a quit and a night made one record of 22:46 to 11:02.
    /// Pressing Pause keeps the session only as long as any other absence.
    func absenceOutgrewCap() -> Bool {
        guard case .paused(let reason) = state, Self.pauseMeansNobodyHere(reason),
              let began = pauseStartDate else { return false }
        return interval(from: began) >= store.longAwayCap
    }

    /// Whether a pause says nobody is at the session. Two do not: a break app
    /// the user is looking at, and something on screen they are watching.
    /// Both end with the user's own next move, not with the cap.
    static func pauseMeansNobodyHere(_ reason: PauseReason) -> Bool {
        switch reason {
        case .distractionApp, .watching: return false
        case .manual, .away, .idle, .systemSleep, .extendedBreak: return true
        }
    }

    /// Ends a session whose absence outgrew the cap, archived where the absence
    /// began — the same shape as the lock path in `resolve(away:)`. `elapsed`
    /// already subtracts the live pause, so the record's work is exactly what
    /// was done before they left.
    func endAbsentSession() -> LongAwayTransitionOutcome {
        let began = pauseStartDate
        guard archiveCurrentSession(endingAt: began) else {
            return .refused(awayDecisionError ?? "The terminal checkpoint could not be saved.")
        }
        cancelDwell()
        pauseStartDate = nil
        awayInterval = nil
        shadowAway = 0
        decisionStartDate = nil
        awayReturnedAt = nil
        activeIsAuto = false
        activeAutomaticAction = nil
        state = .idle
        if let error = awayDecisionError { return .pendingFinalisation(error) }
        return .completed
    }

    @discardableResult
    func completeLongAway(intent: LongAwayCompletionIntent) -> LongAwayTransitionResult {
        let request = LongAwayTransitionRequest(threadID: activeThreadID, sessionStart: sessionStartDate,
            state: state, name: sessionName, workType: activeWorkType, bundleID: currentAppBundleID,
            transitionRevision: transitionRevision, intent: intent)
        let outcome = endAbsentSession()
        if outcome.applied, intent == .beginFreshSession { beginFreshSession() }
        let result = LongAwayTransitionResult(request: request, outcome: outcome)
        lastLongAwayTransition = result
        return result
    }

    /// Ends a stretch nobody has been at since `left`, through the one
    /// long-away ending. Used where the absence is found some other way than
    /// a pause outgrowing the cap: the app was closed across it, `resolve` is
    /// only now measuring it, or a question sat through it. Whatever the
    /// stretch was doing, it becomes what it really was, an away pause from
    /// `left`. The record then ends there with exactly the work before it, and
    /// a refused save leaves that pause standing with its Retry, the cap judged
    /// again on the next event. A live stretch with the absence banked would
    /// instead carry on, and count it as work the next time it resumed.
    /// A pending question goes with the stretch, unanswered, as it does when a
    /// session is ended with the card up. An absence past the cap is never
    /// asked about.
    func endStretch(leftAt left: Date) {
        // Second absences the card already sat through stay excluded, as any
        // answer would have excluded them.
        totalPausedDuration += shadowAway
        shadowAway = 0
        awayInterval = nil
        decisionStartDate = nil
        awayReturnedAt = nil
        pendingDecisionID = nil
        workBeforePendingAway = nil
        departureApp = nil
        pendingAwayLabel = nil
        pauseStartDate = min(left, now())
        state = .paused(reason: .away)
        completeLongAway(intent: .endOnly)
    }

    /// Where a second absence the question sat through began, once it has
    /// outgrown the cap. Past that it is no longer a pause inside the question
    /// but the end of the session, as it would have been with no question up.
    /// An answer given afterwards must not continue a stretch across it.
    func secondAbsenceOutgrewCap() -> Date? {
        guard case .awaitingUserDecision = state, let began = awayInterval?.start,
              interval(from: began) >= store.longAwayCap else { return nil }
        return began
    }

    /// Stops the stretch at a second absence past the cap without dropping
    /// the question it sat through. The absence becomes a live pause from
    /// where it began — `elapsed` subtracts it, so nothing after it is work —
    /// and the question stays up. Its answer is applied as usual, receipt and
    /// break included, and then `apply` ends the stretch there. Only an
    /// awaiting stretch held this way has a `pauseStartDate`.
    func holdSecondAbsence() {
        guard let left = secondAbsenceOutgrewCap() else { return }
        awayInterval = nil
        pauseStartDate = left
        persist()
    }

    @discardableResult
    func retryLongAwayTransition(_ request: LongAwayTransitionRequest) -> LongAwayTransitionResult {
        guard transitionRevision == request.transitionRevision, state == request.state,
              activeThreadID == request.threadID, sessionStartDate == request.sessionStart,
              sessionName == request.name, activeWorkType == request.workType,
              currentAppBundleID == request.bundleID, absenceOutgrewCap() else {
            let error = "That Retry belongs to an earlier paused stretch. Current work was preserved."
            awayDecisionError = error
            let result = LongAwayTransitionResult(request: request, outcome: .refused(error))
            lastLongAwayTransition = result
            return result
        }
        let result = completeLongAway(intent: request.intent)
        persist()
        onStateChanged?(state)
        return result
    }

    func isSelf(_ bundleID: String?) -> Bool {
        guard let bundleID, let ownBundleID else { return false }
        return bundleID == ownBundleID
    }

    func recordApp(bundleID: String?, name: String) {
        if isSelf(bundleID) { return }
        currentAppBundleID = bundleID
        currentAppName = name.isEmpty ? "—" : name
        // Neither field changes `state`, so the emit block will not persist for
        // us — write through here or the snapshot goes stale between transitions.
        persist()
    }

    /// The card blocks nothing, so the minutes it sits there are ordinary
    /// minutes — unless nobody is here. Quiet past the idle threshold while a
    /// question is pending is a second absence the card sat through, opened
    /// back-dated to the last input and banked like a lock would be, so that
    /// whichever session the answer continues cannot count it. Input closes
    /// it. Without this, a question left up over a forty-minute errand handed
    /// the errand to the session that started when the user came back.
    func noteQuietWhileAwaiting(_ seconds: TimeInterval) {
        // Judged first, whatever this sample says, as for a paused stretch.
        if secondAbsenceOutgrewCap() != nil { holdSecondAbsence() }
        // Held: the stretch already stops there, so later quiet is nobody's.
        guard pauseStartDate == nil else { return }
        if seconds >= store.idlePauseThreshold {
            guard awayInterval == nil else { return }
            awayInterval = (start: now().addingTimeInterval(-seconds), trigger: .idle)
            persist()
        } else if let interval = awayInterval {
            // Confirmed input closes whatever absence the card sat through —
            // idle-opened or a sleep whose wake was only ever the machine's.
            shadowAway += self.interval(from: interval.start)
            awayInterval = nil
            persist()
        }
    }

    /// D8 — the first away event wins; later ones are ignored while one is open.
    func recordAway(_ trigger: AwayTrigger) {
        guard awayInterval == nil else { return }
        awayInterval = (start: now(), trigger: trigger)
        // Persist immediately so a power loss while locked still knows when the
        // away interval began, rather than falling back to the last transition.
        persist()
    }

    /// D7/D8/D9 — idempotent resolution of a single away interval.
    func resolveAway() {
        guard let interval = awayInterval else { return }
        awayInterval = nil
        resolve(away: self.interval(from: interval.start), startedAt: interval.start)
    }

    func resolve(away: TimeInterval, startedAt: Date? = nil) {
        if away < FocusConstants.awayDebounce { return }
        // An absence this long was not a break inside a session, it was the end
        // of one. Keeping the session open across it is what produced records
        // spanning thirty-two hours, and a record that covers two nights has to
        // guess which day its work belongs to no matter how the guess is made.
        // There is also nothing to ask: nobody answers "was that a break?" about
        // a night's sleep with "I was working". Judged before the absence is
        // banked, so a refused save leaves it the pause the session ends in,
        // with its Retry, not a running session that said nothing.
        if away >= breakThreshold, away >= store.longAwayCap {
            endStretch(leftAt: now().addingTimeInterval(-away))
            return
        }
        // Excluded the instant it is noticed, whether or not anyone answers.
        // Leaving it in the total until the card was dismissed meant an
        // overnight sleep read as nine hours of work on the goal bar — the
        // flattering direction, and the one an unanswered question must never
        // drift towards. `.mergeTime` is what adds it back.
        totalPausedDuration += away
        if let startedAt { addPausedSpan(startedAt, startedAt.addingTimeInterval(away)) }
        if away < breakThreshold {
            persist()
            return
        }
        cancelDwell()

        decisionStartDate = now()
        awayReturnedAt = decisionStartDate
        pendingDecisionID = UUID()
        workBeforePendingAway = elapsed
        departureApp = currentAppBundleID
        state = .awaitingUserDecision(away: away, lastApp: currentAppName)
    }
}
