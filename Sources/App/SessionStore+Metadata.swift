import Foundation

extension SessionStore {
    /// Only a genuinely near-simultaneous transition may be labelled as an
    /// observed start/end. Stored timestamps always remain the sampling clock.
    private static let powerBoundaryTolerance: TimeInterval = 2

    private func refreshPowerMetadataError() {
        powerMetadataError = pendingPowerObservations.lazy.compactMap(\.lastError).first
            ?? pendingPowerTransferError
    }

    private func persistPowerObservationRecovery() {
        engine.store.pendingPowerObservations = pendingPowerObservations
        refreshPowerMetadataError()
    }

    private func persistPowerTransferRecovery() {
        engine.store.pendingPowerTransfers = pendingPowerTransfers
        engine.store.pendingPowerMetadataError = pendingPowerTransferError
        refreshPowerMetadataError()
    }

    /// Durably queues before touching the sidecar. A callback arriving behind a
    /// failed front is retained but cannot trigger a retry or overtake it; the
    /// next refresh (including cold launch) owns replay.
    func enqueuePowerObservation(_ observation: PowerObservation, for recordID: UUID) {
        let mayAttemptImmediately = pendingPowerObservations.isEmpty
        pendingPowerObservations.append(PendingPowerObservation(
            recordID: recordID, observation: observation, lastError: nil))
        persistPowerObservationRecovery()
        if mayAttemptImmediately { _ = replayPendingPowerObservations() }
    }

    @discardableResult
    private func replayPendingPowerObservations() -> Bool {
        while let pending = pendingPowerObservations.first {
            switch metadataArchive.appendPower(pending.observation, for: pending.recordID) {
            case .failed(let error):
                pendingPowerObservations[0] = PendingPowerObservation(
                    recordID: pending.recordID, observation: pending.observation,
                    lastError: error)
                persistPowerObservationRecovery()
                return false
            case .saved:
                pendingPowerObservations.removeFirst()
                persistPowerObservationRecovery()
            }
        }
        return true
    }

    private func capturePowerObservation(for recordID: UUID,
                                         boundary: PowerCoverageBoundary?) {
        guard let powerMonitor else { return }
        let timestamp = now()
        let observation = powerMonitor.observation(at: timestamp, boundary: boundary)
        enqueuePowerObservation(observation, for: recordID)
    }

    /// One reading into the day's log at a session boundary, so the quiet
    /// block on the idle side of it has a sample at its edge even on mains,
    /// where the level does not tick.
    private func seedAmbientPower(at time: Date) {
        guard let powerMonitor else { return }
        ambientPower.append(powerMonitor.observation(at: time, boundary: nil), now: time)
    }

    /// What the Mac was on across a quiet block of the story.
    func ambientPowerSummary(within span: DateInterval) -> PowerContextSummary? {
        PowerContextSummary.make(observations: ambientPower.observations(in: span), interval: span)
    }

    func reconcilePowerBoundaries() {
        // Recovery must precede ownership transfers and retention. Otherwise a
        // queued predecessor sample could be appended after its transfer ran.
        guard replayPendingPowerObservations() else { return }
        let currentID = engine.state == .idle ? nil : engine.activeRecordID
        let sampleTime = now()
        // Whether the monitor was sampling right up to this call. It was if
        // this process tracked a stretch before now and the machine has not
        // slept since. `lastPowerRecordID` is in-memory on purpose: after a
        // relaunch it is nil however many transfers are queued on disk.
        let wasSampling = lastPowerRecordID != nil && !powerCoverageLapsed
        let firstSource = pendingPowerTransfers.first?.sourceID ?? lastPowerRecordID

        // A later engine transition cannot replace an earlier failed transfer.
        // Extend the chain from its exact tail and then commit it front-to-back.
        if let currentID,
           let tail = pendingPowerTransfers.last?.destinationID ?? lastPowerRecordID,
           tail != currentID {
            pendingPowerTransfers.append(PendingPowerTransfer(
                sourceID: tail, destinationID: currentID,
                factualBoundary: engine.sessionStartDate))
            persistPowerTransferRecovery()
        }
        while let transfer = pendingPowerTransfers.first {
            switch metadataArchive.reassignPower(from: transfer.sourceID,
                to: transfer.destinationID, atOrAfter: transfer.factualBoundary) {
            case .failed(let error):
                pendingPowerTransferError = error
                persistPowerTransferRecovery()
                return
            case .saved:
                lastPowerRecordID = transfer.destinationID
                pendingPowerTransfers.removeFirst()
                pendingPowerTransferError = nil
                persistPowerTransferRecovery()
            }
        }
        pendingPowerTransferError = nil
        persistPowerTransferRecovery()

        let previousID = currentID == nil ? lastPowerRecordID : firstSource
        if let previousID, previousID != currentID {
            if let record = engine.archive.records.first(where: { $0.id == previousID }),
               abs(sampleTime.timeIntervalSince(record.end)) <= Self.powerBoundaryTolerance {
                capturePowerObservation(for: previousID, boundary: .stretchEnded)
            }
            // Idle now: the quiet block that begins here gets its first reading.
            if currentID == nil { seedAmbientPower(at: sampleTime) }
        }
        if let currentID, currentID != firstSource {
            // First sample for this stretch. At its start it marks the start.
            // Later than that it is a resume only if sampling had stopped —
            // a relaunch, a wake, an automatic start backdated across idle
            // time. A stretch that an Away answer split off a tracked
            // predecessor was sampled straight through the split, and its
            // first own sample is just a sample: "coverage resumed" here was
            // written at 0m of every such stretch.
            let boundary: PowerCoverageBoundary?
            if abs(sampleTime.timeIntervalSince(engine.sessionStartDate)) <= Self.powerBoundaryTolerance {
                boundary = .stretchStarted
            } else if wasSampling {
                boundary = nil
            } else {
                boundary = .coverageResumed
            }
            capturePowerObservation(for: currentID, boundary: boundary)
            // A stretch beginning now ends a quiet block; give it a last reading.
            if boundary == .stretchStarted { seedAmbientPower(at: sampleTime) }
        } else if currentID != nil, case .running = engine.state, lastPowerState.isPaused {
            // The monitor samples through a pause; only sleep stops it.
            capturePowerObservation(for: currentID!,
                                    boundary: powerCoverageLapsed ? .coverageResumed : nil)
        }
        powerCoverageLapsed = false
        lastPowerRecordID = currentID
        lastPowerState = engine.state
    }
    func beginNoteEditing(for recordID: UUID) {
        if sessionNoteDrafts[recordID] == nil {
            sessionNoteDrafts[recordID] = metadataArchive.metadata(for: recordID)?.note ?? ""
        }
        sessionNoteErrors.removeValue(forKey: recordID)
        expandedNoteEditorIDs.insert(recordID)
    }

    func setNoteDraft(_ text: String, for recordID: UUID) {
        sessionNoteDrafts[recordID] = text
    }

    func noteDraft(for recordID: UUID) -> String { sessionNoteDrafts[recordID] ?? "" }
    func noteError(for recordID: UUID) -> String? { sessionNoteErrors[recordID] }

    @discardableResult func saveNote(for recordID: UUID) -> Bool {
        let draft = sessionNoteDrafts[recordID] ?? ""
        switch metadataArchive.saveNote(draft, for: recordID) {
        case .saved:
            sessionNoteErrors.removeValue(forKey: recordID)
            expandedNoteEditorIDs.remove(recordID)
            sessionNoteDrafts.removeValue(forKey: recordID)
            if focusedNoteEditorID == recordID { focusedNoteEditorID = nil }
            storyProjectionCache.removeAll(keepingCapacity: true)
            storyProjectionCacheOrder.removeAll(keepingCapacity: true)
            insightReadingCache.removeAll(keepingCapacity: true)
            insightReadingCacheOrder.removeAll(keepingCapacity: true)
            objectWillChange.send()
            return true
        case .failed(let error):
            sessionNoteErrors[recordID] = error
            return false
        }
    }

    @discardableResult func saveFocusedNote() -> Bool {
        guard let focusedNoteEditorID else { return false }
        return saveNote(for: focusedNoteEditorID)
    }

    @discardableResult func cancelNoteEditing(for recordID: UUID,
                                              discardingChanges: Bool = false) -> Bool {
        let saved = metadataArchive.metadata(for: recordID)?.note ?? ""
        let draft = sessionNoteDrafts[recordID] ?? saved
        guard discardingChanges || draft == saved else { return false }
        expandedNoteEditorIDs.remove(recordID)
        if focusedNoteEditorID == recordID { focusedNoteEditorID = nil }
        sessionNoteDrafts.removeValue(forKey: recordID)
        sessionNoteErrors.removeValue(forKey: recordID)
        return true
    }

    func refreshSessionMetadataRetention() {
        var retained = Set(engine.archive.records.map(\.id))
        retained.formUnion(engine.retainedCorrectionRecordIDs)
        retained.formUnion(sessionNoteDrafts.keys)
        retained.formUnion(expandedNoteEditorIDs)
        for transfer in pendingPowerTransfers {
            retained.insert(transfer.sourceID)
            retained.insert(transfer.destinationID)
        }
        retained.formUnion(pendingPowerObservations.map(\.recordID))
        if engine.state != .idle { retained.insert(engine.activeRecordID) }
        _ = metadataArchive.retain(recordIDs: retained)
    }

    func sessionMetadata(for recordID: UUID) -> SessionMetadata? {
        metadataArchive.metadata(for: recordID)
    }

    func powerMetadataError(for recordID: UUID) -> String? {
        if let error = pendingPowerObservations.lazy.compactMap({ pending in
            pending.recordID == recordID ? pending.lastError : nil
        }).first {
            return error
        }
        guard let transfer = pendingPowerTransfers.first,
              transfer.sourceID == recordID || transfer.destinationID == recordID
        else { return nil }
        return pendingPowerTransferError
    }

    func powerMetadataError(for recordIDs: [UUID]) -> String? {
        recordIDs.lazy.compactMap { self.powerMetadataError(for: $0) }.first
    }

    /// Every power reading kept for these stretches, for marks drawn per row.
    func powerObservations(for recordIDs: [UUID]) -> [PowerObservation] {
        Set(recordIDs).flatMap { metadataArchive.metadata(for: $0)?.power ?? [] }
    }

    func powerSummary(for recordIDs: [UUID], interval: DateInterval) -> PowerContextSummary? {
        var seen = Set<UUID>()
        let uniqueRecordIDs = recordIDs.filter { seen.insert($0).inserted }
        let groups = uniqueRecordIDs.compactMap { metadataArchive.metadata(for: $0)?.power }
            .filter { !$0.isEmpty }
        let observations = groups.flatMap { $0 }
        guard let summary = PowerContextSummary.make(observations: observations,
                                                     interval: interval) else { return nil }
        guard uniqueRecordIDs.count > 1 else { return summary }
        let qualification = groups.count == uniqueRecordIDs.count
            ? "Recorded across \(groups.count) stretches; gaps between stretches are not power coverage."
            : "Recorded for \(groups.count) of \(uniqueRecordIDs.count) stretches; coverage is partial."
        return PowerContextSummary(headline: summary.headline,
            detail: [qualification, summary.detail].compactMap { $0 }.joined(separator: " "),
            symbolName: summary.symbolName)
    }
}
