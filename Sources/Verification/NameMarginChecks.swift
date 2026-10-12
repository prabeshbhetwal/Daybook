import Foundation

/// The margin rule for name suggestions (ruling S13): when the best earlier
/// name leads the second by less than 0.1, the session is ambiguous and is
/// neither asked about nor offered. Also where an offer's source is checked:
/// a reused earlier name reads as the person's own, a fresh one as the
/// model's. Kept apart from the other name suites so their numbers and file
/// sizes hold.
enum NameMarginChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A lead of 0.1 or more is clear, less is ambiguous, and one candidate is clear", leadRows),
        ("An ambiguous session is not asked about and not offered", ambiguousNotAsked),
        ("An earlier name's offer has the earlier source and a fresh name's the fresh one", offerSource),
    ]

    private typealias Checks = NameSuggestionStoreChecks

    private static func candidate(_ name: String, _ score: Double) -> NameCandidate {
        NameCandidate(name: name, score: score, usualWorkType: .deepWork, usualApps: [])
    }

    private static func leadRows() -> [String] {
        var problems: [String] = []
        expect(NameCandidates.margin == 0.1, "the margin is \(NameCandidates.margin), not 0.1", &problems)
        expect(NameCandidates.isClearLead([candidate("A", 0.9), candidate("B", 0.78)]),
               "a lead of 0.12 should be clear", &problems)
        expect(!NameCandidates.isClearLead([candidate("A", 0.9), candidate("B", 0.85)]),
               "a lead of 0.05 should be ambiguous", &problems)
        expect(!NameCandidates.isClearLead([candidate("A", 0.5), candidate("B", 0.5)]),
               "a tie should be ambiguous", &problems)
        expect(NameCandidates.isClearLead([candidate("A", 0.4)]), "one candidate should be clear", &problems)
        expect(NameCandidates.isClearLead([]), "no candidates should be clear (the second question decides)", &problems)
        expect(NameCandidates.isClearLead([candidate("A", 0.9), candidate("B", 0.5), candidate("C", 0.49)]),
               "only the first two are compared", &problems)
        return problems
    }

    /// Today 7:00–7:30 in Xcode. "Daybook" and "Thesis" both used Xcode only,
    /// so they tie. With Thesis in Pages instead, Daybook is the only candidate.
    private static func fixture(thesisApp: String, _ body: @MainActor (NameSuggestionStoreChecks.Fixture, inout [String]) -> Void) -> [String] {
        Checks.withFixture(records: { days in [
            Checks.record(days.at(0, 7), days.at(0, 7, 30)),
            Checks.record(days.at(3, 9), days.at(3, 10), name: "Daybook"),
            Checks.record(days.at(4, 9), days.at(4, 10), name: "Thesis"),
        ] }, usage: { days in [
            Checks.app("Xcode", days.at(0, 7), 25 * 60), Checks.app("Xcode", days.at(3, 9), 50 * 60),
            Checks.app(thesisApp, days.at(4, 9), 50 * 60),
        ] }) { f, _, problems in body(f, &problems) }
    }

    @MainActor private static func ask(_ f: NameSuggestionStoreChecks.Fixture) -> (offered: String?, calls: Int) {
        f.persistence.useAppleIntelligence = true
        let suggester = NameSuggester(store: f.store)
        var calls = 0
        suggester.responder = { _ in calls += 1; return .earlier(1) }
        suggester.refresh()
        _ = InstalledAppCatalog.turnRunLoop(until: { !suggester.isAsking }, timeout: 5)
        return (suggester.current?.name, calls)
    }

    private static func ambiguousNotAsked() -> [String] {
        var problems = fixture(thesisApp: "Xcode") { f, problems in
            let names = f.store.nameSuggestionTargets().first.flatMap { f.store.nameFacts(for: $0) }?.candidates.map(\.name)
            expect(names?.count == 2, "the tie should leave two candidates, got \(String(describing: names))", &problems)
            let result = ask(f)
            expect(result.calls == 0 && result.offered == nil,
                   "an ambiguous session: asked \(result.calls) times, offered \(String(describing: result.offered))", &problems)
        }
        problems += fixture(thesisApp: "Pages") { f, problems in
            let result = ask(f)
            expect(result.calls == 1 && result.offered == "Daybook",
                   "a clear session: asked \(result.calls) times, offered \(String(describing: result.offered))", &problems)
        }
        return problems
    }

    private static func offerSource() -> [String] {
        var problems = fixture(thesisApp: "Pages") { f, problems in
            f.persistence.useAppleIntelligence = true
            let suggester = NameSuggester(store: f.store)
            suggester.responder = { _ in .earlier(1) }
            suggester.refresh()
            _ = InstalledAppCatalog.turnRunLoop(until: { !suggester.isAsking }, timeout: 5)
            expect(suggester.current?.name == "Daybook" && suggester.current?.source == .earlier,
                   "an earlier answer offered \(String(describing: suggester.current?.name)) as \(String(describing: suggester.current?.source))",
                   &problems)
        }
        let thread = UUID()
        problems += Checks.withFixture(records: { days in [Checks.record(days.at(0, 7), days.at(0, 7, 30), thread: thread)] }) { f, _, problems in
            guard let session = Checks.target(f, thread) else { return problems.append("the session is not offered") }
            _ = f.metadata.saveNote("fixed parser for fortnight", for: session.recordIDs[0])
            f.persistence.useAppleIntelligence = true
            let suggester = NameSuggester(store: f.store)
            suggester.responder = { _ in .fresh("Fortnight parser") }
            suggester.refresh()
            _ = InstalledAppCatalog.turnRunLoop(until: { !suggester.isAsking }, timeout: 5)
            expect(suggester.current?.name == "Fortnight parser" && suggester.current?.source == .fresh,
                   "a fresh answer offered \(String(describing: suggester.current?.name)) as \(String(describing: suggester.current?.source))",
                   &problems)
        }
        return problems
    }
}
