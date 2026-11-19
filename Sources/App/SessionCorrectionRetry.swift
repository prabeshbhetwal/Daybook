import Foundation

enum SessionCorrectionRetry {
    case correction(threadID: UUID, correction: SessionCorrection, claims: Bool = false)
    /// A cut or a join refused before its records changed: Retry does it again with the same arguments, the
    /// same tail id included. Held in memory like every retry, so a relaunch drops it and the person cuts or
    /// joins again. Not a `SessionCorrection` case: the journal keeps them as removals (ruling B26).
    case split(threadID: UUID, recordID: UUID, at: Date, tail: SplitTail, tailID: UUID)
    case merge(threadID: UUID, tailID: UUID)
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
        case .correction(let thread, let correction, _):
            return transaction.fieldsAfter.contains { receipt in
                receipt.threadID == thread && receipt.correction == correction
                    && !transaction.fieldsBefore.contains { $0.id == receipt.id }
            }
        case .split(let thread, _, _, _, _):
            return transaction.wrote(.split, for: thread)
        case .merge(let thread, _):
            return transaction.wrote(.merge, for: thread)
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

private extension DecisionHistory.Transaction {
    /// Whether this transaction wrote a new receipt of `kind` for `thread`.
    func wrote(_ kind: SessionStoreCorrectionState.Restructure, for thread: UUID) -> Bool {
        fieldsAfter.contains { receipt in
            receipt.threadID == thread && receipt.restructure == kind
                && !fieldsBefore.contains { $0.id == receipt.id }
        }
    }
}
