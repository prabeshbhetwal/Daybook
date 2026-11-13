import Foundation

/// The tour and the break reasons are the longest prose the app shows. An em
/// dash joining two thoughts in them read as machine-written; each is now a
/// full stop, a colon or a comma. A lone dash standing for "no value" is a
/// different thing and is not checked here.
enum CopyDashChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The tour and the break reasons join no two thoughts with an em dash", noEmDash)
    ]

    private static func noEmDash() -> [String] {
        var problems: [String] = []
        for chapter in FirstRunScript.chapters {
            for card in chapter.cards {
                for text in [card.sentence, card.body, card.note, card.result].compactMap({ $0 }) {
                    expect(!text.contains("\u{2014}"), "tour copy without an em dash, got “\(text)”", &problems)
                }
            }
        }
        for tier in BreakTier.allCases {
            expect(!tier.reason.contains("\u{2014}"),
                   "the \(tier.shortLabel) reason without an em dash, got “\(tier.reason)”", &problems)
        }
        return problems
    }
}
