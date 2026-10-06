import Foundation

/// Periods every screen works out in Gregorian, whatever calendar the Mac
/// uses, so each matches its Gregorian title and History's tree. Its own
/// suite, registered last, so the checks after `CalendarChecks` keep their
/// numbers.
enum PeriodCalendarChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Review, Insights, the story and History search work out the months History names",
         periodsMatchHistory)
    ]

    /// Under Umm al-Qura, 7 October 2026 falls in a month that runs from 12
    /// September to 11 October. Every screen titles its months in Gregorian,
    /// so each must work out the Gregorian month History's tree shows. The
    /// calendar is in `CalendarChecks.awayZone`, so a screen reading the
    /// Mac's own fails too.
    private static func periodsMatchHistory() -> [String] {
        MainActor.assumeIsolated {
            var islamic = Calendar(identifier: .islamicUmmAlQura)
            islamic.timeZone = CalendarChecks.awayZone
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
