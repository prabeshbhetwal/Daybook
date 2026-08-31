import Foundation

/// Store-owned bookkeeping for one correction and its reversible field values.
/// It deliberately carries IDs and fields, never an archive replacement.
struct SessionStoreCorrectionState: Codable, Identifiable, Equatable {
    var id = UUID()
    var sequence = 0
    struct ActiveFields: Codable, Equatable {
        let name: String
        let workType: WorkType
    }

    let threadID: UUID
    let correction: SessionCorrection
    let archiveSnapshot: SessionArchiveCorrectionSnapshot?
    /// The thread value before correction, including for archive-only edits.
    /// A later continuation inherits the corrected value, so Undo needs this
    /// independently of whether a stretch was active when Save was pressed.
    let originalFields: ActiveFields
    /// IDs already present when correction was made. Later continuations are
    /// restored through the same atomic archive candidate without changing
    /// evidence that pre-dated the correction.
    let archiveRecordIDs: Set<UUID>
}

enum SessionCorrectionRetry {
    case correction(threadID: UUID, correction: SessionCorrection)
    case undo(SessionStoreCorrectionState)
    case awayUndo(UUID)
    case awayDecision(UserDecision, label: String?, reviewing: Bool, expectedID: UUID)
    case legacy(record: SessionRecord, decision: UserDecision, target: SessionRecord?)
    case ending(threadID: UUID, sessionStart: Date)
    case discarding(threadID: UUID, sessionStart: Date, resumeTracking: Bool)
    case longAway(LongAwayTransitionRequest, resumeTracking: Bool)

    func matches(_ transaction: DecisionHistory.Transaction) -> Bool {
        let before = transaction.before.awayDecisions ?? []
        let after = transaction.after.awayDecisions ?? []
        switch self {
        case .awayUndo(let id):
            return before.contains { $0.id == id && $0.isResolved }
                && !after.contains { $0.id == id && $0.isResolved }
        case .awayDecision(let decision, _, let reviewing, let id):
            return (reviewing ? before.contains { $0.id == id && !$0.isResolved }
                : transaction.before.pendingDecisionID == id)
                && after.contains { $0.id == id && $0.decision == decision }
        case .undo(let correction):
            return transaction.fieldsBefore.contains { $0.id == correction.id }
                && !transaction.fieldsAfter.contains { $0.id == correction.id }
        case .correction(let thread, let correction):
            return transaction.fieldsAfter.contains { receipt in
                receipt.threadID == thread && receipt.correction == correction
                    && !transaction.fieldsBefore.contains { $0.id == receipt.id }
            }
        case .legacy(let record, let decision, _):
            return transaction.removed.contains(record) && after.contains {
                $0.legacyOriginalRecord == record && $0.decision == decision
            }
        case .ending(let thread, let start):
            return transaction.before.threadID == thread && transaction.before.sessionStart == start
                && transaction.before.kind != .idle && transaction.after.kind == .idle
                && (transaction.operation == .endStretch || (transaction.operation == nil
                    && transaction.added.contains { $0.threadID == thread && $0.start == start }))
        case .discarding(let thread, let start, _):
            return transaction.operation == .discardStretch && transaction.before.threadID == thread
                && transaction.before.sessionStart == start && transaction.before.kind != .idle
                && transaction.after.kind == .idle
        case .longAway(let request, _):
            return transaction.operation == .endStretch && transaction.before.threadID == request.threadID
                && transaction.before.sessionStart == request.sessionStart && transaction.after.kind == .idle
        }
    }
}
