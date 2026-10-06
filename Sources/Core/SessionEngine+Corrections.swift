import Foundation

extension SessionEngine {
    // MARK: - Persistence (D14)

    func persist() {
        store.saveState(snapshot())
    }

    /// Reconcile before accepting another correction. A newer committed
    /// generation owns correction identity even when preferences are stale.
    @discardableResult
    func prepareCorrection() -> Bool {
        if let error = decisionHistory.reconcile(archive: archive) {
            awayDecisionError = error; return false
        }
        if let saved = decisionHistory.document.checkpoint,
           liveGeneration(of: saved) > liveCorrectionGeneration {
            applyExactCorrectionState(saved)
        }
        synchroniseCommittedCorrectionMetadata()
        return true
    }

    func stageActiveCorrection(_ correction: SessionCorrection, threadID: UUID) {
        guard state != .idle, activeThreadID == threadID else { return }
        switch correction {
        case .rename(let name): store.sessionName = name
        case .workType(let type): activeWorkType = type
        case .removed: break   // never staged on a live stretch
        }
    }

    @discardableResult
    func commitCorrection(before: PersistedState, removing: [SessionRecord] = [],
                          adding: [SessionRecord] = [], allowsEviction: Bool = false,
                          fields: [SessionStoreCorrectionState]? = nil,
                          operation: DecisionHistory.Operation = .correction) -> Bool {
        correctionGeneration += 1
        if operation.updatesLiveState { liveCorrectionGeneration = correctionGeneration }
        let after = snapshot()
        let result = decisionHistory.commit(before: before, after: after, removing: removing,
            adding: adding, fields: fields, archive: archive, allowsEviction: allowsEviction, operation: operation)
        if let error = result.error {
            // Once the scoped archive effects landed, retain the live after
            // state too. The pending journal completes finalisation on retry.
            // Before archive commit, restore only our staged in-memory state.
            if !result.didCommit { applyExactCorrectionState(before) }
            else { synchroniseCommittedCorrectionMetadata() }
            awayDecisionError = error
            if operation.updatesLiveState { persist() }
            return false
        }
        synchroniseCommittedCorrectionMetadata()
        awayDecisionError = nil
        if operation.updatesLiveState { persist() }
        return true
    }

    func synchroniseCommittedCorrectionMetadata() {
        guard let saved = decisionHistory.committedMetadata(in: archive), saved.generation >= correctionGeneration else { return }
        correctionGeneration = saved.generation
        awayDecisions = saved.awayDecisions
    }

    func liveGeneration(of snapshot: PersistedState) -> Int {
        snapshot.liveCorrectionGeneration ?? snapshot.correctionGeneration ?? 0
    }

    func linkCreditRecords(_ records: [SessionRecord]) {
        for index in awayDecisions.indices where awayDecisions[index].creditedSeconds > 0 {
            if let record = records.first(where: { $0.threadID == awayDecisions[index].threadID
                && $0.start == awayDecisions[index].sessionStart }) {
                awayDecisions[index].expectedCreditRecord = record
            }
        }
    }

    /// Restore a transaction checkpoint without inventing a new presence event
    /// or replaying the ordinary launch/away transition.
    func applyExactCorrectionState(_ saved: PersistedState) {
        switch saved.kind {
        case .idle: state = .idle
        case .running: state = .running
        case .paused: state = .paused(reason: saved.restoredPauseReason)
        case .awaiting: state = .awaitingUserDecision(away: saved.pendingAway ?? 0, lastApp: saved.lastApp)
        }
        store.sessionName = saved.name
        sessionStartDate = saved.sessionStart
        totalPausedDuration = saved.totalPaused
        pausedSpans = saved.pausedSpans ?? []
        pauseStartDate = saved.pauseStart
        awayInterval = saved.awayStart.map { (start: $0, trigger: saved.awayTrigger ?? .screenLock) }
        shadowAway = saved.shadowAway ?? 0
        decisionStartDate = saved.decisionStarted
        awayReturnedAt = saved.awayReturnedAt
        pendingDecisionID = saved.pendingDecisionID
        workBeforePendingAway = saved.workBeforePendingAway
        activeThreadID = saved.threadID ?? activeThreadID
        activeRecordID = saved.activeRecordID ?? legacyActiveRecordID(for: saved)
        activeWorkType = saved.activeWorkType ?? .deepWork
        activeIsAuto = saved.isAuto ?? false
        activeAutomaticAction = saved.automaticActivityAction
        awayDecisions = saved.awayDecisions ?? saved.awayDecision.map { [$0] } ?? []
        correctionGeneration = saved.correctionGeneration ?? 0
        liveCorrectionGeneration = liveGeneration(of: saved)
    }

    func snapshot() -> PersistedState {
        var result = PersistedState(state: state,
                       name: sessionName,
                       sessionStart: sessionStartDate,
                       totalPaused: totalPausedDuration,
                       pausedSpans: pausedSpans.isEmpty ? nil : pausedSpans,
                       pauseStart: pauseStartDate,
                       away: awayInterval,
                       lastApp: currentAppName,
                       lastAppBundleID: currentAppBundleID,
                       decisionStarted: decisionStartDate,
                       savedAt: now(),
                       threadID: activeThreadID,
                       activeWorkType: activeWorkType,
                       isAuto: activeIsAuto,
                       shadowAway: shadowAway)
        result.awayDecision = lastAwayDecision
        result.awayDecisions = awayDecisions
        result.correctionGeneration = correctionGeneration
        result.liveCorrectionGeneration = liveCorrectionGeneration
        result.pendingDecisionID = pendingDecisionID
        result.awayReturnedAt = awayReturnedAt
        result.workBeforePendingAway = workBeforePendingAway
        result.activeRecordID = activeRecordID
        result.automaticActivityAction = activeAutomaticAction
        result.pendingRests = pendingRests.isEmpty ? nil : pendingRests
        return result
    }
}
