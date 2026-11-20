import Foundation

/// A category set not to count toward focus, where the first round missed it (Phase C review, ruling C11): a
/// goal on it is paused rather than missed, Ask counts focus stretch by stretch, and a running session in it adds
/// nothing to focused-active time.
enum NonCountingReviewChecks: CheckSuite {
    private typealias Fixture = FocusPropertyFixture

    static let tests: [(String, () -> [String])] = [
        ("A goal on a category that no longer counts toward focus is recorded as paused, and judged again once it counts",
         goalOnANonCountingCategoryPauses),
        ("Ask counts focus stretch by stretch, not by a session's newest category", askCountsEachStretch),
        ("A running session in a category that does not count adds no focused-active time", runningNonFocusAddsNothing),
    ]

    private static func goalOnANonCountingCategoryPauses() -> [String] {
        var problems: [String] = []
        let goal = DailyGoalItem(target: .category(Fixture.reading.rawValue), kind: .target, seconds: 3_600)
        Fixture.withCatalogue([Fixture.readingDefinition { $0.countsTowardFocus = false }]) {
            let results = GoalDayResults.close(goals: [goal], credit: [WorkType.deepWork.rawValue: 600],
                                               appUse: ["com.example.editor": 600]) ?? []
            expect(results.count == 1 && results.first?.paused == true && results.first?.met == false,
                   "a goal on a category that does not count was judged: \(results)", &problems)
        }
        Fixture.withCatalogue([Fixture.readingDefinition()]) {
            let results = GoalDayResults.judge([goal], credit: [:], appUse: [:])
            expect(results.count == 1 && results.first?.paused != true,
                   "the goal was not judged again once its category counted: \(results)", &problems)
        }
        return problems
    }

    private static func askCountsEachStretch() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            f.engine.store.workTypeDefinitions = [Fixture.readingDefinition { $0.countsTowardFocus = false }]
            defer { f.engine.store.workTypeDefinitions = [] }
            let today = f.calendar.startOfDay(for: f.clock.value)
            func at(_ back: Int, _ hour: Int, _ minute: Int = 0) -> Date {
                let day = f.calendar.date(byAdding: .day, value: -back, to: today)!
                return f.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
            }
            // One session this morning: an hour of Reading, which does not count, then an hour of Deep work. Another
            // on Monday evening: an hour of Deep work, then Reading from 11pm into Tuesday.
            let (morning, evening) = (UUID(), UUID())
            let stretches = [
                SessionRecord(name: "Essay", workType: Fixture.reading, start: at(0, 6), end: at(0, 7), workSeconds: 3_600, threadID: morning),
                SessionRecord(name: "Essay", workType: .deepWork, start: at(0, 7), end: at(0, 8), workSeconds: 3_600, threadID: morning),
                SessionRecord(name: "Essay", workType: .deepWork, start: at(2, 21), end: at(2, 22), workSeconds: 3_600, threadID: evening),
                SessionRecord(name: "Essay", workType: Fixture.reading, start: at(2, 23), end: at(1, 0, 30), workSeconds: 5_400,
                              threadID: evening),
            ]
            guard stretches.allSatisfy({ f.engine.archive.append($0) == nil }) else { return problems.append("could not save the sessions") }
            let got = f.store.askLookup(.focusTotals(.today, words: "essay"))
            expect(got.contains(": 1h over 1 session"), "Ask counted the stretch that does not count as focus: \(got)", &problems)
            let week = f.store.askLookup(.focusTotals(.thisWeek, words: "essay"))
            expect(week.contains(": 2h over 2 sessions on 2 days"),
                   "Ask counted a day only a stretch that does not count fell on: \(week)", &problems)
        }
    }

    private static func runningNonFocusAddsNothing() -> [String] {
        var problems: [String] = []
        let start = SelfTest.base
        func at(_ offset: TimeInterval) -> Date { start.addingTimeInterval(offset) }
        // Two records over the same ten minutes, and hands-on time then and again while a session that does not count runs.
        let records = ["A", "B"].map { SessionRecord(name: $0, workType: .deepWork, start: start, end: at(600), workSeconds: 600) }
        let usage = [AppUsageSession(bundleID: "com.example.editor", appName: "Editor", start: start, end: at(600)),
                     AppUsageSession(bundleID: "com.example.editor", appName: "Editor", start: at(1_200), end: at(1_800))]
        let interval = DateInterval(start: start, duration: 3_600)
        let alone = FocusedActiveTime.seconds(in: interval, records: records, usage: usage, running: nil)
        let beside = FocusedActiveTime.seconds(in: interval, records: records, usage: usage,
                                               running: (start: at(1_200), end: at(1_800)), runningWork: 0)
        expect(alone == 600 && beside == alone,
               "a running span that does not count added focus: noRunning=\(alone) withNonFocusRunning=\(beside)", &problems)
        return problems
    }
}
