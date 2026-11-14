import Foundation

/// One stretch of a period row's split bar. A nil `workType` is "Other".
struct HistorySplitPart: Equatable, Identifiable {
    let workType: WorkType?
    let share: Double
    /// Same hue as the part before it, which is not itself muted, so the bar
    /// draws neighbours of one colour alternately and never alike.
    let isMuted: Bool
    var id: String { workType?.rawValue ?? "other" }
}

enum HistorySplit {
    /// A category whose rounded percentage is below this folds into Other, so
    /// no label ever reads "0%".
    static let otherBelowPercent = 3

    /// The shares (largest first) as bar parts. The first is always kept, even
    /// when it is small. "Other" comes last and exists only when something folded.
    static func parts(_ shares: [WorkTypeShare]) -> [HistorySplitPart] {
        var kept: [WorkTypeShare] = []
        var folded: [WorkTypeShare] = []
        for (index, share) in shares.enumerated() {
            if index == 0 || Int((share.share * 100).rounded()) >= otherBelowPercent {
                kept.append(share)
            } else {
                folded.append(share)
            }
        }
        var parts: [HistorySplitPart] = []
        for share in kept {
            let previous = parts.last
            let muted = previous.map { $0.workType?.hue == share.workType.hue && !$0.isMuted } ?? false
            parts.append(HistorySplitPart(workType: share.workType, share: share.share, isMuted: muted))
        }
        if !folded.isEmpty {
            parts.append(HistorySplitPart(workType: nil, share: folded.reduce(0) { $0 + $1.share }, isMuted: false))
        }
        return parts
    }
}
