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
         weeksStartMonday),
        ("Review, Insights, the story and History search work out the months History names",
         periodsMatchHistory)
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

    /// A zone whose offset differs from the Mac's in October 2026. A calendar
    /// handed to a screen in it works out different instants from
    /// `Calendar.current`, so a screen that reads the Mac's own instead fails
    /// whatever region and calendar the Mac is set to.
    private static var awayZone: TimeZone {
        let far = TimeZone(identifier: "Pacific/Kiritimati")!
        let moment = SelfTest.gregorian.date(from: DateComponents(year: 2026, month: 10, day: 7))!
        return far.secondsFromGMT(for: moment) == TimeZone.current.secondsFromGMT(for: moment)
            ? TimeZone(identifier: "Pacific/Pago_Pago")! : far
    }

    /// Each screen is handed a Sunday-first calendar in `awayZone`, the store
    /// through `periodCalendarBase`, so this bites on a Monday-first Mac too.
    private static func weeksStartMonday() -> [String] {
        MainActor.assumeIsolated {
            var sundayFirst = Calendar(identifier: .gregorian)
            sundayFirst.timeZone = awayZone
            sundayFirst.firstWeekday = 1
            let sunday = sundayFirst.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 12))!
            let monday = sundayFirst.date(from: DateComponents(year: 2026, month: 10, day: 5))!
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

            store.periodCalendarBase = sundayFirst
            store.reviewPeriod = .week
            store.reviewAnchor = sunday
            expect(store.reviewPeriodStart == monday, "Review's week began \(store.reviewPeriodStart)", &problems)
            expect(store.storyReviewBounds().start == monday,
                   "the story's week began \(store.storyReviewBounds().start)", &problems)
            store.moveReviewPeriod(by: -1)
            let previous = sundayFirst.date(byAdding: .day, value: -7, to: monday)!
            expect(store.reviewPeriodStart == previous,
                   "a week back, Review's week began \(store.reviewPeriodStart)", &problems)
            return problems
        }
    }

    /// Under Umm al-Qura, 7 October 2026 falls in a month that runs from 12
    /// September to 11 October. Every screen titles its months in Gregorian,
    /// so each must work out the Gregorian month History's tree shows. The
    /// calendar is in `awayZone`, so a screen reading the Mac's own fails too.
    private static func periodsMatchHistory() -> [String] {
        MainActor.assumeIsolated {
            var islamic = Calendar(identifier: .islamicUmmAlQura)
            islamic.timeZone = awayZone
            var gregorian = Calendar(identifier: .gregorian)
            gregorian.timeZone = islamic.timeZone
            func date(_ month: Int, _ day: Int, hour: Int = 0) -> Date {
                gregorian.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
            }
            let anchor = date(10, 7, hour: 12)
            let clock = TestClock(anchor)
            var problems: [String] = []

            let tree = HistoryTreeBuilder.calendar(islamic)
            let october = tree.dateInterval(of: .month, for: anchor)
            expect(october == DateInterval(start: date(10, 1), end: date(11, 1)),
                   "History's October ran \(String(describing: october))", &problems)

            let stats = PeriodStats(sessions: SessionArchive(directory: SelfTest.scratchDirectory(), now: { clock.value }),
                                    usage: AppUsageArchive(directory: SelfTest.scratchDirectory(), now: { clock.value }),
                                    calendar: islamic, now: { clock.value })
            let bounds = stats.bounds(for: .month, containing: anchor)
            expect(bounds.start == date(10, 1) && bounds.end == date(11, 1),
                   "a period roll-up's month ran \(bounds.start) to \(bounds.end)", &problems)

            // Search hits newest first, two in October and one in September.
            let hits = [date(10, 7, hour: 9), date(10, 1, hour: 9), date(9, 30, hour: 9)].map { start in
                HistorySearchHit(id: UUID(), threadID: UUID(), name: "Draft", workType: .deepWork,
                                 start: start, end: start.addingTimeInterval(600), worked: 600,
                                 day: start, noteSnippet: nil, matchedApps: [])
            }
            let months = HistoryJournalBuilder.entries(matching: hits, calendar: islamic).compactMap { entry -> JournalMonth? in
                if case .month(let month) = entry { return month }
                return nil
            }
            let titles = months.map { HistoryMonthHeader.title($0.start, in: islamic.timeZone) }
            expect(titles == ["October 2026", "September 2026"] && months.first?.focused == 1_200
                       && months.first?.dailyFocus.count == 31,
                   "search grouped \(titles) holding \(months.map(\.focused))s over \(months.map(\.dailyFocus.count)) days",
                   &problems)

            let store = SessionStore(engine: SelfTest.makeEngine(clock), now: { clock.value })
            store.periodCalendarBase = islamic
            expect(store.periodCalendar.identifier == .gregorian && store.periodCalendar.firstWeekday == 2,
                   "the store's periods are \(store.periodCalendar.identifier), weeks from day \(store.periodCalendar.firstWeekday)",
                   &problems)
            store.reviewPeriod = .month
            store.reviewAnchor = anchor
            expect(store.reviewPeriodStart == date(10, 1) && store.reviewPeriodLabel == "October 2026",
                   "Review's month \(store.reviewPeriodLabel) began \(store.reviewPeriodStart)", &problems)
            let story = store.storyReviewBounds()
            expect(story == DateInterval(start: date(10, 1), end: date(11, 1)),
                   "the story's month ran \(story)", &problems)
            store.moveReviewPeriod(by: -1)
            expect(store.reviewPeriodStart == date(9, 1) && store.reviewPeriodLabel == "September 2026",
                   "a month back, Review's month \(store.reviewPeriodLabel) began \(store.reviewPeriodStart)", &problems)

            let projected = store.insightPeriodProjections(scope: .month, anchoredAt: anchor, limit: 1,
                                                           calendar: islamic).first?.start
            expect(projected == date(10, 1), "Insights' month began \(String(describing: projected))", &problems)
            return problems
        }
    }
}
