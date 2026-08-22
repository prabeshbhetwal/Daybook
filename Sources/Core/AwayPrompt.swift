import Foundation

/// How the away question is put to the user when they come back: lightly, from
/// the menu bar, or on a blurred screen. Pure so it can be tested without a
/// window.
enum AwayPromptTier: Equatable {
    case quick
    case full

    /// `fullPromptAfter == nil` means Never: every absence gets the quick
    /// prompt. The question is still asked — only the weight of the asking
    /// changes.
    static func tier(forAbsence away: TimeInterval,
                     fullPromptAfter: TimeInterval?) -> AwayPromptTier {
        guard let threshold = fullPromptAfter else { return .quick }
        return away >= threshold ? .full : .quick
    }
}
