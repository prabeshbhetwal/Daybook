import Foundation

/// A week's or month's facts as specific as a day's. The live probe's week and
/// month notes dropped their figures ("Thesis for hours"), wrote them in words
/// and totalled "other sessions" out of the rest, so the facts now name the top
/// three sessions only and carry sentences a note can quote whole: the best
/// day, a month's busiest weekday, the longest stretch with its day and time,
/// the comparison, the goal days. Uses the Ask fixture for the store checks:
/// Thesis on Mon 13 Nov 9 to 10 am, Parser on Tue 14 Nov 2:00 to 3:30 pm, the
/// clock on Wed 15 Nov at 9:13.
enum ReviewNotePeriodChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A week's or month's facts name the three sessions with the most time and the observations a note can quote",
         periodObservations),
        ("A month names its busiest weekday and a week does not", busiestWeekday),
        ("A period's facts count the sessions they name, and each count of one, two or three has its own form", namedSessions),
        ("A week's and a month's longest stretch is the Story's, pause taken out, and a blank session name is its kind's",
         periodFromStore),
    ]

    private static let calendar = SelfTest.gregorian

    private static func at(_ hour: Int, _ minute: Int, on day: Date) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    /// Monday 13 Nov 2023 to Sunday 19 Nov, with a best day on the Tuesday and a weekday that was busiest.
    private static let fiveSessions: [(name: String, worked: TimeInterval)] = [
        ("Thesis", 40_000), ("Parser", 30_000), ("Email", 12_000), ("Reading", 5_000), ("Misc", 3_000)]

    private static func input(_ level: HistoryLevel, weekday: NoteWeekday?,
                              totals: [(name: String, worked: TimeInterval)] = fiveSessions) -> NotePeriodInput {
        let monday = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: SelfTest.base))!
        let tuesday = calendar.date(byAdding: .day, value: 1, to: monday)!
        let end = calendar.date(byAdding: .day, value: 7, to: monday)!
        let best = HistoryPlace(level: .day, span: DateInterval(start: tuesday, end: calendar.date(byAdding: .day, value: 1, to: tuesday)!))
        let summary = HistorySummary(focused: 90_000, tracked: 100_000, focusedDays: 4, sessions: 9,
                                     best: (place: best, focused: 28_800))
        return NotePeriodInput(span: DateInterval(start: monday, end: end), level: level, isCurrent: false,
                               summary: summary,
                               sessionTotals: totals,
                               goal: 7_200, goalMetDays: 3, previousFocused: 86_400,
                               longestStretch: NoteStretch(name: "Thesis", start: at(8, 0, on: tuesday), worked: 18_000),
                               busiestWeekday: weekday)
    }

    private static func periodObservations() -> [String] {
        var problems: [String] = []
        let tuesday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: SelfTest.base))!
        guard let month = NoteFacts.period(input(.month, weekday: NoteWeekday(date: tuesday, focused: 36_000, days: 2)),
                                           calendar: calendar) else { return ["a month with sessions produced no facts"] }
        expect(month.lines.contains("Most time went to: Thesis: 11h 6m; Parser: 8h 20m; Email: 3h 20m"),
               "the most-time line should hold the top three only: \(month.lines)", &problems)
        expect(month.observations == ["Best day: Tuesday 14 November 2023 with 8h",
                                      "Busiest weekday: Tuesday with 10h over 2 days",
                                      "Longest stretch: 5h in Thesis, on Tuesday 14 November 2023 from 8:00 am",
                                      "1h more focus than the month before",
                                      "Goal met on 3 of 4 days with focus"],
               "a month's observations are \(month.observations)", &problems)
        expect(month.patternOnly.isEmpty && !month.text.contains("Context:"),
               "a month has no tip, so no observation is kept from one: \(month.text)", &problems)
        return problems
    }

    private static func busiestWeekday() -> [String] {
        var problems: [String] = []
        let tuesday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: SelfTest.base))!
        guard let week = NoteFacts.period(input(.week, weekday: NoteWeekday(date: tuesday, focused: 36_000, days: 2)),
                                          calendar: calendar) else { return ["a week with sessions produced no facts"] }
        expect(!week.observations.contains { $0.hasPrefix("Busiest weekday") },
               "a week named a busiest weekday: \(week.observations)", &problems)
        guard let month = NoteFacts.period(input(.month, weekday: nil), calendar: calendar) else {
            return problems + ["a month with sessions produced no facts"]
        }
        expect(!month.observations.contains { $0.hasPrefix("Busiest weekday") },
               "a month with one weekday named a busiest weekday: \(month.observations)", &problems)
        return problems
    }

    /// A one-session week padded itself in the live run ("You spent 1h on Reading … and 1h on Reading …"), and a
    /// two-session one padded a third, so the model is asked for the form that fits how many the facts name.
    private static func namedSessions() -> [String] {
        guard #available(macOS 26, *) else { return [] }
        var problems: [String] = []
        let cases: [(Int, Int, PeriodForm)] = [(5, 3, .trio), (3, 3, .trio), (2, 2, .pair), (1, 1, .solo)]
        for (count, named, form) in cases {
            guard let facts = NoteFacts.period(input(.week, weekday: nil, totals: Array(fiveSessions.prefix(count))),
                                               calendar: calendar) else { return ["a week with sessions produced no facts"] }
            expect(facts.namedSessions == named, "\(count) sessions: the facts name \(facts.namedSessions), not \(named)", &problems)
            expect(PeriodForm.form(for: facts) == form, "\(count) sessions: asked for \(PeriodForm.form(for: facts)), not \(form)", &problems)
        }
        let day = NoteFacts(kind: .day, lines: ["Day: Wednesday 15 November 2023"], observations: [])
        expect(day.namedSessions == 0, "a day names no sessions for a period's form", &problems)
        return problems
    }

    private typealias Fixture = AskLookupChecks.Fixture

    private static func periodFromStore() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            f.store.setReviewVisible(true)
            let day = f.calendar.date(byAdding: .day, value: -2, to: f.calendar.startOfDay(for: f.clock.value))!
            let start = f.calendar.date(bySettingHour: 11, minute: 0, second: 0, of: day)!
            // Three hours on the clock, the third of them paused: two hours of work, unnamed.
            let blank = SessionRecord(name: "", workType: .deepWork, start: start,
                                      end: start.addingTimeInterval(10_800), workSeconds: 7_200,
                                      pausedSpans: [DateInterval(start: start.addingTimeInterval(3_600),
                                                                 end: start.addingTimeInterval(7_200))])
            guard f.engine.archive.append(blank) == nil else { problems.append("the session was not saved"); return }
            let title = WorkType.deepWork.sessionTitle(named: "")
            for level in [HistoryLevel.week, .month] {
                let place = HistoryPlace(level: level, span: HistoryTreeBuilder.period(level, containing: f.clock.value,
                                                                                     calendar: f.calendar))
                guard let facts = f.store.noteFacts(for: place) else { problems.append("\(level) has no facts"); continue }
                expect(facts.observations.contains("Longest stretch: 2h in \(title), on Monday 13 November 2023 from 11:00 am"),
                       "the \(level)'s observations are \(facts.observations)", &problems)
                expect(facts.lines.contains("Most time went to: \(title): 2h; Parser: 1h 30m; Thesis: 1h"),
                       "the \(level)'s most-time line is \(facts.lines)", &problems)
                expect(!facts.text.contains("Longest stretch: 3h"), "the \(level)'s facts count the pause: \(facts.text)", &problems)
            }
            // Monday held 3h of focus (2h and Thesis's 1h) against Tuesday's 1h 30m.
            let monthPlace = HistoryPlace(level: .month, span: HistoryTreeBuilder.period(.month, containing: f.clock.value,
                                                                                         calendar: f.calendar))
            let month = f.store.noteFacts(for: monthPlace)?.observations ?? []
            expect(month.contains("Busiest weekday: Monday with 3h over 1 day"), "the month's observations are \(month)", &problems)
            let week = f.store.noteFacts(for: HistoryPlace(level: .week, span: HistoryTreeBuilder.period(
                .week, containing: f.clock.value, calendar: f.calendar)))?.observations ?? []
            expect(!week.contains { $0.hasPrefix("Busiest weekday") }, "the week's observations are \(week)", &problems)
        }
    }
}
