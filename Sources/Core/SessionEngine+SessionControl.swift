import Foundation

extension SessionEngine {
    /// Atomically closes the established automatic owner at the new activity's
    /// qualifying boundary and transfers that qualifying interval once. The
    /// old stretch remains live if archival fails.
    @discardableResult
    func switchAutomatically(action: ActivityAutomaticAction,
                             expectedRecordID: UUID) -> Bool {
        let evidence = action.evidence
        guard state == .running, activeIsAuto, activeRecordID == expectedRecordID,
              evidence.start >= sessionStartDate, evidence.end <= now(),
              evidence.start <= evidence.end else { return false }
        guard prepareCorrection() else { onStateChanged?(state); return false }
        let before = snapshot()
        let oldWork = elapsed(endingAt: evidence.start)
        let oldRecord: SessionRecord? = oldWork < store.minimumRecordedSession ? nil
            : SessionRecord(id: activeRecordID, name: sessionName,
                            workType: activeWorkType, start: sessionStartDate,
                            end: evidence.start, workSeconds: oldWork,
                            detectedApp: activeDetectedApp,
                            threadID: activeThreadID, isAuto: true,
                            pausedSpans: trustedPausedSpans(until: evidence.start))
        activeWorkType = action.workType
        activeDetectedApp = currentAppBundleID
        let continued = continuedThread(for: action, at: evidence.start)
        activeThreadID = continued ?? UUID()
        activeThreadWasContinued = continued != nil
        activeRecordID = UUID()
        activeIsAuto = true
        activeAutomaticAction = action
        store.sessionName = action.ruleName
        sessionStartDate = evidence.start
        totalPausedDuration = max(0, now().timeIntervalSince(evidence.end))
        pausedSpans = totalPausedDuration > 0 ? [DateInterval(start: evidence.end, end: now())] : []
        pauseStartDate = nil
        awayInterval = nil
        shadowAway = 0
        decisionStartDate = nil
        awayReturnedAt = nil
        pendingDecisionID = nil
        workBeforePendingAway = nil
        state = .running
        correctionGeneration += 1
        liveCorrectionGeneration = correctionGeneration
        let after = snapshot()
        let result = decisionHistory.commit(before: before, after: after,
            adding: oldRecord.map { [$0] } ?? [], archive: archive,
            allowsEviction: true, operation: .automaticSwitch)
        if !result.didCommit {
            applyExactCorrectionState(before)
            awayDecisionError = result.error
            persist()
            onStateChanged?(state)
            return false
        }
        synchroniseCommittedCorrectionMetadata()
        awayDecisionError = result.error
        persist()
        onStateChanged?(state)
        return true
    }

    /// Ends the running session, writes its record, and returns to `.idle`.
    /// `endingAt` exists for automatic ends: the detector notices a session is
    /// over only after the break has run its course, and the record must say
    /// when the work stopped, not when the app worked it out.
    @discardableResult
    func stop(endingAt endMoment: Date? = nil) -> Bool {
        guard state != .idle else { return true }
        awayDecisionError = nil
        guard archiveCurrentSession(endingAt: endMoment) else {
            persist(); onStateChanged?(state); return false
        }
        // Must not survive into the next session: `beginFreshSession` can start
        // one without going through `start(_:)`, and it would inherit this flag
        // and be treated as the app's own guess.
        activeIsAuto = false
        activeAutomaticAction = nil
        cancelDwell()
        pauseStartDate = nil
        awayInterval = nil
        shadowAway = 0
        decisionStartDate = nil
        awayReturnedAt = nil
        state = .idle
        persist()
        onStateChanged?(state)
        return true
    }

    /// Moves a running session's start earlier, crediting work that happened
    /// before the app noticed it. Only ever earlier: moving a start forward
    /// would erase real work, so a later date is refused rather than clamped
    /// silently to something the caller did not ask for.
    func backdate(to moment: Date) {
        guard state != .idle, moment < sessionStartDate else { return }
        sessionStartDate = moment
        persist()
    }

    /// Ends a session without writing a record. Used only to undo the app's own
    /// automatic start — a guess the user rejected is not history, and keeping
    /// it would put a session in the archive that never happened.
    @discardableResult
    func discard() -> Bool {
        guard state != .idle else { return true }
        let before = snapshot()
        awayDecisionError = nil
        cancelDwell()
        pauseStartDate = nil
        awayInterval = nil
        shadowAway = 0
        decisionStartDate = nil
        awayReturnedAt = nil
        totalPausedDuration = 0
        pausedSpans = []
        activeIsAuto = false
        activeAutomaticAction = nil
        state = .idle
        if decisionHistory.requiresTerminalCheckpoint,
           !commitCorrection(before: before, operation: .discardStretch), state != .idle {
            onStateChanged?(state)
            return false
        }
        persist()
        onStateChanged?(state)
        return true
    }

    // MARK: - Dwell guard (D6)

    func scheduleDwell(for bundleID: String) {
        guard schedulesDwell else { return }
        let item = DispatchWorkItem { [weak self] in
            self?.pendingDwell = nil
            self?.transition(on: .dwellExpired(bundleID: bundleID))
        }
        pendingDwell = item
        DispatchQueue.main.asyncAfter(deadline: .now() + FocusConstants.distractionDwell,
                                      execute: item)
    }

    func cancelDwell() {
        pendingDwell?.cancel()
        pendingDwell = nil
    }
}
