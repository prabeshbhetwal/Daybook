import Foundation
import SwiftUI

/// Behavioural checks for History's tree: the top rule, clipping to the
/// record, week and month boundaries, and the pure helpers the model and
/// keyboard rely on. Fixtures are invented days; no archive is read.
enum HistoryTreeChecks {
    static let tests: [(String, () -> [String])] = [
        ("History opens on the smallest period that holds the whole record", topRule),
        ("Nothing is drawn before the first recorded day or after today", clippedToRecord),
        ("A week across a month boundary appears under both months, clipped, and the months still sum", weekAcrossMonths),
        ("Rows carry their category, hollow when only the Mac was seen, empty when nothing was", dots),
        ("Midnight adds today's row and, on a Monday, a new week", dayRollover),
        ("The opening path unfolds to this week and no further", pathToToday),
        ("Jump to date builds the path down to the day", pathToDay),
        ("A daylight-saving week keeps seven days", daylightSaving),
        ("The tree's summary names the best month for a year and the best day for a month", summaryBest)
    ]

    // MARK: - Fixtures

    /// Sydney, so the daylight-saving check meets a real transition.
    static let calendar: Calendar = HistoryTreeBuilder.calendar({
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
        calendar.locale = Locale(identifier: "en_AU")
        return calendar
    }())

    static func date(_ month: Int, _ day: Int, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    static func row(_ month: Int, _ day: Int, year: Int = 2026, focused: TimeInterval = 0,
                    tracked: TimeInterval = 0, sessions: Int = 0,
                    types: [WorkType: TimeInterval] = [:]) -> HistoryDay {
        HistoryDay(date: date(month, day, year: year), tracked: tracked, focused: focused, sessions: sessions,
                   appBundleIDs: [], workTypes: Set(types.keys), focusByWorkType: types)
    }

    /// Installed Wednesday 17 September 2026; today is Tuesday 29 September.
    static let september: [HistoryDay] = [
        row(9, 28, focused: 3_600, tracked: 4_000, sessions: 2, types: [.deepWork: 3_000, .admin: 600]),
        row(9, 22, focused: 1_800, tracked: 2_000, sessions: 1, types: [.admin: 1_800]),
        row(9, 19, tracked: 600),
        row(9, 17, focused: 900, tracked: 900, sessions: 1, types: [.learning: 900])
    ]
    static let today = date(9, 29)

    static func names(_ rows: [HistoryRow]) -> [String] {
        rows.map { row in
            let f = DateFormatter()
            f.calendar = calendar; f.timeZone = calendar.timeZone; f.locale = calendar.locale
            f.dateFormat = "d/M"
            let end = calendar.date(byAdding: .day, value: -1, to: row.place.span.end)!
            return "\(row.place.level) \(f.string(from: row.place.start))–\(f.string(from: end))"
        }
    }

    // MARK: - Top

    private static func topRule() -> [String] {
        var failures: [String] = []
        // Three days, all this week (Mon 28 – Tue 29 with a day before).
        let threeDays = [row(9, 28, focused: 60, sessions: 1), row(9, 27, focused: 60, sessions: 1)]
        // 27 Sep is a Sunday: the record leaves this week, so the top is the month.
        let leaves = HistoryTreeBuilder.top(days: threeDays, today: today, calendar: calendar)
        if leaves.place?.level != .month { failures.append("a record from last Sunday opened on \(String(describing: leaves.place?.level)), not the month") }
        let thisWeek = HistoryTreeBuilder.top(days: [row(9, 28, focused: 60, sessions: 1)], today: today, calendar: calendar)
        if thisWeek.place?.level != .week || thisWeek.rootLevel != .day {
            failures.append("a record inside this week did not open on the week with day rows")
        }
        let month = HistoryTreeBuilder.top(days: september, today: today, calendar: calendar)
        if month.place?.level != .month || month.rootLevel != .week || month.firstDay != date(9, 17) {
            failures.append("a record from the 17th did not open on the month with week rows from the 17th")
        }
        let year = HistoryTreeBuilder.top(days: september + [row(6, 3, focused: 60, sessions: 1)], today: today, calendar: calendar)
        if year.place?.level != .year || year.rootLevel != .month { failures.append("a record from June did not open on the year") }
        let record = HistoryTreeBuilder.top(days: september + [row(7, 3, year: 2025, focused: 60, sessions: 1)], today: today, calendar: calendar)
        if record.place != nil || record.rootLevel != .year || record.firstDay != date(7, 3, year: 2025) {
            failures.append("a record from last year did not open on the record with year rows")
        }
        let empty = HistoryTreeBuilder.top(days: [], today: today, calendar: calendar)
        if empty.place?.level != .week || empty.firstDay != today { failures.append("an empty archive did not open on this week from today") }
        return failures
    }

    // MARK: - Clipping

    private static func clippedToRecord() -> [String] {
        let top = HistoryTreeBuilder.top(days: september, today: today, calendar: calendar)
        var failures: [String] = []
        let weeks = HistoryTreeBuilder.rows(under: nil, top: top, days: september, calendar: calendar)
        let expected = ["week 28/9–29/9", "week 21/9–27/9", "week 17/9–20/9"]
        if names(weeks) != expected { failures.append("September's weeks read \(names(weeks)), expected \(expected)") }
        guard weeks.count == 3 else { return failures }
        // The first week is Monday 14 – Sunday 20 on the calendar, but the
        // record began on Wednesday 17: the row spans 17 – 20 and has four bars.
        let first = weeks[2]
        if first.place.span.start != date(9, 17) || first.bars.count != 4 {
            failures.append("the first week began \(first.place.span.start) with \(first.bars.count) bars, not the 17th with four")
        }
        let firstDays = HistoryTreeBuilder.rows(under: first.place, top: top, days: september, calendar: calendar)
        if names(firstDays) != ["day 20/9–20/9", "day 19/9–19/9", "day 18/9–18/9", "day 17/9–17/9"] {
            failures.append("the first week opened to \(names(firstDays))")
        }
        // This week ends today, not Sunday.
        let thisWeek = weeks[0]
        if thisWeek.bars.count != 2 { failures.append("this week drew \(thisWeek.bars.count) bars, not two") }
        // A year top: September's row has fourteen bars, 17th to 30th... but
        // today is the 29th, so thirteen.
        let yearTop = HistoryTreeBuilder.top(days: september + [row(6, 3, focused: 60, sessions: 1)], today: today, calendar: calendar)
        let months = HistoryTreeBuilder.rows(under: nil, top: yearTop, days: september + [row(6, 3, focused: 60, sessions: 1)], calendar: calendar)
        if names(months) != ["month 1/9–29/9", "month 1/8–31/8", "month 1/7–31/7", "month 3/6–30/6"] {
            failures.append("the year's months read \(names(months))")
        }
        if let sep = months.first, sep.bars.count != 29 { failures.append("September's row has \(months.first!.bars.count) bars, not 29") }
        if months.contains(where: { $0.place.span.end > calendar.date(byAdding: .day, value: 1, to: today)! }) {
            failures.append("a month row reached past today")
        }
        return failures
    }

    private static func weekAcrossMonths() -> [String] {
        // Record from 1 September, today Tuesday 6 October. The week of
        // Mon 28 Sep – Sun 4 Oct straddles the boundary.
        let days = [row(10, 5, focused: 600, sessions: 1), row(10, 2, focused: 1_200, sessions: 1),
                    row(9, 29, focused: 1_800, sessions: 1), row(9, 1, focused: 300, sessions: 1)]
        let today = date(10, 6)
        let top = HistoryTreeBuilder.top(days: days, today: today, calendar: calendar)
        var failures: [String] = []
        guard top.place?.level == .year else { return ["two months did not open on the year"] }
        let months = HistoryTreeBuilder.rows(under: nil, top: top, days: days, calendar: calendar)
        guard months.count == 2 else { return ["expected October and September, got \(names(months))"] }
        let october = HistoryTreeBuilder.rows(under: months[0].place, top: top, days: days, calendar: calendar)
        let septemberWeeks = HistoryTreeBuilder.rows(under: months[1].place, top: top, days: days, calendar: calendar)
        if names(october) != ["week 5/10–6/10", "week 1/10–4/10"] { failures.append("October's weeks read \(names(october))") }
        if names(septemberWeeks).first != "week 28/9–30/9" { failures.append("September's newest week read \(names(septemberWeeks).first ?? "nothing")") }
        if october.map(\.focused).reduce(0, +) != months[0].focused { failures.append("October's weeks do not sum to October") }
        if septemberWeeks.map(\.focused).reduce(0, +) != months[1].focused { failures.append("September's weeks do not sum to September") }
        // The straddling week opened under October shows only October's days.
        let octoberPart = HistoryTreeBuilder.rows(under: october[1].place, top: top, days: days, calendar: calendar)
        if octoberPart.count != 4 || octoberPart.last?.place.start != date(10, 1) {
            failures.append("the straddling week under October opened to \(names(octoberPart))")
        }
        return failures
    }

    // MARK: - Dots

    private static func dots() -> [String] {
        let top = HistoryTreeBuilder.top(days: september, today: today, calendar: calendar)
        let weeks = HistoryTreeBuilder.rows(under: nil, top: top, days: september, calendar: calendar)
        guard weeks.count == 3 else { return ["expected three weeks"] }
        var failures: [String] = []
        if weeks[0].mainWorkType != .deepWork { failures.append("this week's category was \(String(describing: weeks[0].mainWorkType)), not Deep work") }
        let days = HistoryTreeBuilder.rows(under: weeks[2].place, top: top, days: september, calendar: calendar)
        let byDay = Dictionary(uniqueKeysWithValues: days.map { ($0.place.start, $0) })
        if byDay[date(9, 19)]?.mainWorkType != nil || byDay[date(9, 19)]?.isEmpty != false || byDay[date(9, 19)]?.tracked != 600 {
            failures.append("19 Sep, at the Mac with no session, did not read as app use only")
        }
        if byDay[date(9, 18)]?.isEmpty != true { failures.append("18 Sep, with nothing, did not read as empty") }
        if byDay[date(9, 17)]?.mainWorkType != .learning { failures.append("17 Sep did not carry Learning") }
        let breakOnly = row(9, 25, types: [.breakTime: 0])
        let withBreak = HistoryTreeBuilder.rows(under: weeks[1].place, top: top, days: september + [breakOnly], calendar: calendar)
        if withBreak.first(where: { $0.place.start == date(9, 25) })?.isEmpty != false {
            failures.append("a day holding only a recorded break read as empty")
        }
        return failures
    }

    // MARK: - Time passing

    private static func dayRollover() -> [String] {
        var failures: [String] = []
        let before = HistoryTreeBuilder.top(days: september, today: today, calendar: calendar)
        let thisWeek = HistoryTreeBuilder.rows(under: nil, top: before, days: september, calendar: calendar)[0]
        let daysBefore = HistoryTreeBuilder.rows(under: thisWeek.place, top: before, days: september, calendar: calendar)
        if daysBefore.first?.place.start != today { failures.append("today had no row before midnight") }
        // Wednesday 30 September: today's row appears, the 29th stays.
        let wednesday = date(9, 30)
        let after = HistoryTreeBuilder.top(days: september, today: wednesday, calendar: calendar)
        let week = HistoryTreeBuilder.rows(under: nil, top: after, days: september, calendar: calendar)[0]
        let daysAfter = HistoryTreeBuilder.rows(under: week.place, top: after, days: september, calendar: calendar)
        if daysAfter.map(\.place.start).prefix(2) != [wednesday, today] { failures.append("midnight did not add the 30th above the 29th") }
        // Monday 5 October: a new week and a new month appear; the top steps up to the year.
        let monday = date(10, 5)
        let mondayTop = HistoryTreeBuilder.top(days: september, today: monday, calendar: calendar)
        if mondayTop.place?.level != .year { failures.append("October did not step the top up to the year") }
        let months = HistoryTreeBuilder.rows(under: nil, top: mondayTop, days: september, calendar: calendar)
        let octoberWeeks = HistoryTreeBuilder.rows(under: months[0].place, top: mondayTop, days: september, calendar: calendar)
        if names(octoberWeeks) != ["week 5/10–5/10", "week 1/10–4/10"] { failures.append("Monday's October read \(names(octoberWeeks))") }
        return failures
    }

    private static func pathToToday() -> [String] {
        var failures: [String] = []
        let month = HistoryTreeBuilder.top(days: september, today: today, calendar: calendar)
        let monthPath = HistoryTreeBuilder.pathToToday(top: month, calendar: calendar)
        if monthPath.map(\.level) != [.week] || monthPath.first?.span.start != date(9, 28) {
            failures.append("a month top opened to \(monthPath.map(\.level)), not this week")
        }
        let record = HistoryTreeBuilder.top(days: september + [row(7, 3, year: 2025, focused: 60, sessions: 1)], today: today, calendar: calendar)
        let recordPath = HistoryTreeBuilder.pathToToday(top: record, calendar: calendar)
        if recordPath.map(\.level) != [.year, .month, .week] { failures.append("the record opened to \(recordPath.map(\.level))") }
        if recordPath[0].span.start != date(1, 1) || recordPath[1].span.start != date(9, 1) || recordPath[2].span.start != date(9, 28) {
            failures.append("the record's path did not land on 2026 › September › this week")
        }
        let week = HistoryTreeBuilder.top(days: [row(9, 28, focused: 60, sessions: 1)], today: today, calendar: calendar)
        if !HistoryTreeBuilder.pathToToday(top: week, calendar: calendar).isEmpty { failures.append("a week top opened something") }
        return failures
    }

    private static func pathToDay() -> [String] {
        let record = HistoryTreeBuilder.top(days: september + [row(7, 3, year: 2025, focused: 60, sessions: 1)], today: today, calendar: calendar)
        let path = HistoryTreeBuilder.path(to: date(9, 17), top: record, calendar: calendar)
        var failures: [String] = []
        if path.map(\.level) != [.year, .month, .week, .day] { failures.append("the path to a day read \(path.map(\.level))") }
        // The record began in 2025, so this week is whole: Monday the 14th.
        if path.count == 4, path[2].span.start != date(9, 14) || path[3].span.start != date(9, 17) {
            failures.append("the path's week or day landed wrong: \(path.map(\.span.start))")
        }
        // A record from the 17th clips the week place to the 17th, as its row is drawn.
        let monthTop = HistoryTreeBuilder.top(days: september, today: today, calendar: calendar)
        let clipped = HistoryTreeBuilder.path(to: date(9, 17), top: monthTop, calendar: calendar)
        if clipped.map(\.level) != [.week, .day] || clipped.first?.span.start != date(9, 17) {
            failures.append("a month top's path to the first day read \(clipped.map(\.span.start))")
        }
        // Each place is the row the tree would draw, so toggling by equality works.
        let months = HistoryTreeBuilder.rows(under: path[0], top: record, days: september, calendar: calendar)
        if !months.contains(where: { $0.place == path[1] }) { failures.append("the path's month is not a drawn row") }
        return failures
    }

    private static func daylightSaving() -> [String] {
        // Sydney moves its clocks forward at 2 am on Sunday 4 October 2026.
        let days = [row(10, 5, focused: 600, sessions: 1), row(10, 3, focused: 600, sessions: 1), row(9, 1, focused: 60, sessions: 1)]
        let today = date(10, 6)
        let top = HistoryTreeBuilder.top(days: days, today: today, calendar: calendar)
        let months = HistoryTreeBuilder.rows(under: nil, top: top, days: days, calendar: calendar)
        guard let october = months.first else { return ["no October"] }
        let weeks = HistoryTreeBuilder.rows(under: october.place, top: top, days: days, calendar: calendar)
        guard let straddle = weeks.last else { return ["no straddling week"] }
        let octoberDays = HistoryTreeBuilder.rows(under: straddle.place, top: top, days: days, calendar: calendar)
        var failures: [String] = []
        if octoberDays.count != 4 { failures.append("1 – 4 October drew \(octoberDays.count) days") }
        if Set(octoberDays.map(\.place.start)).count != 4 { failures.append("a daylight-saving day was doubled") }
        if octoberDays.first(where: { $0.place.start == date(10, 3) })?.focused != 600 { failures.append("3 October lost its focus across the clock change") }
        return failures
    }

    private static func summaryBest() -> [String] {
        var failures: [String] = []
        let days = september + [row(6, 3, focused: 7_200, sessions: 1, types: [.deepWork: 7_200])]
        let year = HistoryTreeBuilder.top(days: days, today: today, calendar: calendar)
        let yearSummary = HistoryTreeBuilder.summary(top: year, days: days, calendar: calendar)
        if yearSummary.focused != 13_500 || yearSummary.focusedDays != 4 || yearSummary.best?.place.level != .month
            || yearSummary.best?.place.start != date(6, 3) {
            failures.append("the year's summary read \(yearSummary.focused)s on \(yearSummary.focusedDays) days, best \(String(describing: yearSummary.best))")
        }
        let month = HistoryTreeBuilder.top(days: september, today: today, calendar: calendar)
        let monthSummary = HistoryTreeBuilder.summary(top: month, days: september, calendar: calendar)
        if monthSummary.best?.place.level != .day || monthSummary.best?.place.start != date(9, 28) {
            failures.append("the month's best day was \(String(describing: monthSummary.best))")
        }
        return failures
    }
}
