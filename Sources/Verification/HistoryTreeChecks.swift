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
        ("The tree's summary names the best month for a year and the best day for a month", summaryBest),
        ("A ticking clock does not rebuild the tree, and today's live figures reach its rows", treeIsCached),
        ("Opening a row folds its sibling; folding a row folds everything under it; an empty row cannot open", openAndFold),
        ("Arrow keys walk the visible rows in reading order, Return toggles, left and right fold and open", keyboardWalk),
        ("Rows say their period, figures and state once, in words for VoiceOver", rowWording),
        ("The headline names the top period and its totals", headlineWording),
        ("The rail follows the deepest open row and the picked session, and drops a session that is gone", railFollowsDeepestOpen),
        ("A period's reading covers exactly its span: one week, one month, a year's months, the record's months", periodReading),
        ("The dashboard has no step or calendar, and History never moves its day", dashboardIsToday),
        ("Open rows survive midnight and the top stepping up", openSurvivesMidnight),
        ("A zone whose clocks change at midnight keeps every day once", daylightSavingAtMidnight),
        ("Today's live figures patch the cached summary without a walk", summaryPatching),
        ("A day's rail in History reads exactly what the dashboard reads for that day", railDayMatchesDashboard),
        ("An app-use checkpoint repairs the days it touched in place; a session change rebuilds the index", checkpointPatchesIndex),
        ("Opening History again on unchanged evidence rebuilds neither the index nor Insights", reopenRebuildsNothing),
        ("Insights are built only while this month's rail shows them", insightsOnlyForThisMonth),
        ("The find bar's app list is sorted once per archive state, and learns a new app", appListIsCached)
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

    // MARK: - Store

    private static func treeIsCached() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .running, accurateUsage: true)
            defer { FixtureFactory.cleanUp() }
            store.refreshReview()
            var failures: [String] = []
            let calendar = SessionStore.historyCalendar
            let top = store.historyTop()
            _ = store.historyRows(under: nil)
            let path = HistoryTreeBuilder.pathToToday(top: top, calendar: calendar)
            for place in path { _ = store.historyRows(under: place) }
            let built = store.historyTreeComputeCount
            for _ in 0..<5 {
                _ = store.historyRows(under: nil)
                for place in path { _ = store.historyRows(under: place) }
            }
            if store.historyTreeComputeCount != built {
                failures.append("re-reading the tree rebuilt it \(store.historyTreeComputeCount - built) times")
            }
            // The running session's live focus reaches today's row and every
            // row above it, without a rebuild.
            let today = calendar.startOfDay(for: store.now())
            let live = store.historyDays.first { calendar.isDate($0.date, inSameDayAs: today) }
            guard let liveFocus = live?.focused, liveFocus > 0 else { return ["the running fixture has no live focus today"] }
            var parent: HistoryPlace? = nil
            for place in path {
                let rows = store.historyRows(under: parent)
                guard let row = rows.first(where: { $0.place == place }) else { failures.append("\(place.level) row missing"); break }
                if row.focused < liveFocus { failures.append("the \(place.level) row shows \(row.focused)s, less than today's \(liveFocus)s") }
                parent = place
            }
            let days = store.historyRows(under: path.last)
            if days.first(where: { $0.place.span.contains(today) })?.focused != liveFocus {
                failures.append("today's row does not carry the live figure")
            }
            if store.historyTreeComputeCount != built { failures.append("reading live rows rebuilt the tree") }
            // The headline's summary is cached the same way, and carries the live figure.
            let summary = store.historySummary()
            let weekSummary = store.historySummary(for: path.last)
            let afterSummary = store.historyTreeComputeCount
            for _ in 0..<5 { _ = store.historySummary(); _ = store.historySummary(for: path.last) }
            if store.historyTreeComputeCount != afterSummary { failures.append("re-reading the summary walked the record again") }
            if summary.focused < liveFocus || weekSummary.focused < liveFocus { failures.append("the summary does not carry today's live figure") }
            return failures
        }
    }

    // MARK: - Model

    private static func openAndFold() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.insightsStore(withEvidence: true)
            defer { FixtureFactory.cleanUp() }
            store.refreshReview()
            let navigation = MainWindowModel(store: store)
            navigation.open(tab: .review)
            var failures: [String] = []
            let top = store.historyTop()
            let expected = HistoryTreeBuilder.pathToToday(top: top, calendar: SessionStore.historyCalendar)
            if navigation.historyOpen != expected { failures.append("History did not open to this week: \(navigation.historyOpen.map(\.level))") }
            let roots = store.historyRows(under: nil).filter { !$0.isEmpty }
            guard roots.count >= 2 else { return ["the dense fixture has fewer than two root rows with evidence"] }
            let newest = roots[0], older = roots[1]
            navigation.toggleHistory(older.place)
            if navigation.historyOpen != [older.place] { failures.append("opening a sibling did not fold the open root: \(navigation.historyOpen.map(\.level))") }
            navigation.toggleHistory(newest.place)
            let children = store.historyRows(under: newest.place)
            if let child = children.first(where: { !$0.isEmpty }) {
                navigation.toggleHistory(child.place)
                if navigation.historyOpen != [newest.place, child.place] { failures.append("a child did not open under its parent") }
                navigation.toggleHistory(newest.place)
                if !navigation.historyOpen.isEmpty { failures.append("folding the root left \(navigation.historyOpen.count) open") }
            }
            navigation.toggleHistory(newest.place)
            if let empty = children.first(where: \.isEmpty) {
                navigation.toggleHistory(empty.place)
                if navigation.historyOpen.contains(empty.place) { failures.append("an empty row opened") }
            }
            // A child of a folded parent cannot be opened out of order.
            navigation.foldDeepestHistory()
            if let child = children.first(where: { !$0.isEmpty }) {
                navigation.toggleHistory(child.place)
                if navigation.historyOpen.contains(child.place) { failures.append("a child opened under a folded parent") }
            }
            // The keyboard says an open row is expanded, and a place that is no
            // longer in the record is spoken as nothing rather than crashing.
            navigation.toggleHistory(newest.place)
            if HistoryTree.spoken(.row(newest.place), store: store, open: navigation.historyOpen)?.hasSuffix("expanded") != true {
                failures.append("an open row was not announced as expanded")
            }
            let outside = HistoryPlace(level: .day, span: DateInterval(start: Date(timeIntervalSince1970: 0), duration: 86_400))
            if HistoryTree.spoken(.row(outside), store: store, open: navigation.historyOpen) != nil {
                failures.append("a place outside the record was spoken")
            }
            navigation.toggleHistory(newest.place)
            // Escape folds one level at a time.
            navigation.toggleHistory(newest.place)
            if let child = children.first(where: { !$0.isEmpty }) { navigation.toggleHistory(child.place) }
            let depth = navigation.historyOpen.count
            navigation.foldDeepestHistory()
            if navigation.historyOpen.count != depth - 1 { failures.append("Escape folded \(depth - navigation.historyOpen.count) levels") }
            return failures
        }
    }

    private static func keyboardWalk() -> [String] {
        let top = HistoryTreeBuilder.top(days: september, today: today, calendar: calendar)
        let weeks = HistoryTreeBuilder.rows(under: nil, top: top, days: september, calendar: calendar)
        let thisWeek = weeks[0]
        let days = HistoryTreeBuilder.rows(under: thisWeek.place, top: top, days: september, calendar: calendar)
        let a = UUID(), b = UUID()
        let rows: (HistoryPlace?) -> [HistoryRow] = { parent in
            HistoryTreeBuilder.rows(under: parent, top: top, days: september, calendar: calendar)
        }
        let threads: (Date) -> [UUID] = { $0 == date(9, 28) ? [a, b] : [] }
        // This week open, and Monday 28 open: its two sessions are stops.
        let open = [thisWeek.place, days[1].place]
        let visible = HistoryTreeBuilder.visible(open: open, rows: rows, threads: threads)
        let expected: [HistoryFocus] = [
            .row(thisWeek.place), .row(days[0].place), .row(days[1].place),
            .session(thread: a, day: date(9, 28)), .session(thread: b, day: date(9, 28)),
            .row(weeks[1].place), .row(weeks[2].place)
        ]
        return visible == expected ? [] : ["visible rows read \(visible), expected \(expected)"]
    }

    // MARK: - Wording

    private static func rowWording() -> [String] {
        let top = HistoryTreeBuilder.top(days: september + [row(7, 3, year: 2025, focused: 60, sessions: 1)], today: today, calendar: calendar)
        let years = HistoryTreeBuilder.rows(under: nil, top: top, days: september, calendar: calendar)
        var failures: [String] = []
        guard let year = years.first else { return ["no year row"] }
        if HistoryRowText.title(year.place, today: today, calendar: calendar) != "2026" { failures.append("the year row was titled \(HistoryRowText.title(year.place, today: today, calendar: calendar))") }
        let months = HistoryTreeBuilder.rows(under: year.place, top: top, days: september, calendar: calendar)
        guard let sep = months.first else { return ["no September"] }
        if HistoryRowText.title(sep.place, today: today, calendar: calendar) != "September" { failures.append("September was titled \(HistoryRowText.title(sep.place, today: today, calendar: calendar))") }
        if HistoryRowText.facts(sep, today: today) != "\(Tokens.duration(6_300)) · 3 days" { failures.append("September's facts read \(HistoryRowText.facts(sep, today: today))") }
        let weeks = HistoryTreeBuilder.rows(under: sep.place, top: top, days: september, calendar: calendar)
        if HistoryRowText.title(weeks[2].place, today: today, calendar: calendar) != "14 – 20 Sep" { failures.append("the third week was titled \(HistoryRowText.title(weeks[2].place, today: today, calendar: calendar))") }
        if HistoryRowText.title(weeks[0].place, today: today, calendar: calendar) != "28 – 29 Sep" { failures.append("this week was titled \(HistoryRowText.title(weeks[0].place, today: today, calendar: calendar))") }
        let monthTop = HistoryTreeBuilder.top(days: september, today: today, calendar: calendar)
        let clippedWeeks = HistoryTreeBuilder.rows(under: nil, top: monthTop, days: september, calendar: calendar)
        if HistoryRowText.title(clippedWeeks[2].place, today: today, calendar: calendar) != "17 – 20 Sep" { failures.append("the first recorded week was titled \(HistoryRowText.title(clippedWeeks[2].place, today: today, calendar: calendar))") }
        let days = HistoryTreeBuilder.rows(under: weeks[0].place, top: top, days: september, calendar: calendar)
        if HistoryRowText.title(days[0].place, today: today, calendar: calendar) != "Today" { failures.append("today was titled \(HistoryRowText.title(days[0].place, today: today, calendar: calendar))") }
        if HistoryRowText.title(days[1].place, today: today, calendar: calendar) != "Mon 28 Sep" { failures.append("Monday was titled \(HistoryRowText.title(days[1].place, today: today, calendar: calendar))") }
        if HistoryRowText.facts(days[1], today: today) != "\(Tokens.duration(3_600)) · 2 sessions" { failures.append("Monday's facts read \(HistoryRowText.facts(days[1], today: today))") }
        if HistoryRowText.facts(days[0], today: today) != "nothing recorded yet today" { failures.append("an empty today read \(HistoryRowText.facts(days[0], today: today))") }
        let older = HistoryTreeBuilder.rows(under: weeks[2].place, top: top, days: september, calendar: calendar)
        let empty = older.first { $0.place.start == date(9, 18) }!
        let appOnly = older.first { $0.place.start == date(9, 19) }!
        if HistoryRowText.facts(empty, today: today) != "nothing recorded" { failures.append("an empty day read \(HistoryRowText.facts(empty, today: today))") }
        if HistoryRowText.facts(appOnly, today: today) != "Recorded app use only · \(Tokens.duration(600))" { failures.append("an app-use day read \(HistoryRowText.facts(appOnly, today: today))") }
        let spoken = HistoryRowText.spoken(sep, today: today, isOpen: false, depth: 1, calendar: calendar)
        let wanted = "September 2026, \(Tokens.spent(6_300)) across 3 days, month, level 2, collapsed"
        if spoken != wanted { failures.append("September was spoken as \"\(spoken)\", wanted \"\(wanted)\"") }
        if spoken.contains("h ") { failures.append("a compact duration reached VoiceOver") }
        return failures
    }

    private static func headlineWording() -> [String] {
        var failures: [String] = []
        let month = HistoryTreeBuilder.top(days: september, today: today, calendar: calendar)
        let monthLine = HistoryRowText.headline(top: month, summary: HistoryTreeBuilder.summary(top: month, days: september, calendar: calendar), calendar: calendar)
        if monthLine.eyebrow != "September 2026" || monthLine.sentence != "You focused \(Tokens.duration(6_300)) across 3 days." {
            failures.append("the month headline read \(monthLine.eyebrow) / \(monthLine.sentence)")
        }
        if !monthLine.facts.contains("best day Mon 28 Sep · \(Tokens.duration(3_600))") { failures.append("the month's facts were \(monthLine.facts)") }
        let recordDays = september + [row(7, 3, year: 2025, focused: 60, sessions: 1)]
        let record = HistoryTreeBuilder.top(days: recordDays, today: today, calendar: calendar)
        let recordLine = HistoryRowText.headline(top: record, summary: HistoryTreeBuilder.summary(top: record, days: recordDays, calendar: calendar), calendar: calendar)
        if recordLine.eyebrow != "On record since 3 July 2025" { failures.append("the record's eyebrow read \(recordLine.eyebrow)") }
        if !recordLine.facts.contains("best month September 2026 · \(Tokens.duration(6_300))") { failures.append("the record's facts were \(recordLine.facts)") }
        let oneDay = HistoryTreeBuilder.top(days: [row(9, 28, focused: 60, sessions: 1)], today: today, calendar: calendar)
        let weekLine = HistoryRowText.headline(top: oneDay, summary: HistoryTreeBuilder.summary(top: oneDay, days: [row(9, 28, focused: 60, sessions: 1)], calendar: calendar), calendar: calendar)
        if weekLine.sentence != "You focused \(Tokens.duration(60)) across 1 day." { failures.append("one focused day read \(weekLine.sentence)") }
        // A record of one day, today: its week is that one day, and says so.
        let oneToday = HistoryTreeBuilder.top(days: [row(9, 29, focused: 60, sessions: 1)], today: today, calendar: calendar)
        let todayLine = HistoryRowText.headline(top: oneToday, summary: HistoryTreeBuilder.summary(top: oneToday, days: [row(9, 29, focused: 60, sessions: 1)], calendar: calendar), calendar: calendar)
        if todayLine.eyebrow != "Tuesday 29 September" { failures.append("a one-day record's eyebrow read \(todayLine.eyebrow)") }
        return failures
    }

    // MARK: - Rail

    private static func railFollowsDeepestOpen() -> [String] {
        let top = HistoryTreeBuilder.top(days: september, today: today, calendar: calendar)
        let week = HistoryTreeBuilder.rows(under: nil, top: top, days: september, calendar: calendar)[0]
        let day = HistoryTreeBuilder.rows(under: week.place, top: top, days: september, calendar: calendar)[1]
        var failures: [String] = []
        if HistoryRailScope.resolve(open: [], session: nil, pick: nil) != .period(nil) { failures.append("nothing open did not describe the top") }
        if HistoryRailScope.resolve(open: [week.place], session: nil, pick: nil) != .period(week.place) { failures.append("an open week was not described") }
        if HistoryRailScope.resolve(open: [week.place, day.place], session: nil, pick: nil) != .day(day.place.start) { failures.append("an open day was not described") }
        let pick = HistorySessionPick(thread: UUID(), day: day.place.start)
        if HistoryRailScope.resolve(open: [week.place, day.place], session: nil, pick: pick) != .day(day.place.start) {
            failures.append("a picked session that is gone did not fall back to its day")
        }
        return failures
    }

    private static func periodReading() -> [String] {
        var failures: [String] = []
        let top = HistoryTreeBuilder.top(days: september + [row(7, 3, year: 2025, focused: 60, sessions: 1)], today: today, calendar: calendar)
        let record = HistoryPeriodRail.reading(for: nil, top: top, calendar: calendar)
        if record.scope != .month || record.limit != 15 || !calendar.isDate(record.anchor, inSameDayAs: today) {
            failures.append("the record read \(record.scope) × \(record.limit) anchored \(record.anchor)")
        }
        let years = HistoryTreeBuilder.rows(under: nil, top: top, days: september, calendar: calendar)
        let thisYear = HistoryPeriodRail.reading(for: years[0].place, top: top, calendar: calendar)
        if thisYear.scope != .month || thisYear.limit != 9 { failures.append("2026 read \(thisYear.scope) × \(thisYear.limit)") }
        let lastYear = HistoryPeriodRail.reading(for: years[1].place, top: top, calendar: calendar)
        if lastYear.limit != 6 || !calendar.isDate(lastYear.anchor, inSameDayAs: date(12, 31, year: 2025)) {
            failures.append("2025 read × \(lastYear.limit) anchored \(lastYear.anchor)")
        }
        let months = HistoryTreeBuilder.rows(under: years[0].place, top: top, days: september, calendar: calendar)
        let sep = HistoryPeriodRail.reading(for: months[0].place, top: top, calendar: calendar)
        if sep.scope != .month || sep.limit != 1 { failures.append("September read \(sep.scope) × \(sep.limit)") }
        let weeks = HistoryTreeBuilder.rows(under: months[0].place, top: top, days: september, calendar: calendar)
        // A week reads exactly its days: this week is Monday 28 to today, two days.
        let week = HistoryPeriodRail.reading(for: weeks[0].place, top: top, calendar: calendar)
        if week.scope != .day || week.limit != 2 || !calendar.isDate(week.anchor, inSameDayAs: today) {
            failures.append("this week read \(week.scope) × \(week.limit) anchored \(week.anchor)")
        }
        return failures
    }

    // MARK: - Dashboard

    private static func dashboardIsToday() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.insightsStore(withEvidence: true)
            defer { FixtureFactory.cleanUp() }
            store.refreshReview()
            let navigation = MainWindowModel(store: store)
            navigation.open(tab: .review)
            var failures: [String] = []
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: store.now()))!
            navigation.openHistory(day: yesterday)
            if !store.isToday { failures.append("opening a day in History moved the dashboard's day") }
            if navigation.workspace != .history { failures.append("opening a day left History") }
            navigation.returnToStory()
            if !store.isToday { failures.append("returning to the story did not show today") }
            let frame = StoryWorkspaceChecks.renderFrame(
                StoryChromeBar(store: store, navigation: navigation),
                width: 1_160, height: 60)
            if !frame.evidence.contains(.storyChromeControls) {
                failures.append("the story chrome did not draw the session controls: \(frame.evidence.map(\.rawValue).sorted())")
            }
            return failures
        }
    }

    // MARK: - Review fixes

    private static func openSurvivesMidnight() -> [String] {
        var failures: [String] = []
        let tuesday = HistoryTreeBuilder.top(days: september, today: today, calendar: calendar)
        let week = HistoryTreeBuilder.rows(under: nil, top: tuesday, days: september, calendar: calendar)[0]
        let day = HistoryTreeBuilder.rows(under: week.place, top: tuesday, days: september, calendar: calendar)[0]
        let open = [week.place, day.place]
        // Wednesday: the week row now reaches the 30th; the open week must be that row.
        let wednesday = HistoryTreeBuilder.top(days: september, today: date(9, 30), calendar: calendar)
        let kept = HistoryTreeBuilder.reconcile(open: open, top: wednesday, calendar: calendar)
        let weekRow = HistoryTreeBuilder.rows(under: nil, top: wednesday, days: september, calendar: calendar)[0]
        if kept.count != 2 || kept[0] != weekRow.place || kept[1] != day.place {
            failures.append("after midnight the open path read \(kept.map { "\($0.level) \($0.span)" })")
        }
        // Monday 5 October: the top steps up to the year, so the path gains September.
        let monday = HistoryTreeBuilder.top(days: september, today: date(10, 5), calendar: calendar)
        let stepped = HistoryTreeBuilder.reconcile(open: open, top: monday, calendar: calendar)
        if stepped.map(\.level) != [.month, .week, .day] { failures.append("after the top stepped up the path read \(stepped.map(\.level))") }
        let months = HistoryTreeBuilder.rows(under: nil, top: monday, days: september, calendar: calendar)
        if stepped.first.map({ place in months.contains { $0.place == place } }) != true { failures.append("the gained month is not a drawn row") }
        // A day that is no longer in the record folds away.
        let later = HistoryTreeBuilder.top(days: [row(10, 2, focused: 60, sessions: 1)], today: date(10, 5), calendar: calendar)
        if !HistoryTreeBuilder.reconcile(open: open, top: later, calendar: calendar).isEmpty { failures.append("a day outside the record stayed open") }
        if !HistoryTreeBuilder.reconcile(open: [], top: wednesday, calendar: calendar).isEmpty { failures.append("nothing open became something") }
        return failures
    }

    private static func daylightSavingAtMidnight() -> [String] {
        // Santiago moves its clocks forward at midnight on Sunday 6 September 2026:
        // that day begins at 01:00. Every day must still be walked once.
        var base = Calendar(identifier: .gregorian)
        base.timeZone = TimeZone(identifier: "America/Santiago")!
        let santiago = HistoryTreeBuilder.calendar(base)
        func local(_ month: Int, _ day: Int) -> Date { santiago.date(from: DateComponents(year: 2026, month: month, day: day))! }
        let days = [HistoryDay(date: local(9, 20), tracked: 0, focused: 600, sessions: 1, appBundleIDs: [], workTypes: [.deepWork]),
                    HistoryDay(date: local(9, 6), tracked: 0, focused: 300, sessions: 1, appBundleIDs: [], workTypes: [.deepWork]),
                    HistoryDay(date: local(9, 3), tracked: 0, focused: 900, sessions: 1, appBundleIDs: [], workTypes: [.deepWork])]
        let today = local(9, 25)
        let top = HistoryTreeBuilder.top(days: days, today: today, calendar: santiago)
        var failures: [String] = []
        let weeks = HistoryTreeBuilder.rows(under: nil, top: top, days: days, calendar: santiago)
        let everyDay = weeks.flatMap { HistoryTreeBuilder.rows(under: $0.place, top: top, days: days, calendar: santiago) }
        if everyDay.count != 23 { failures.append("3 – 25 September drew \(everyDay.count) days, not 23") }
        if Set(everyDay.map(\.place.start)).count != everyDay.count { failures.append("a day was drawn twice") }
        if everyDay.map(\.focused).reduce(0, +) != 1_800 { failures.append("a day's focus was lost across the clock change") }
        if let sunday = everyDay.first(where: { santiago.component(.day, from: $0.place.start) == 6 }), sunday.focused != 300 {
            failures.append("the clock-change day lost its focus")
        }
        let summary = HistoryTreeBuilder.summary(top: top, days: days, calendar: santiago)
        if summary.focused != 1_800 || summary.focusedDays != 3 { failures.append("the summary read \(summary.focused)s on \(summary.focusedDays) days") }
        return failures
    }

    private static func summaryPatching() -> [String] {
        let top = HistoryTreeBuilder.top(days: september, today: today, calendar: calendar)
        let byDate = HistoryTreeBuilder.index(september, calendar: calendar)
        let cached = HistoryTreeBuilder.summary(top: top, byDate: byDate, calendar: calendar)
        var failures: [String] = []
        let small = row(9, 29, focused: 1_200, tracked: 300, sessions: 1, types: [.deepWork: 1_200])
        let patched = HistoryTreeBuilder.patching(cached, top: top, byDate: byDate, cachedToday: nil, live: small, calendar: calendar)
        if patched.focused != 7_500 || patched.tracked != 7_800 || patched.focusedDays != 4 || patched.sessions != 5 {
            failures.append("a live today read \(patched.focused)s, \(patched.tracked)s app use, \(patched.focusedDays) days, \(patched.sessions) sessions")
        }
        if patched.best?.place.start != date(9, 28) { failures.append("a small live day displaced the best day") }
        let big = row(9, 29, focused: 5_000, sessions: 2, types: [.deepWork: 5_000])
        let overtaken = HistoryTreeBuilder.patching(patched, top: top, byDate: byDate, cachedToday: small, live: big, calendar: calendar)
        if overtaken.focused != 11_300 || overtaken.tracked != 7_500 || overtaken.best?.place.start != date(9, 29) || overtaken.best?.focused != 5_000 {
            failures.append("a bigger live day read \(overtaken.focused)s, best \(String(describing: overtaken.best))")
        }
        if HistoryTreeBuilder.patching(cached, top: top, byDate: byDate, cachedToday: nil, live: nil, calendar: calendar) != cached {
            failures.append("no live day changed the summary")
        }
        return failures
    }

    // MARK: - The day, as the dashboard draws it

    private static func railDayMatchesDashboard() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.insightsStore(withEvidence: true)
            defer { FixtureFactory.cleanUp() }
            store.setDashboardVisible(true)
            let calendar = Calendar.current
            let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: store.now()))!
            // The dashboard, stepped to yesterday, is the reference.
            store.selectDay(offset: 1)
            var failures: [String] = []
            let reading = store.storyRailDay(on: yesterday)
            if reading.apps != store.rankedApps { failures.append("History's apps for yesterday differ from the dashboard's") }
            if reading.rhythm != store.rhythm || reading.rhythmPeak != store.rhythmPeak {
                failures.append("History's rhythm for yesterday differs from the dashboard's")
            }
            if reading.goal != store.selectedDayGoal { failures.append("History's goal for yesterday differs from the dashboard's") }
            if reading.apps.isEmpty { failures.append("the fixture's yesterday has no apps, so nothing was compared") }
            if let app = reading.apps.first,
               store.storyAppEvidence(for: app.bundleID, period: nil, day: yesterday)
                != store.storyAppEvidence(for: app.bundleID, period: nil) {
                failures.append("an app's detail for yesterday differs from the dashboard's")
            }
            store.selectDay(offset: 0)
            // Read while the dashboard shows today: History still gets yesterday.
            if store.storyRailDay(on: yesterday).apps != reading.apps {
                failures.append("History's reading for yesterday followed the dashboard's day")
            }
            return failures
        }
    }

    // MARK: - Cost

    /// Every app switch checkpoints app use. With History showing, that used
    /// to walk the whole uncapped archive again (a third of a second at two
    /// months of record); now the archive names the days the checkpoint
    /// touched and only those are rebuilt. A session change still rebuilds.
    private static func checkpointPatchesIndex() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            defer { FixtureFactory.cleanUp() }
            guard let usage = store.usage else { return ["the history fixture attaches no usage archive"] }
            var failures: [String] = []
            let calendar = Calendar.current
            store.setReviewVisible(true)
            store.refreshReview()
            let generation = store.historyIndexGeneration
            // Three days back: not today, so the live tail alone would not cover it.
            let day = calendar.date(byAdding: .day, value: -3, to: calendar.startOfDay(for: store.now()))!
            let start = day.addingTimeInterval(9 * 3_600)
            let before = store.historyDays.first { calendar.isDate($0.date, inSameDayAs: day) }?.tracked ?? 0
            // As the tracker does it: the checkpoint lands, the ticker's
            // figures are read, then the one refresh is consumed.
            store.withRefreshTransaction {
                usage.checkpoint(AppUsageSession(bundleID: "fc.check.newcomer", appName: "Newcomer",
                                                 start: start, end: start.addingTimeInterval(1_800)))
                store.updateTimeDrivenFigures()
            }
            if store.historyIndexGeneration != generation {
                failures.append("an app-use checkpoint rebuilt the whole index")
            }
            let after = store.historyDays.first { calendar.isDate($0.date, inSameDayAs: day) }?.tracked ?? 0
            if after != before + 1_800 {
                failures.append("the checkpointed day's app use read \(after)s, not \(before + 1_800)s")
            }
            if store.historyAppName(for: "fc.check.newcomer") != "Newcomer" {
                failures.append("the find bar does not know the app the checkpoint brought")
            }
            if store.reviewRefreshPending || store.reviewLiveTailRefreshPending {
                failures.append("the checkpoint left a refresh pending after it was applied")
            }
            // A session is any day's evidence: the index is rebuilt.
            store.engine.archive.append(SessionRecord(name: "Late entry", workType: .deepWork,
                                                      start: start.addingTimeInterval(3_600),
                                                      end: start.addingTimeInterval(5_400),
                                                      workSeconds: 1_800))
            store.refresh()
            if store.historyIndexGeneration == generation {
                failures.append("a session change did not rebuild the index")
            }
            return failures
        }
    }

    /// The Insights surfaces (pace, rhythm, quality) appear on this month's
    /// rail alone. History opens on this week, whose rail shows none of
    /// them, yet every app switch rebuilt both surfaces for it.
    private static func insightsOnlyForThisMonth() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            defer { FixtureFactory.cleanUp() }
            guard let usage = store.usage else { return ["the history fixture attaches no usage archive"] }
            var failures: [String] = []
            let calendar = SessionStore.historyCalendar
            store.setReviewVisible(true)
            store.refreshReview()
            let top = store.historyTop()
            let today = calendar.startOfDay(for: store.now())
            let month = HistoryPlace(level: .month, span: HistoryTreeBuilder.period(.month, containing: today, calendar: calendar))
            let week = HistoryPlace(level: .week, span: HistoryTreeBuilder.period(.week, containing: today, calendar: calendar))
            let lastMonth = calendar.date(byAdding: .month, value: -1, to: today)!
            let earlier = HistoryPlace(level: .month, span: HistoryTreeBuilder.period(.month, containing: lastMonth, calendar: calendar))
            if !HistoryPeriodRail.showsThisMonth(place: month, top: top) { failures.append("this month's rail does not claim Insights") }
            if HistoryPeriodRail.showsThisMonth(place: week, top: top) { failures.append("a week's rail claims Insights") }
            if HistoryPeriodRail.showsThisMonth(place: earlier, top: top) { failures.append("an earlier month's rail claims Insights") }
            // Without a claim, app use comes and goes and Insights stay unbuilt.
            store.setInsightsVisible(false)
            let built = store.insightsComputeCount
            let start = today.addingTimeInterval(8 * 3_600)
            usage.checkpoint(AppUsageSession(bundleID: "fc.check.quiet", appName: "Quiet",
                                             start: start, end: start.addingTimeInterval(600)))
            if store.insightsComputeCount != built {
                failures.append("a checkpoint built Insights \(store.insightsComputeCount - built) times for a rail that shows none")
            }
            // The claim consumes what is owed, once.
            store.setInsightsVisible(true)
            if store.insightsComputeCount != built + 1 {
                failures.append("this month's rail got \(store.insightsComputeCount - built) builds, not one")
            }
            return failures
        }
    }

    /// The find bar's app menu is drawn on every render of History, once a
    /// second while anything is live. Its list was gathered and sorted by
    /// localised name each time.
    private static func appListIsCached() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            defer { FixtureFactory.cleanUp() }
            guard let usage = store.usage else { return ["the history fixture attaches no usage archive"] }
            var failures: [String] = []
            store.setReviewVisible(true)
            store.refreshReview()
            let first = store.historyAppBundleIDs
            let built = store.historyAppListComputeCount
            for _ in 0..<5 where store.historyAppBundleIDs != first { failures.append("the app list changed between reads") }
            if store.historyAppListComputeCount != built {
                failures.append("five reads of an unchanged archive sorted the app list \(store.historyAppListComputeCount - built) more times")
            }
            let today = Calendar.current.startOfDay(for: store.now())
            let start = today.addingTimeInterval(8 * 3_600)
            usage.checkpoint(AppUsageSession(bundleID: "fc.check.arrival", appName: "Arrival",
                                             start: start, end: start.addingTimeInterval(600)))
            if !store.historyAppBundleIDs.contains("fc.check.arrival") {
                failures.append("the app list did not learn the app a checkpoint brought")
            }
            return failures
        }
    }

    /// ⌘2 used to rebuild the index and both Insights surfaces every time,
    /// changed or not. The page now takes what the visibility gate owes it.
    private static func reopenRebuildsNothing() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            defer { FixtureFactory.cleanUp() }
            var failures: [String] = []
            let navigation = MainWindowModel(store: store)
            navigation.open(tab: .review)
            if store.historyDays.isEmpty { failures.append("opening History did not build its index") }
            let generation = store.historyIndexGeneration
            let insights = store.insightsComputeCount
            for _ in 0..<3 {
                navigation.returnToStory()
                navigation.open(tab: .review)
            }
            if store.historyIndexGeneration != generation {
                failures.append("reopening History on unchanged evidence rebuilt the index \(store.historyIndexGeneration - generation) times")
            }
            if store.insightsComputeCount != insights {
                failures.append("reopening History built Insights \(store.insightsComputeCount - insights) times")
            }
            return failures
        }
    }
}
