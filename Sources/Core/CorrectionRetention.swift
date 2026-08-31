import Foundation

/// Applies a proven capacity boundary to correction references. It is never
/// called for a reversible removal or merely because an original is missing.
enum CorrectionRetention {
    static func applying(_ retired: [SessionRecord], to state: PersistedState,
                         fields: [SessionStoreCorrectionState], surviving: [SessionRecord])
        -> (state: PersistedState, fields: [SessionStoreCorrectionState]) {
        guard !retired.isEmpty else { return (state, fields) }
        let ids = Set(retired.map(\.id))
        var result = state
        let receipts = state.awayDecisions ?? state.awayDecision.map { [$0] } ?? []
        let heldSources = receipts.flatMap {
            [$0.insertedRecord, $0.expectedCreditRecord, $0.legacyOriginalRecord].compactMap { $0 }
        }.filter { !ids.contains($0.id) }
        let knownSourceIDs = Set((surviving + heldSources).map(\.id))
        let boundary = surviving.map(\.start).min()
        result.awayDecisions = receipts.compactMap { original in
            var receipt = original
            if let inserted = receipt.insertedRecord, ids.contains(inserted.id) { return nil }
            if let legacy = receipt.legacyOriginalRecord, ids.contains(legacy.id) { return nil }
            if let credit = receipt.expectedCreditRecord, ids.contains(credit.id) {
                if receipt.creditedSeconds > 0 || receipt.insertedRecord == nil { return nil }
                receipt.expectedCreditRecord = nil
            }
            // An entirely record-free notice follows this proven retained
            // window, not a separate age timeout. Explicit missing records
            // and temporarily held originals remain recoverable/conflicting.
            if receipt.insertedRecord == nil, receipt.legacyOriginalRecord == nil,
               receipt.expectedCreditRecord == nil, let boundary, receipt.range.end <= boundary {
                let liveAnchor = state.kind != .idle && state.threadID == receipt.threadID
                    && (state.sessionStart == receipt.sessionStart || state.sessionStart == receipt.range.end)
                let savedAnchor = (surviving + heldSources).contains {
                    $0.threadID == receipt.threadID && ($0.start == receipt.sessionStart || $0.start == receipt.range.end)
                }
                let missingFieldAnchor = fields.contains {
                    $0.threadID == receipt.threadID
                        && !$0.archiveRecordIDs.subtracting(ids).isSubset(of: knownSourceIDs)
                }
                if !liveAnchor && !savedAnchor && !missingFieldAnchor { return nil }
            }
            return receipt
        }
        result.awayDecision = result.awayDecisions?.last
        let retainedFields = fields.compactMap { field -> SessionStoreCorrectionState? in
            let remaining = field.archiveRecordIDs.subtracting(ids)
            let originals = field.archiveSnapshot?.fields.filter { !ids.contains($0.recordID) }
            let active = state.kind != .idle && state.threadID == field.threadID
            let hasSurvivor = (surviving + heldSources).contains { $0.threadID == field.threadID }
            guard !remaining.isEmpty || originals?.isEmpty == false || active || hasSurvivor else { return nil }
            let snapshot = field.archiveSnapshot.map {
                SessionArchiveCorrectionSnapshot(threadID: $0.threadID, correction: $0.correction, fields: originals ?? [])
            }
            return SessionStoreCorrectionState(id: field.id, sequence: field.sequence, threadID: field.threadID,
                correction: field.correction, archiveSnapshot: snapshot, originalFields: field.originalFields,
                archiveRecordIDs: remaining)
        }
        return (result, retainedFields)
    }
}
