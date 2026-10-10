import Foundation

/// Ask's numbers are History's, however long the history: a search that stops
/// at the newest few hundred sessions would undercount an all-time total
/// without saying so.
enum AskLookupVolumeChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Ask counts every matching session, however long the history", countsEverySession),
    ]

    /// The fixture's two Thesis days plus 1,001 more, each with a minute of
    /// Thesis and of Safari, so 1,003 sessions match "thesis" and 1,002 used
    /// Safari: past the 1,000 a capped search stops at.
    private static func countsEverySession() -> [String] {
        let started = Date()
        let problems = AskLookupChecks.withFixture(extraThesisDays: 1_001) { f, problems in
            let thesis = f.store.askLookup(.focusTotals(.allTime, words: "thesis"))
            let thesisWant = "Sessions matching “thesis” in all your history: 19h 41m over 1003 sessions on 1003 days."
            expect(thesis == thesisWant, "all-time thesis says “\(thesis)”, not “\(thesisWant)”", &problems)

            let safari = f.store.askLookup(.appTime(.allTime, app: "safari"))
            let safariWant = "Safari in all your history: 17h 41m in front; used in 1002 sessions."
            expect(safari == safariWant, "all-time Safari says “\(safari)”, not “\(safariWant)”", &problems)
        }
        Diagnostics.log("Ask 1,003-session lookups took \(Date().timeIntervalSince(started))s with the fixture")
        return problems
    }
}
