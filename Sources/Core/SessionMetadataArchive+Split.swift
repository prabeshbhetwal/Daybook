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
