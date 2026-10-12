import Foundation

/// The pure half of name suggestions: earlier names ranked by the app time
/// they share with a session, and the audit of a name the on-device model
/// words itself. Dates and categories are fixtures; no calendar is read.
enum NameSuggestionCoreChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Shared app time ranks earlier names", ranking),
        ("A matching category adds 0.1, and a tie goes to the more recent name", bonusAndTie),
        ("Names differing only in case or accents are one candidate in the latest spelling", folding),
        ("At most three candidates", limitThree),
        ("A fresh name passes only when short, plain and not a category or an app", auditRows),
        ("A choice resolves to exact candidate text or an audited fresh name", resolveRows),
        ("A name's sessions pool their app time, which can lift it over the threshold", pooling),
    ]

    private static let base = Date(timeIntervalSince1970: 1_700_000_000)
    private static let appNames = ["Xcode", "Safari"]

    private static func earlier(_ name: String, workType: WorkType = .deepWork, daysAgo: Int = 0,
                              _ apps: [String: TimeInterval]) -> NameHistoryEntry {
        NameHistoryEntry(name: name, workType: workType,
                         end: base.addingTimeInterval(-Double(daysAgo) * 86_400), appSeconds: apps)
    }

    private static func ranking() -> [String] {
        var problems: [String] = []
        let session: [String: TimeInterval] = ["xcode": 3000, "safari": 1200, "terminal": 600]
        let daybook: [String: TimeInterval] = ["xcode": 5000, "terminal": 1000, "safari": 100, "mail": 50]
        let thesis: [String: TimeInterval] = ["pages": 4000, "safari": 1000]
        SelfTest.expectClose(NameCandidates.shared(session, ["xcode": 5000, "terminal": 1000]), 0.75,
                           "Daybook shares 0.75 of the session's time", &problems)
        SelfTest.expectClose(NameCandidates.shared(session, thesis), 0.20,
                           "Thesis shares 0.20, only Safari", &problems)
        expect(NameCandidates.shared(session, [:]) == 0 && NameCandidates.shared([:], session) == 0,
               "an empty mix shares nothing", &problems)

        let ranked = NameCandidates.rank(
            appSeconds: session, workType: .deepWork,
            history: [earlier("Daybook", ["xcode": 5000, "terminal": 1000]), earlier("Thesis", workType: .learning, thesis)])
        expect(ranked.map(\.name) == ["Daybook"], "Thesis falls under 0.3, got \(ranked.map(\.name))", &problems)

        let full = NameCandidates.rank(appSeconds: session, workType: .deepWork,
                                       history: [earlier("Daybook", daybook)])
        expect(full.first?.usualApps == ["xcode", "terminal", "safari"],
               "the usual apps are the three biggest by time, got \(full.first?.usualApps ?? [])", &problems)
        expect(full.first?.usualWorkType == .deepWork, "the usual category is kept", &problems)
        expect(NameCandidates.rank(appSeconds: [:], workType: .deepWork, history: [earlier("Daybook", daybook)]).isEmpty,
               "a session with no app time matches nothing", &problems)
        return problems
    }

    private static func bonusAndTie() -> [String] {
        var problems: [String] = []
        let mix: [String: TimeInterval] = ["xcode": 600]
        let bonus = NameCandidates.rank(
            appSeconds: mix, workType: .deepWork,
            history: [earlier("Alpha", workType: .deepWork, daysAgo: 5, mix), earlier("Beta", workType: .learning, daysAgo: 1, mix)])
        expect(bonus.map(\.name) == ["Alpha", "Beta"],
               "the matching category outranks a newer name, got \(bonus.map(\.name))", &problems)
        SelfTest.expectClose(bonus.first?.score ?? 0, 1.1, "a full match with the category scores 1.1", &problems)
        SelfTest.expectClose(bonus.last?.score ?? 0, 1.0, "a full match in another category scores 1.0", &problems)

        let tie = NameCandidates.rank(
            appSeconds: mix, workType: .deepWork,
            history: [earlier("Old", daysAgo: 9, mix), earlier("New", daysAgo: 2, mix), earlier("Mid", daysAgo: 4, mix)])
        expect(tie.map(\.name) == ["New", "Mid", "Old"],
               "equal scores go to the more recent name, got \(tie.map(\.name))", &problems)

        let usual = NameCandidates.rank(
            appSeconds: mix, workType: .learning,
            history: [earlier("Mixed", workType: .deepWork, daysAgo: 3, mix), earlier("Mixed", workType: .learning, daysAgo: 2, mix),
                      earlier("Mixed", workType: .deepWork, daysAgo: 1, mix)])
        expect(usual.first?.usualWorkType == .deepWork, "the most common category is the usual one", &problems)
        SelfTest.expectClose(usual.first?.score ?? 0, 1.0, "the bonus follows the usual category, not the latest", &problems)
        return problems
    }

    private static func folding() -> [String] {
        var problems: [String] = []
        let mix: [String: TimeInterval] = ["xcode": 600]
        let ranked = NameCandidates.rank(
            appSeconds: mix, workType: .deepWork,
            history: [earlier("daybook", daysAgo: 6, mix), earlier("Dáybook", daysAgo: 1, mix),
                      earlier("DAYBOOK", daysAgo: 3, mix), earlier("  ", daysAgo: 0, mix)])
        expect(ranked.map(\.name) == ["Dáybook"],
               "case and accents are one name, in the latest spelling; got \(ranked.map(\.name))", &problems)
        return problems
    }

    private static func limitThree() -> [String] {
        var problems: [String] = []
        let mix: [String: TimeInterval] = ["xcode": 600]
        let names = ["A", "B", "C", "D", "E"]
        let ranked = NameCandidates.rank(
            appSeconds: mix, workType: .deepWork,
            history: names.enumerated().map { earlier($1, daysAgo: $0, mix) })
        expect(ranked.map(\.name) == ["A", "B", "C"], "only the best three are offered, got \(ranked.map(\.name))", &problems)
        return problems
    }

    private static func auditRows() -> [String] {
        var problems: [String] = []
        func accepts(_ name: String) -> Bool {
            NameAudit.accepts(name, appNames: appNames)
        }
        expect(accepts("Daybook parser"), "a short plain name passes", &problems)
        expect(accepts("  Thesis \n"), "surrounding space is ignored", &problems)
        expect(accepts("One two three four"), "four words pass", &problems)
        expect(accepts(String(repeating: "a", count: 30)), "30 characters pass", &problems)
        let rejected = ["Fix 2 bugs", "\"Daybook\"", "'Daybook'", "“Daybook”", "Deep work", "deep WORK", "Xcode", "xcode ",
                        "one two three four five", String(repeating: "a", count: 31), "", "   "]
        for name in rejected {
            expect(!accepts(name), "\"\(name)\" is rejected", &problems)
        }
        return problems
    }

    private static func resolveRows() -> [String] {
        var problems: [String] = []
        let candidates = [NameCandidate(name: "Daybook", score: 0.9, usualWorkType: .deepWork, usualApps: ["xcode"]),
                          NameCandidate(name: "Thesis", score: 0.5, usualWorkType: .learning, usualApps: ["pages"])]
        func resolve(_ choice: NameChoice, earlier: [String] = ["Daybook"]) -> String? {
            NameAudit.resolve(choice, candidates: candidates, earlierNames: earlier, appNames: appNames)
        }
        expect(resolve(.earlier(1)) == "Daybook", "1 is the first candidate's exact text", &problems)
        expect(resolve(.earlier(2)) == "Thesis", "2 is the second candidate's exact text", &problems)
        expect(resolve(.earlier(3)) == nil && resolve(.earlier(4)) == nil && resolve(.earlier(0)) == nil,
               "a number with no candidate gives nothing", &problems)
        expect(resolve(.fresh("daybook")) == "Daybook", "a fresh name equal to an earlier one takes its spelling", &problems)
        expect(resolve(.fresh("Dáybook")) == "Daybook", "accents do not separate them either", &problems)
        expect(resolve(.fresh("  Fortnight parser ")) == "Fortnight parser", "a new name is trimmed", &problems)
        expect(resolve(.fresh("podcast mix")) == "Podcast mix" && resolve(.fresh("éclair plan")) == "Éclair plan",
               "a new name starts with a capital, as a break's does", &problems)
        expect(resolve(.fresh("landing page")) == "Landing page" && resolve(.fresh("x")) == "X",
               "a lowercase name and a single letter are capitalised", &problems)
        expect(resolve(.fresh("iOS build")) == "iOS build" && resolve(.fresh("macOS port")) == "macOS port",
               "a brand's own spelling is not capitalised", &problems)
        expect(resolve(.fresh("Daybook\nparser"), earlier: []) == "Daybook parser",
               "a newline between words becomes one space", &problems)
        expect(resolve(.fresh("Daybook   parser"), earlier: []) == "Daybook parser",
               "repeated spaces collapse", &problems)
        expect(resolve(.fresh("daybook \t parser"), earlier: ["Daybook Parser"]) == "Daybook Parser",
               "odd spacing still takes the earlier spelling", &problems)
        expect(resolve(.fresh("Deep work")) == nil, "a category name is refused", &problems)
        expect(resolve(.fresh("Xcode")) == nil, "an app's name is refused", &problems)
        expect(resolve(.none) == nil, "none gives nothing", &problems)
        return problems
    }

    /// Ten apps share the session evenly. Each of four earlier sessions
    /// covers one app, so alone each shares only 0.1; together they cover
    /// four apps and share 0.1 + 0.1 + 0.1 + 500/6500, over the threshold.
    private static func pooling() -> [String] {
        var problems: [String] = []
        let session = Dictionary(uniqueKeysWithValues: (0..<10).map { ("s\($0)", 100.0) })
        let history = [earlier("Notes", daysAgo: 4, ["s0": 3000]), earlier("Notes", daysAgo: 3, ["s1": 2000]),
                       earlier("Notes", daysAgo: 2, ["s2": 1000]), earlier("Notes", daysAgo: 1, ["s3": 500])]
        for single in history {
            SelfTest.expectClose(NameCandidates.shared(session, single.appSeconds), 0.1,
                                 "one earlier session alone shares 0.1", &problems)
        }
        let ranked = NameCandidates.rank(appSeconds: session, workType: .deepWork, history: history)
        expect(ranked.map(\.name) == ["Notes"], "pooled, Notes clears the threshold; got \(ranked.map(\.name))", &problems)
        SelfTest.expectClose(ranked.first?.score ?? 0, 0.1 * 3 + 500.0 / 6500 + 0.1,
                             "the score is the pooled shared time plus the bonus", &problems)
        expect(ranked.first?.usualApps == ["s0", "s1", "s2"],
               "the usual apps follow the pooled mix, got \(ranked.first?.usualApps ?? [])", &problems)
        return problems
    }
}
