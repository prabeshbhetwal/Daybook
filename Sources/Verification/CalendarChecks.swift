import Foundation

/// Periods that read the same whatever calendar and region the Mac is set to.
/// History names its periods in Gregorian, so it works them out in Gregorian;
/// every screen's week runs Monday to Sunday. Under an Islamic calendar a
/// History row titled September ran from 12 September to 11 October, and in a
/// US region Review's week began on the Sunday that History's week ended on.
enum CalendarChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("History works out and names Gregorian periods whatever calendar the Mac uses",
         historyIsGregorian),
        ("Every screen's week runs Monday to Sunday whatever the region says",
         weeksStartMonday)
    ]

    private static func historyIsGregorian() -> [String] {
        var islamic = Calendar(identifier: .islamicUmmAlQura)
        islamic.timeZone = TimeZone(identifier: "Australia/Sydney")!
        var sydney = Calendar(identifier: .gregorian)
        sydney.timeZone = islamic.timeZone
        func date(_ month: Int, _ day: Int) -> Date {
            sydney.date(from: DateComponents(year: 2026, month: month, day: day))!
        }
        let calendar = HistoryTreeBuilder.calendar(islamic)
        let today = date(10, 7)
        let days = [date(10, 6), date(9, 23)].map {
            HistoryDay(date: $0, tracked: 0, focused: 600, sessions: 1, appBundleIDs: [], workTypes: [.deepWork])
        }
        var problems: [String] = []
        expect(calendar.identifier == .gregorian && calendar.timeZone == islamic.timeZone && calendar.firstWeekday == 2,
               "History's calendar is \(calendar.identifier) in \(calendar.timeZone.identifier), weeks from day \(calendar.firstWeekday)",
               &problems)
        // 23 September to 7 October spans two Gregorian months, so the top is the year.
        let top = HistoryTreeBuilder.top(days: days, today: today, calendar: calendar)
        let months = HistoryTreeBuilder.rows(under: nil, top: top, days: days, calendar: calendar)
        let names = months.map { HistoryRowText.title($0.place, today: today, calendar: calendar) }
        expect(top.place?.level == .year && names == ["October", "September"],
               "the record read \(String(describing: top.place?.level)) with rows \(names)", &problems)
        if let october = months.first {
            expect(october.place.span.start == date(10, 1) && october.focused == 600,
                   "October began \(october.place.span.start) holding \(october.focused)s", &problems)
        }
        return problems
    }

    /// Where a screen takes a calendar, it is handed a Sunday-first one; where
    /// it reads the Mac's own, this bites in a Sunday-first region such as
    /// GitHub's US runner.
    private static func weeksStartMonday() -> [String] {
        MainActor.assumeIsolated {
            var sundayFirst = SelfTest.gregorian
            sundayFirst.firstWeekday = 1
            let sunday = SelfTest.gregorian.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 12))!
            let monday = SelfTest.gregorian.date(from: DateComponents(year: 2026, month: 10, day: 5))!
            let clock = TestClock(sunday)
            var problems: [String] = []

            let stats = PeriodStats(sessions: SessionArchive(directory: SelfTest.scratchDirectory(), now: { clock.value }),
                                    usage: AppUsageArchive(directory: SelfTest.scratchDirectory(), now: { clock.value }),
                                    calendar: sundayFirst, now: { clock.value })
            expect(stats.bounds(for: .week, containing: sunday).start == monday,
                   "a period roll-up's week began \(stats.bounds(for: .week, containing: sunday).start)", &problems)

            let store = SessionStore(engine: SelfTest.makeEngine(clock), now: { clock.value })
            let projected = store.insightPeriodProjections(scope: .week, anchoredAt: sunday, limit: 1,
                                                           calendar: sundayFirst).first?.start
            expect(projected == monday, "Insights' week began \(String(describing: projected))", &problems)
            let labels = InsightGridRows(scope: .week, periods: [], calendar: sundayFirst).labels
            expect(labels.first == "MON" && labels.last == "SUN", "Insights' weekdays read \(labels)", &problems)

            store.reviewPeriod = .week
            store.reviewAnchor = sunday
            expect(store.reviewPeriodStart == monday, "Review's week began \(store.reviewPeriodStart)", &problems)
            expect(store.storyReviewBounds().start == monday,
                   "the story's week began \(store.storyReviewBounds().start)", &problems)
            return problems
        }
    }
}
