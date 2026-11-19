import Foundation

/// A split's link and the cuts the person turned down, beside a record's note and power readings: the
/// person's own overrides (spec section 5), never rewritten by a derivation.
extension SessionMetadataArchive {
    /// How near a declined moment must be to count as the same cut: a shape derived again can place a
    /// departure a beat away.
    static let declinedSplitTolerance: TimeInterval = 1

    @discardableResult
    func saveSplitLink(_ link: SplitLink?, for recordID: UUID) -> SessionMetadataWriteResult {
        update(recordID) { $0.splitFrom = link }
    }

    /// A head's summary replaced by the one of both halves of a join (nil: it has none), or given back by Undo of it.
    @discardableResult
    func replaceActivityShape(_ shape: SessionActivityShape?, for recordID: UUID) -> SessionMetadataWriteResult {
        update(recordID) { $0.activityShape = shape }
    }

    /// The head's own summary, kept on the tail while the halves stand joined (nil: nothing to keep any more).
    @discardableResult
    func setAsideHeadSummary(_ shape: SessionActivityShape?, on tailID: UUID) -> SessionMetadataWriteResult {
        update(tailID) { $0.headSummary = shape }
    }

    @discardableResult
    func declineSplit(at moment: Date, for recordID: UUID) -> SessionMetadataWriteResult {
        guard !hasDeclinedSplit(at: moment, for: recordID) else { return .saved }
        return update(recordID) { $0.declinedSplits = ($0.declinedSplits ?? []) + [moment] }
    }

    func hasDeclinedSplit(at moment: Date, for recordID: UUID) -> Bool {
        (metadata(for: recordID)?.declinedSplits ?? []).contains {
            abs($0.timeIntervalSince(moment)) <= Self.declinedSplitTolerance
        }
    }
}
