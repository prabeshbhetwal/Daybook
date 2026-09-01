import Foundation

extension SessionStore {
    func capturePowerObservation(boundary: PowerCoverageBoundary?) {
        guard engine.state != .idle, powerMonitor != nil else { return }
        capturePowerObservation(for: engine.activeRecordID, at: now(), boundary: boundary)
    }

    private func capturePowerObservation(for recordID: UUID, at timestamp: Date,
                                         boundary: PowerCoverageBoundary?) {
        guard let powerMonitor else { return }
        let observation = powerMonitor.observation(at: timestamp, boundary: boundary)
        if case .failed(let error) = metadataArchive.appendPower(observation, for: recordID) {
            for recordID in expandedNoteEditorIDs { sessionNoteErrors[recordID] = error }
        }
    }

    func reconcilePowerBoundaries() {
        let currentID = engine.state == .idle ? nil : engine.activeRecordID
        if let previousID = lastPowerRecordID, previousID != currentID,
           let record = engine.archive.records.first(where: { $0.id == previousID }) {
            capturePowerObservation(for: previousID, at: record.end, boundary: .stretchEnded)
        }
        if let currentID, currentID != lastPowerRecordID {
            capturePowerObservation(for: currentID, at: engine.sessionStartDate,
                                    boundary: .stretchStarted)
        } else if currentID != nil, case .running = engine.state, lastPowerState.isPaused {
            capturePowerObservation(for: currentID!, at: now(), boundary: .coverageResumed)
        }
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
        if engine.state != .idle { retained.insert(engine.activeRecordID) }
        if case .failed(let error) = metadataArchive.retain(recordIDs: retained) {
            // Keep the error visible on every affected open draft. Retention is
            // conservative: a failed write leaves the prior sidecar untouched.
            for recordID in expandedNoteEditorIDs { sessionNoteErrors[recordID] = error }
        }
    }

    func sessionMetadata(for recordID: UUID) -> SessionMetadata? {
        metadataArchive.metadata(for: recordID)
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
            detail: [qualification, summary.detail].compactMap { $0 }.joined(separator: "\n"),
            symbolName: summary.symbolName)
    }
}
