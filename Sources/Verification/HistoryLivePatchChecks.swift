import Foundation

/// A running session lifts today's figures in History without a rebuild. A
/// period that merely ends at today's midnight (yesterday, last week on a
/// Monday, last month on the 1st) holds none of today, so it must not move.
enum HistoryLivePatchChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A running session adds to today in History and to no period that ended before it",
         liveGrowthStaysInToday),
    ]

    /// The fixture's History holds Mon 13 and Tue 14 Nov and Tue 17 Oct. Each
    /// case moves the clock to a day on which the period under test has just
    /// ended, starts a session, lets History's tree cache the period, then
    /// lets the session grow an hour.
    private static let cases: [(label: String, daysLater: Int, level: HistoryLevel, range: AskRange)] = [
        ("yesterday", 0, .day, .yesterday),
        ("last week on a Monday", 5, .week, .lastWeek),
        ("last month on the 1st", 16, .month, .lastMonth),
    ]

    private static func liveGrowthStaysInToday() -> [String] {
        var problems: [String] = []
        for item in cases {
            problems += AskLookupChecks.withFixture { f, problems in
                let calendar = f.calendar
                let now = calendar.date(byAdding: .day, value: item.daysLater, to: f.clock.value) ?? f.clock.value
                f.clock.value = now
                let startOfToday = calendar.startOfDay(for: now)
                let earlier = HistoryPlace(level: item.level,
                                           span: item.range.interval(now: now, firstDay: now, calendar: calendar))
                expect(earlier.span.end == startOfToday, "\(item.label): the period ends at \(earlier.span.end), "
                       + "not at the start of today (\(startOfToday)), so the case tests nothing", &problems)
                let today = HistoryPlace(level: .day, span: DateInterval(
                    start: startOfToday, end: HistoryTreeBuilder.dayAfter(startOfToday, calendar: calendar)))

                f.engine.start(workType: .deepWork, intent: "Probe")
                f.clock.advance(10 * 60)
                _ = f.store.askLookup(.focusTotals(.today, words: nil))
                let before = f.store.historySummary(for: earlier)
                let todayBefore = f.store.historySummary(for: today)
                expect(todayBefore.focused == 600, "\(item.label): today reads \(todayBefore.focused)s, not 600s",
                       &problems)

                f.clock.advance(60 * 60)
                _ = f.store.askLookup(.focusTotals(.today, words: nil))
                let after = f.store.historySummary(for: earlier)
                expect(after == before, "\(item.label): the period moved from \(before.focused)s to "
                       + "\(after.focused)s while today's session ran", &problems)
                let todayAfter = f.store.historySummary(for: today)
                expect(todayAfter.focused == 600 + 3_600, "\(item.label): today reads \(todayAfter.focused)s, "
                       + "not 4200s, after the session ran another hour", &problems)
            }
        }
        return problems
    }
}
