import Foundation

extension SessionEngine {
    /// Answers the pending question, optionally naming the break. The store's
    /// one entry point for decisions; `transition(on: .decision)` remains for
    /// tests and for answers without a name.
    @discardableResult
    func decide(_ decision: UserDecision, label: String? = nil) -> Bool {
        guard prepareCorrection() else { return false }
        guard case .awaitingUserDecision = state else { return false }
        awayDecisionError = nil
        pendingAwayLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        transition(on: .decision(decision))
        // An answer to a question held at a second absence past the cap is
        // kept and then ends the session, so idle is a saved answer too.
        return awayDecisionError == nil && !isAwaitingCorrection
    }

    func apply(_ decision: UserDecision) {
        guard case .awaitingUserDecision(let away, _) = state else { return }
        guard prepareCorrection() else { return }
        // Answered before any sample saw the second absence close.
        holdSecondAbsence()
        let heldAt = pauseStartDate
        let before = snapshot()
        let departureBefore = departureApp
        // Capitalised for the record — the timeline shows it as a title — and
        // consumed here whatever the answer, so it cannot leak into a later one.
        let breakName: String = {
            guard let label = pendingAwayLabel, !label.isEmpty else { return "Break" }
            return label.prefix(1).uppercased() + label.dropFirst()
        }()
        pendingAwayLabel = nil
        // Prepare all durable changes before mutating the live state. Answering
        // is presence; any second absence remains excluded, whichever answer wins.
        let shadow = shadowAway + (awayInterval.map { interval(from: $0.start) } ?? 0)
        // Restore restamps the accounting anchor, never the actual absence.
        // Keep both the original range and work already earned before it.
        let returnedAt = awayReturnedAt ?? decisionStartDate
        let awayStarted = returnedAt?.addingTimeInterval(-away)
        let decisionID = pendingDecisionID ?? UUID()
        // Judged before the state changes, because it reads the pending one.
        let keepsThread = returnKeepsThread
        let originalName = sessionName
        let originalThread = activeThreadID
        let originalStart = sessionStartDate
        let availableWork = max(0, elapsed - shadow)
        let beforeSpan = max(0, (awayStarted ?? now()).timeIntervalSince(originalStart))
        let beforeReturn = min(availableWork, beforeSpan, max(0, workBeforePendingAway
            ?? (elapsed - (decisionStartDate.map { interval(from: $0) } ?? 0))))
        let afterReturn = max(0, availableWork - beforeReturn)
        var additions: [SessionRecord] = []
        var breakRecord: SessionRecord?
        if decision != .mergeTime {
            if decision == .tookBreak, let awayStarted,
               away >= store.minimumRecordedSession {
                let record = SessionRecord(id: decisionID, name: breakName, workType: .breakTime,
                    start: awayStarted, end: awayStarted.addingTimeInterval(away),
                    workSeconds: away, threadID: decisionID)
                breakRecord = record
                additions.append(record)
            }
            if beforeReturn >= store.minimumRecordedSession {
                additions.append(SessionRecord(id: activeRecordID,
                    name: originalName, workType: activeWorkType,
                    start: originalStart, end: min(max(awayStarted ?? now(), originalStart), now()),
                    workSeconds: beforeReturn, detectedApp: activeDetectedApp,
                    threadID: originalThread, isAuto: activeIsAuto,
                    pausedSpans: trustedPausedSpans(until: awayStarted ?? now())))
            }
        }
        if let existing = archive.records.first(where: { $0.id == decisionID }),
           existing != breakRecord {
            awayDecisionError = "An answer is already saved for this interval. Its record was preserved."
            return
        }
        if decision == .mergeTime, archive.records.contains(where: {
            $0.id == activeRecordID
        }) {
            awayDecisionError = "The preceding stretch is already saved. Finish the original uncounted answer before changing this interval."
            return
        }
        if let error = validateDecisionEffects(additions) {
            awayDecisionError = error
            return
        }
        awayDecisionError = nil
        let oldPaused = totalPausedDuration
        awayInterval = nil
        shadowAway = 0
        departureApp = nil
        decisionStartDate = nil
        awayReturnedAt = nil
        pendingDecisionID = nil
        workBeforePendingAway = nil

        switch decision {
        case .mergeTime:
            totalPausedDuration -= away   // it was work after all (D12)
            if let awayStarted { removePausedSpan(startingAt: awayStarted, duration: away) }
            // "I was working" answered the *first* gap. A second absence the
            // card sat through was never part of the question and stays
            // excluded.
            totalPausedDuration += shadow
            state = .running

        case .continueSession, .tookBreak, .resetTimer:
            // The session ended when they walked away. Holding it open across
            // the gap made one record span an afternoon, so its elapsed figure
            // measured the span of the work rather than any stretch worked —
            // which is how the hero timer came to read 5h 57m.
            let thread = activeThreadID
            // The earlier stretch was already saved, ending at departure and
            // excluding work since return. Only now publish its successor.
            beginFreshSession()
            // Same work, resumed — unless they said it was something else, or
            // came back into a different app than the one they left in, which
            // is new work. `Continue Today` groups by thread, so this is what
            // keeps an afternoon split by lunch reading as one job, and what
            // keeps the old job one click away when the afternoon moved on.
            let continues = decision != .resetTimer && keepsThread
            activeThreadID = continues ? thread : UUID()
            if !continues { store.sessionName = "" }
            // Answering is not the start of the work — coming back was.
            if let returnedAt { sessionStartDate = returnedAt }
            // Retain work done after the real return, including work observed
            // before a relaunch. Closed-app time and secondary absence stay out.
            totalPausedDuration = max(0, interval(from: sessionStartDate) - afterReturn)
            pausedSpans = []
        }
        // Whatever the path, the books must balance: a session cannot have
        // been paused for longer than it has existed. Without this, banked
        // absence landing on a young session pinned its clock at zero for
        // as long as the excess lasted.
        totalPausedDuration = max(0, min(totalPausedDuration, interval(from: sessionStartDate)))
        if !PauseAllocation.isTrusted(pausedSpans, start: sessionStartDate, end: now(),
                                      pausedTotal: totalPausedDuration) { pausedSpans = [] }
        if let returnedAt, let awayStarted, returnedAt > awayStarted {
            let uncreditedPause = min(interval(from: originalStart), max(0, oldPaused + shadow))
            lastAwayDecision = AwayDecisionReceipt(id: decisionID,
                range: DateInterval(start: awayStarted, end: returnedAt), name: originalName,
                workType: activeWorkType, threadID: originalThread, sessionStart: originalStart,
                decision: decision, insertedRecord: breakRecord,
                creditedSeconds: decision == .mergeTime ? max(0, uncreditedPause - totalPausedDuration) : 0)
        }
        // Already-saved initial effects are a replay after interrupted legacy
        // persistence; do not insert them a second time.
        let newRecords = additions.filter { wanted in !archive.records.contains { $0.id == wanted.id } }
        linkCreditRecords(additions)
        if !commitCorrection(before: before, adding: newRecords, allowsEviction: true), isAwaitingCorrection {
            departureApp = departureBefore
        }
        // Held at a second absence past the cap: the answer is kept, then the
        // stretch it continued ends where that absence began — as the restore
        // replay does. A fresh successor banked the absence in its paused
        // total; `endStretch` carries it as the closing pause instead.
        if let heldAt, !isAwaitingCorrection {
            if pauseStartDate == nil {
                totalPausedDuration = max(0, totalPausedDuration - interval(from: heldAt))
            }
            endStretch(leftAt: heldAt)
        }
    }
}
