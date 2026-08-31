import Foundation

/// One reversible classification of an absence. It does not snapshot or rewind
/// the archive: later stretches, names and timing remain independent evidence.
struct AwayDecisionReceipt: Codable, Equatable, Identifiable {
    var id: UUID
    let range: DateInterval
    let name: String
    let workType: WorkType
    let threadID: UUID
    let sessionStart: Date
    var decision: UserDecision?
    /// A separate break/focus record created for this interval, if any.
    var insertedRecord: SessionRecord?
    /// The original "I was working" path credits the open stretch in place.
    /// Undo removes only that credit, even after that stretch is archived.
    var creditedSeconds: TimeInterval
    /// Captured when the originally credited live stretch is closed. This
    /// exact before/after pair makes archived Undo safe across an interrupted
    /// archive write followed by stale preference restoration.
    var expectedCreditRecord: SessionRecord? = nil

    var isResolved: Bool { decision != nil }

    /// Two effect identities are reserved for an initial decision. Neither
    /// changes when the same persisted pending decision is replayed.
    static func precedingRecordID(for decisionID: UUID) -> UUID {
        var bytes = decisionID.uuid
        bytes.0 ^= 0x80
        return UUID(uuid: bytes)
    }

    var title: String {
        switch decision {
        case .tookBreak: return "Recorded as a break"
        case .mergeTime: return "Counted as focus"
        case .continueSession, .resetTimer: return "Left uncounted"
        case nil: return "Review this interval"
        }
    }
}
