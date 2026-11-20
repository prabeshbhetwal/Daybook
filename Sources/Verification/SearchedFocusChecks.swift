import Foundation

/// The searched journal's focus for a session filed partly under a category set not to count: its figures add
/// the stretches that count, whichever category its newest stretch carries.
enum SearchedFocusChecks: CheckSuite {
    typealias Fixture = NonCountingFixture

    static let tests: [(String, () -> [String])] = [
        ("A searched session with stretches that count and stretches that do not adds only the counting focus",
         countingStretchesOnly),
    ]

    private static func countingStretchesOnly() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            // Yesterday, one session called Thesis: an hour in one category and, after a gap, an hour in the other.
            for (order, types) in [("Deep work then Reading", [WorkType.deepWork, Fixture.reading]),
                                   ("Reading then Deep work", [Fixture.reading, WorkType.deepWork])] {
                let thread = UUID()
                let stretches = zip([9, 11], types).map { hour, type in
                    SessionRecord(name: "Thesis", workType: type, start: Fixture.Base.at(-1, hour),
                                  end: Fixture.Base.at(-1, hour + 1), workSeconds: 3_600, threadID: thread)
                }
                guard let f = Fixture(extra: stretches) else { return ["the fixture could not be set up"] }
                defer { f.cleanUp() }
                f.store.setHistoryQuery("thesis")
                let entries = f.store.historyJournal()
                let days = entries.compactMap { entry -> JournalDay? in
                    if case .day(let day) = entry { return day }
                    return nil
                }
                let months = entries.compactMap { entry -> JournalMonth? in
                    if case .month(let month) = entry { return month }
                    return nil
                }
                expect(days.count == 1 && days[0].threads == [thread],
                       "\(order): the search listed \(days.count) days, not Thesis's one", &problems)
                expect(days.first?.focused == 3_600 && days.first?.sessions == 1,
                       "\(order): the day showed \(days.first?.focused ?? -1) seconds over "
                       + "\(days.first?.sessions ?? -1) sessions, not 3600 over 1", &problems)
                expect(months.count == 1 && months[0].focused == 3_600 && months[0].focusedDays == 1,
                       "\(order): the month showed \(months.first?.focused ?? -1) seconds over "
                       + "\(months.first?.focusedDays ?? -1) focused days, not 3600 over 1", &problems)
            }
            return problems
        }
    }
}
