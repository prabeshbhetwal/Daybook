import Foundation

/// History works out and names its periods in the calendar it is handed.
/// The app always hands it the Mac's own, so a slip shows only when the
/// two differ: on a check runner in another time zone, a Sydney fixture's
/// September was titled August.
enum HistoryCalendarChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("History's spans, titles and readings follow the calendar it is handed, not the Mac's time zone",
         followsHandedCalendar)
    ]

    /// Kiritimati, UTC+14: its midnights fall on the previous date in every
    /// other zone in use, so a period named in the Mac's zone reads a day,
    /// month or year early wherever the checks run.
    private static func followsHandedCalendar() -> [String] {
        var base = Calendar(identifier: .gregorian)
        base.timeZone = TimeZone(identifier: "Pacific/Kiritimati")!
        let calendar = HistoryTreeBuilder.calendar(base)
        func date(_ month: Int, _ day: Int, year: Int = 2026) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day))!
        }
        func day(_ date: Date) -> HistoryDay {
            HistoryDay(date: date, tracked: 0, focused: 600, sessions: 1, appBundleIDs: [], workTypes: [.deepWork])
        }
        let today = date(9, 29)
        // From the 1st: read in the Mac's zone, the record would begin in June.
        let days = [day(date(9, 28)), day(date(7, 1, year: 2025))]
        var problems: [String] = []

        // The whole record: its span ends at the end of today, there.
        let top = HistoryTreeBuilder.top(days: days, today: today, calendar: calendar)
        let end = HistoryTreeBuilder.dayAfter(today, calendar: calendar)
        expect(top.place == nil && top.span.end == end,
               "the record's span ends at \(end), got \(top.span.end)", &problems)

        func title(_ row: HistoryRow?) -> String {
            row.map { HistoryRowText.title($0.place, today: today, calendar: calendar) } ?? "no row"
        }
        let year = HistoryTreeBuilder.rows(under: nil, top: top, days: days, calendar: calendar).first
        let month = year.flatMap { HistoryTreeBuilder.rows(under: $0.place, top: top, days: days, calendar: calendar).first }
        let week = month.flatMap { HistoryTreeBuilder.rows(under: $0.place, top: top, days: days, calendar: calendar).first }
        let weekDays = week.map { HistoryTreeBuilder.rows(under: $0.place, top: top, days: days, calendar: calendar) } ?? []
        expect(title(year) == "2026", "this year is titled 2026, got \(title(year))", &problems)
        expect(title(month) == "September", "this month is titled September, got \(title(month))", &problems)
        expect(title(week) == "28 – 29 Sep", "this week is titled 28 – 29 Sep, got \(title(week))", &problems)
        let monday = weekDays.dropFirst().first
        expect(title(monday) == "Mon 28 Sep", "yesterday is titled Mon 28 Sep, got \(title(monday))", &problems)
        // January's year, said aloud: midnight on the 1st is still last year west of here.
        let january = year.flatMap { HistoryTreeBuilder.rows(under: $0.place, top: top, days: days, calendar: calendar).last }
        let spoken = january.map { HistoryRowText.spoken($0, today: today, isOpen: false, depth: 1, calendar: calendar) } ?? ""
        expect(spoken.hasPrefix("January 2026,"), "January is spoken as \"\(spoken)\"", &problems)

        // The headline over each kind of top, each record starting on a 1st.
        func eyebrow(_ recorded: [Date]) -> String {
            let days = recorded.map(day)
            let top = HistoryTreeBuilder.top(days: days, today: today, calendar: calendar)
            let summary = HistoryTreeBuilder.summary(top: top, days: days, calendar: calendar)
            return HistoryRowText.headline(top: top, summary: summary, calendar: calendar).eyebrow
        }
        let eyebrows = [eyebrow(days.map(\.date)), eyebrow([date(1, 1)]), eyebrow([date(9, 1)]),
                        eyebrow([date(9, 28)]), eyebrow([date(9, 29)])]
        let wanted = ["On record since 1 July 2025", "2026", "September 2026", "28 – 29 September", "Tuesday 29 September"]
        expect(eyebrows == wanted, "the headlines read \(eyebrows), wanted \(wanted)", &problems)

        let reading = HistoryPeriodRail.reading(for: nil, top: top, calendar: calendar)
        expect(calendar.isDate(reading.anchor, inSameDayAs: today) && reading.limit == 15,
               "the record reads 15 months to today, got \(reading.limit) to \(reading.anchor)", &problems)

        // A month on top names its year on the path.
        let september = HistoryPlace(level: .month, span: DateInterval(start: date(9, 1), end: date(10, 1)))
        let monthTop = HistoryTop(place: september, firstDay: date(9, 17), today: today, calendar: calendar)
        let crumb = HistoryPath.crumbs(top: monthTop, open: [], session: nil, today: today, calendar: calendar).first?.title
        expect(crumb == "September 2026", "a month on top reads September 2026, got \(crumb ?? "nothing")", &problems)
        return problems
    }
}
