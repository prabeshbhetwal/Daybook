import Foundation

/// The levels History unfolds through. Sessions sit under a day and come
/// from the day's projection, not from this index.
enum HistoryLevel: Int, Comparable, CaseIterable {
    case year = 0, month, week, day

    static func < (lhs: HistoryLevel, rhs: HistoryLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var child: HistoryLevel? { HistoryLevel(rawValue: rawValue + 1) }

    var component: Calendar.Component {
        switch self {
        case .year: return .year
        case .month: return .month
        case .week: return .weekOfYear
        case .day: return .day
        }
    }

    var spokenName: String {
        switch self {
        case .year: return "year"
        case .month: return "month"
        case .week: return "week"
        case .day: return "day"
        }
    }
}

/// One period on the spine: its level and the days it covers, already
/// clipped to its parent and to the record. A week that straddles a month
/// is two places, one under each month, so they never read as the same row.
struct HistoryPlace: Hashable {
    let level: HistoryLevel
    let span: DateInterval

    var start: Date { span.start }
    var id: String {
        "row-\(level.rawValue)-\(Int(span.start.timeIntervalSince1970))-\(Int(span.end.timeIntervalSince1970))"
    }
}

extension DateInterval {
    /// Whether `date` lies in the interval, taking its start but not its end.
    /// `contains` takes both, so a period that ends at today's midnight
    /// (yesterday, last week on a Monday, last month on the 1st) holds today.
    func holds(_ date: Date) -> Bool { start <= date && date < end }
}

/// One thin bar inside a folded row: a month of a year, or a day of a month
/// or week.
struct HistoryBar: Equatable {
    let start: Date
    let focused: TimeInterval
}

/// A row as drawn. Figures cover the place's span and nothing outside it.
struct HistoryRow: Identifiable, Equatable {
    let place: HistoryPlace
    let focused: TimeInterval
    let tracked: TimeInterval
    let focusedDays: Int
    let sessions: Int
    /// The category most of the focus went to; nil without focus.
    let mainWorkType: WorkType?
    /// Anything at all: focus, app use, a session or a recorded break.
    let hasEvidence: Bool
    let bars: [HistoryBar]

    var isEmpty: Bool { !hasEvidence }
    var id: String { place.id }
    /// At the Mac, but no session.
    var isAppUseOnly: Bool { sessions == 0 && focused == 0 && tracked > 0 }
}

/// The top of the tree: the smallest period holding the whole record, or
/// nil for the record itself, whose rows are years.
struct HistoryTop: Equatable {
    let place: HistoryPlace?
    let firstDay: Date
    let today: Date
    /// The days the root rows divide between them: the top period, or the
    /// whole record to the end of today in the calendar the top was built in.
    let span: DateInterval

    init(place: HistoryPlace?, firstDay: Date, today: Date, calendar: Calendar) {
        self.place = place
        self.firstDay = firstDay
        self.today = today
        span = place?.span ?? DateInterval(start: firstDay, end: HistoryTreeBuilder.dayAfter(today, calendar: calendar))
    }

    var rootLevel: HistoryLevel { place?.level.child ?? .year }
}

/// The headline's figures for the top period.
struct HistorySummary: Equatable {
    let focused: TimeInterval
    let tracked: TimeInterval
    let focusedDays: Int
    let sessions: Int
    /// The best month of a year or the record; the best day of a month or week.
    let best: (place: HistoryPlace, focused: TimeInterval)?

    static func == (lhs: HistorySummary, rhs: HistorySummary) -> Bool {
        lhs.focused == rhs.focused && lhs.tracked == rhs.tracked && lhs.focusedDays == rhs.focusedDays
            && lhs.sessions == rhs.sessions && lhs.best?.place == rhs.best?.place && lhs.best?.focused == rhs.best?.focused
    }
}

/// Builds History's rows from the day index. Pure: no store, no clock, so
/// the checks hand it any archive and any today.
enum HistoryTreeBuilder {
    /// The calendar every screen works periods out in (`Calendar.forPeriods`).
    /// History names its periods in Gregorian, so it works them out in
    /// Gregorian too: in a Hebrew or Islamic calendar a "month" row titled
    /// September ran from 12 September to 11 October.
    static func calendar(_ base: Calendar = .current) -> Calendar {
        base.forPeriods
    }

    /// The start of the next calendar day. Normalised, because in a zone
    /// whose clocks change at midnight the transition day begins at 01:00,
    /// and adding a day to that keeps the hour: the index is keyed by
    /// `startOfDay`, so every later lookup would miss.
    static func dayAfter(_ day: Date, calendar: Calendar = calendar()) -> Date {
        let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day))
            ?? day.addingTimeInterval(86_400)
        return calendar.startOfDay(for: next)
    }

    /// The calendar period of `level` holding `date`.
    static func period(_ level: HistoryLevel, containing date: Date, calendar: Calendar = calendar()) -> DateInterval {
        calendar.dateInterval(of: level.component, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), end: dayAfter(date, calendar: calendar))
    }

    /// The smallest period holding every recorded day and today.
    static func top(days: [HistoryDay], today: Date, calendar: Calendar = calendar()) -> HistoryTop {
        let today = calendar.startOfDay(for: today)
        let firstDay = min(days.map { calendar.startOfDay(for: $0.date) }.min() ?? today, today)
        let record = DateInterval(start: firstDay, end: dayAfter(today, calendar: calendar))
        for level in [HistoryLevel.week, .month, .year] {
            let candidate = period(level, containing: today, calendar: calendar)
            if candidate.start <= firstDay {
                return HistoryTop(place: HistoryPlace(level: level, span: candidate.intersection(with: record) ?? record),
                                  firstDay: firstDay, today: today, calendar: calendar)
            }
        }
        return HistoryTop(place: nil, firstDay: firstDay, today: today, calendar: calendar)
    }

    /// The rows under `parent`, newest first; nil gives the root rows. Each
    /// child period is clipped to the parent's span, which is itself clipped
    /// to the record, so nothing reaches before the first day or past today.
    static func rows(under parent: HistoryPlace?, top: HistoryTop, days: [HistoryDay],
                     calendar: Calendar = calendar()) -> [HistoryRow] {
        rows(under: parent, top: top, byDate: index(days, calendar: calendar), calendar: calendar)
    }

    static func rows(under parent: HistoryPlace?, top: HistoryTop, byDate: [Date: HistoryDay],
                     calendar: Calendar) -> [HistoryRow] {
        guard let level = parent?.level.child ?? Optional(top.rootLevel) else { return [] }
        let bounds = parent?.span ?? top.span
        var result: [HistoryRow] = []
        var cursor = period(level, containing: bounds.start, calendar: calendar).start
        while cursor < bounds.end {
            let whole = period(level, containing: cursor, calendar: calendar)
            if let span = whole.intersection(with: bounds), span.duration > 0 {
                result.append(row(HistoryPlace(level: level, span: span), byDate: byDate, calendar: calendar))
            }
            cursor = whole.end
        }
        return result.reversed()
    }

    /// One row's figures from the days in its span. `live` stands in for its
    /// own day, so today's running figures reach a row without the index
    /// being rebuilt.
    static func row(_ place: HistoryPlace, byDate: [Date: HistoryDay], live: HistoryDay? = nil,
                    calendar: Calendar) -> HistoryRow {
        let liveDay = live.map { calendar.startOfDay(for: $0.date) }
        var focused: TimeInterval = 0, tracked: TimeInterval = 0
        var focusedDays = 0, sessions = 0
        var byType: [WorkType: TimeInterval] = [:]
        var evidence = false
        forEachDay(in: place.span, calendar: calendar) { day in
            guard let row = day == liveDay ? live : byDate[day] else { return }
            focused += row.focused
            tracked += row.tracked
            sessions += row.sessions
            if row.focused > 0 { focusedDays += 1 }
            for (type, seconds) in row.focusByWorkType where type.countsAsFocus { byType[type, default: 0] += seconds }
            if row.focused > 0 || row.tracked > 0 || row.sessions > 0 || !row.workTypes.isEmpty { evidence = true }
        }
        return HistoryRow(place: place, focused: focused, tracked: tracked, focusedDays: focusedDays,
                          sessions: sessions, mainWorkType: WorkTypeShare.shares(from: byType).first?.workType,
                          hasEvidence: evidence, bars: bars(for: place, byDate: byDate, live: live, calendar: calendar))
    }

    /// A year's bars are its months; a month's or week's are its days; a
    /// day has none (its strip is drawn from the day's sessions).
    private static func bars(for place: HistoryPlace, byDate: [Date: HistoryDay], live: HistoryDay?,
                             calendar: Calendar) -> [HistoryBar] {
        let liveDay = live.map { calendar.startOfDay(for: $0.date) }
        func focus(on day: Date) -> TimeInterval { (day == liveDay ? live : byDate[day])?.focused ?? 0 }
        switch place.level {
        case .day: return []
        case .year:
            var result: [HistoryBar] = []
            var cursor = place.span.start
            while cursor < place.span.end {
                let month = period(.month, containing: cursor, calendar: calendar)
                let span = month.intersection(with: place.span) ?? month
                var total: TimeInterval = 0
                forEachDay(in: span, calendar: calendar) { total += focus(on: $0) }
                result.append(HistoryBar(start: span.start, focused: total))
                cursor = month.end
            }
            return result
        case .month, .week:
            var result: [HistoryBar] = []
            forEachDay(in: place.span, calendar: calendar) { result.append(HistoryBar(start: $0, focused: focus(on: $0))) }
            return result
        }
    }

    /// The headline's figures and its best child.
    static func summary(top: HistoryTop, days: [HistoryDay], calendar: Calendar = calendar()) -> HistorySummary {
        summary(top: top, byDate: index(days, calendar: calendar), calendar: calendar)
    }

    static func summary(top: HistoryTop, byDate: [Date: HistoryDay], live: HistoryDay? = nil,
                        calendar: Calendar) -> HistorySummary {
        let whole = row(HistoryPlace(level: top.place?.level ?? .year, span: top.span), byDate: byDate, live: live,
                        calendar: calendar)
        let level = bestLevel(for: top)
        var best: (place: HistoryPlace, focused: TimeInterval)?
        var cursor = period(level, containing: top.span.start, calendar: calendar).start
        while cursor < top.span.end {
            let whole = period(level, containing: cursor, calendar: calendar)
            if let span = whole.intersection(with: top.span), span.duration > 0 {
                let candidate = row(HistoryPlace(level: level, span: span), byDate: byDate, live: live, calendar: calendar)
                if candidate.focused > (best?.focused ?? 0) { best = (candidate.place, candidate.focused) }
            }
            cursor = whole.end
        }
        return HistorySummary(focused: whole.focused, tracked: whole.tracked, focusedDays: whole.focusedDays,
                              sessions: whole.sessions, best: best)
    }

    /// The best month of a year or the record; the best day of a month or week.
    private static func bestLevel(for top: HistoryTop) -> HistoryLevel {
        (top.place?.level ?? .year) <= .year ? .month : .day
    }

    /// A cached summary brought up to today's live figures without walking
    /// the record: the totals move by today's change, and the best child is
    /// re-judged only against today's own unit.
    static func patching(_ summary: HistorySummary, top: HistoryTop, byDate: [Date: HistoryDay],
                         cachedToday: HistoryDay?, live: HistoryDay?, calendar: Calendar) -> HistorySummary {
        guard let live, live != cachedToday else { return summary }
        let today = calendar.startOfDay(for: live.date)
        guard top.span.holds(today) else { return summary }
        let was = cachedToday
        let focused = summary.focused - (was?.focused ?? 0) + live.focused
        let tracked = summary.tracked - (was?.tracked ?? 0) + live.tracked
        let sessions = summary.sessions - (was?.sessions ?? 0) + live.sessions
        let focusedDays = summary.focusedDays - ((was?.focused ?? 0) > 0 ? 1 : 0) + (live.focused > 0 ? 1 : 0)
        let level = bestLevel(for: top)
        let unit = period(level, containing: today, calendar: calendar).intersection(with: top.span)
            ?? DateInterval(start: today, end: dayAfter(today, calendar: calendar))
        let candidate = row(HistoryPlace(level: level, span: unit), byDate: byDate, live: live, calendar: calendar)
        var best = summary.best
        if best?.place == candidate.place {
            // Today's unit was already the best; focus only grows while a
            // session runs, so it stays the best at its new figure.
            best = candidate.focused > 0 ? (candidate.place, candidate.focused) : nil
        } else if candidate.focused > (best?.focused ?? 0) {
            best = (candidate.place, candidate.focused)
        }
        return HistorySummary(focused: focused, tracked: tracked, focusedDays: focusedDays,
                              sessions: sessions, best: best)
    }

    /// The open path after the tree moved under it: midnight re-clips the
    /// rows holding today, and a longer record can step the top up a level.
    /// Each open place is rebuilt as the row now drawn for its first day,
    /// down to the same level; a place no longer in the record folds away.
    static func reconcile(open: [HistoryPlace], top: HistoryTop, calendar: Calendar = calendar()) -> [HistoryPlace] {
        guard let deepest = open.last else { return [] }
        let path = path(to: deepest.start, top: top, calendar: calendar).filter { $0.level <= deepest.level }
        // The path is only the row if it reached the deepest level.
        return path.last?.level == deepest.level ? path : []
    }

    /// What History opens with: the path from the root down to this week,
    /// each place clipped exactly as its row is drawn. Nothing when the top
    /// is the week itself.
    static func pathToToday(top: HistoryTop, calendar: Calendar = calendar()) -> [HistoryPlace] {
        var result: [HistoryPlace] = []
        var bounds = top.span
        var level: HistoryLevel? = top.rootLevel
        while let current = level, current <= .week {
            let whole = period(current, containing: top.today, calendar: calendar)
            guard let span = whole.intersection(with: bounds) else { break }
            result.append(HistoryPlace(level: current, span: span))
            bounds = span
            level = current.child
        }
        return result
    }

    /// The path from the root down to `day`, for Jump to date and search.
    static func path(to day: Date, top: HistoryTop, calendar: Calendar = calendar()) -> [HistoryPlace] {
        let day = calendar.startOfDay(for: day)
        var result: [HistoryPlace] = []
        var bounds = top.span
        var level: HistoryLevel? = top.rootLevel
        while let current = level {
            let whole = period(current, containing: day, calendar: calendar)
            guard let span = whole.intersection(with: bounds) else { break }
            result.append(HistoryPlace(level: current, span: span))
            bounds = span
            level = current.child
        }
        return result
    }

    /// Rows holding today, rebuilt with the live day standing in for the
    /// cached one; the rest untouched, and the index untouched.
    static func patching(_ rows: [HistoryRow], byDate: [Date: HistoryDay], cachedToday: HistoryDay?,
                         live: HistoryDay?, calendar: Calendar = calendar()) -> [HistoryRow] {
        guard let live, live != cachedToday else { return rows }
        let today = calendar.startOfDay(for: live.date)
        guard rows.contains(where: { $0.place.span.holds(today) }) else { return rows }
        return rows.map { $0.place.span.holds(today) ? row($0.place, byDate: byDate, live: live, calendar: calendar) : $0 }
    }

    static func index(_ days: [HistoryDay], calendar: Calendar) -> [Date: HistoryDay] {
        var byDate: [Date: HistoryDay] = [:]
        for day in days { byDate[calendar.startOfDay(for: day.date)] = day }
        return byDate
    }

    private static func forEachDay(in span: DateInterval, calendar: Calendar, _ body: (Date) -> Void) {
        var cursor = calendar.startOfDay(for: span.start)
        while cursor < span.end {
            body(cursor)
            cursor = dayAfter(cursor, calendar: calendar)
        }
    }
}

/// What the keyboard stands on in History: a row, or a session under an
/// open day.
enum HistoryFocus: Hashable {
    case row(HistoryPlace)
    case session(thread: UUID, day: Date)
}

extension HistoryTreeBuilder {
    /// Every stop ↑ and ↓ can land on, in reading order: each root row,
    /// then, under the one that is open, its rows, and so on down; under an
    /// open day, its sessions. Breaks are not stops.
    static func visible(open: [HistoryPlace], rows: (HistoryPlace?) -> [HistoryRow],
                        threads: (Date) -> [UUID]) -> [HistoryFocus] {
        var result: [HistoryFocus] = []
        func walk(_ parent: HistoryPlace?, depth: Int) {
            for row in rows(parent) {
                result.append(.row(row.place))
                guard open.indices.contains(depth), open[depth] == row.place else { continue }
                if row.place.level == .day {
                    for thread in threads(row.place.start) { result.append(.session(thread: thread, day: row.place.start)) }
                } else {
                    walk(row.place, depth: depth + 1)
                }
            }
        }
        walk(nil, depth: 0)
        return result
    }
}
