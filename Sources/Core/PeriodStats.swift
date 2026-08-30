import Foundation

enum TrackingPeriod: String, Codable, CaseIterable {
    case day, week, month

    var displayName: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        }
    }
}

/// One calendar day's rollup — one bar in the period chart.
struct PeriodDay: Identifiable, Equatable {
    let date: Date
    let tracked: TimeInterval
    let byWorkType: [WorkTypeShare]
    var id: Date { date }
}

/// The only measure a period bar carries. Work-type composition is presented
/// separately by the donut and must never be stacked into this value.
struct PeriodChartPoint: Identifiable, Equatable {
    let date: Date
    let seconds: TimeInterval
    var id: Date { date }
}

/// Pure plot geometry for the tracked-by-day chart. It lives in Core so the
/// contract can be tested without a view: a bar drawn hard against the plot
/// frame is unreadable, and a scale that ends below the average rule hides it.
enum PeriodChartLayout {
    /// One empty bar-width of padding on each side of the series. A daily bar
    /// occupies the whole cell from its own day to the next, so the trailing
    /// bound is two days past the last point: stopping one day past it lets the
    /// final bar fill the padding and finish flush against the plot frame.
    /// Calendar arithmetic rather than 86,400 seconds, because a daylight-saving
    /// day is 23 or 25 hours long and fixed seconds would land the edge mid-day.
    static func domain(for points: [PeriodChartPoint],
                       calendar: Calendar = .current) -> ClosedRange<Date> {
        let anchor = points.map(\.date).min() ?? calendar.startOfDay(for: Date())
        let end = points.map(\.date).max() ?? anchor
        let first = calendar.startOfDay(for: anchor)
        let last = calendar.startOfDay(for: end)
        let lower = calendar.date(byAdding: .day, value: -1, to: first) ?? first
        let upper = calendar.date(byAdding: .day, value: 2, to: last) ?? last
        return lower...max(upper, lower)
    }

    /// The vertical scale in minutes: zero-based, always containing the tallest
    /// bar and the average rule, rounded up to a step a reader can label.
    static func yMaximumMinutes(for points: [PeriodChartPoint],
                                average: TimeInterval) -> Double {
        let tallest = points.map(\.seconds).max() ?? 0
        let minutes = max(tallest, max(0, average)) / 60
        let step: Double
        switch minutes {
        case ..<60: step = 15
        case ..<240: step = 30
        case ..<600: step = 60
        default: step = 120
        }
        return max(step, (minutes / step).rounded(.up) * step)
    }
}

enum PeriodChartData {
    static func tracked(_ days: [PeriodDay]) -> [PeriodChartPoint] {
        days.map { PeriodChartPoint(date: $0.date, seconds: $0.tracked) }
    }
}

struct PeriodSummary: Equatable {
    let tracked: TimeInterval
    let activeDays: Int
    let totalDays: Int
    let averagePerActiveDay: TimeInterval
    let longest: AppSession?
}

struct LogEntry: Identifiable, Equatable {
    let session: AppSession
    let day: Date
    var id: String { session.id }
}

/// How the session log is ordered.
enum LogGrouping: String, Codable, CaseIterable {
    case byApp, byTime

    var displayName: String {
        switch self {
        case .byApp: return "By app"
        case .byTime: return "By time"
        }
    }
}

/// One app's whole period: every session it had, and what they add up to.
/// Chronological order answers "what did I do at 3pm"; this answers "how much
/// of my week went to this app", which is the question people actually ask.
struct LogAppGroup: Identifiable, Equatable {
    let bundleID: String
    let appName: String
    let total: TimeInterval
    let visits: Int
    /// Newest first, matching the chronological view.
    let sessions: [LogEntry]
    /// Share of the period's tracked total, 0...1.
    let share: Double
    var id: String { bundleID }

    /// The span this app covers across the whole period. Not the selected day's
    /// span — in a week view that would name one day and mean another.
    var firstStart: Date { sessions.map(\.session.start).min() ?? Date() }
    var lastEnd: Date { sessions.map(\.session.end).max() ?? Date() }

    var longest: TimeInterval { sessions.map(\.session.attended).max() ?? 0 }

    /// Mean attended time per session. Reported beside the longest because one
    /// long sitting and forty glances produce the same total and are not the
    /// same behaviour.
    var averageSession: TimeInterval {
        sessions.isEmpty ? 0 : total / Double(sessions.count)
    }

    /// This app's own shape across the period, oldest day first, including days
    /// it was not used at all — a gap has to look like a gap.
    func dailyTotals(from start: Date, to end: Date,
                     calendar: Calendar = .current) -> [(day: Date, seconds: TimeInterval)] {
        var totals: [Date: TimeInterval] = [:]
        for entry in sessions {
            totals[entry.day, default: 0] += entry.session.attended
        }
        var result: [(day: Date, seconds: TimeInterval)] = []
        var cursor = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        while cursor <= last && result.count < 40 {
            result.append((cursor, totals[cursor] ?? 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }
}

/// Everything the dashboard needs for one period, from one walk over the days.
struct PeriodRollup: Equatable {
    let days: [PeriodDay]
    /// Newest bounded rows for chronological presentation.
    let log: [LogEntry]
    /// Exact app-session rows grouped by their local calendar day. Detail views
    /// use this index rather than the bounded chronological presentation.
    let entriesByDay: [Date: [LogEntry]]
    /// Exact source count and app aggregates remain independent of the row cap.
    let totalLogEntries: Int
    let exactAppGroups: [LogAppGroup]
    let dayTotals: [Date: TimeInterval]
    let summary: PeriodSummary

    var logRowsOmitted: Int { max(0, totalLogEntries - log.count) }

    static let empty = PeriodRollup(
        days: [], log: [], entriesByDay: [:], totalLogEntries: 0, exactAppGroups: [], dayTotals: [:],
        summary: PeriodSummary(tracked: 0, activeDays: 0, totalDays: 0,
                               averagePerActiveDay: 0, longest: nil))
}

/// Week and month rollups. Composes `DashboardStats` once per day rather than
/// reimplementing the arithmetic, so a day's numbers have exactly one definition
/// and the period totals can never drift from the day view.
struct PeriodStats {

    private static let maximumLogEntries = 500

    private let sessions: SessionArchive
    private let usage: AppUsageArchive
    private let usageSnapshot: AppUsageSnapshot?
    private let calendar: Calendar
    private let now: () -> Date

    init(sessions: SessionArchive,
         usage: AppUsageArchive,
         usageSnapshot: AppUsageSnapshot? = nil,
         calendar: Calendar = .current,
         now: @escaping () -> Date = Date.init) {
        self.sessions = sessions
        self.usage = usage
        self.usageSnapshot = usageSnapshot
        self.calendar = calendar
        self.now = now
    }

    func bounds(for period: TrackingPeriod, containing day: Date) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: day)
        switch period {
        case .day:
            return (start, calendar.date(byAdding: .day, value: 1, to: start) ?? start)
        case .week:
            let interval = calendar.dateInterval(of: .weekOfYear, for: start)
            return (interval?.start ?? start, interval?.end ?? start)
        case .month:
            let interval = calendar.dateInterval(of: .month, for: start)
            return (interval?.start ?? start, interval?.end ?? start)
        }
    }

    /// Tracked total for the period before the one containing `day` — the
    /// baseline behind "vs last week". Walks the same day slices the chart
    /// does, so the comparison can never drift from the bars.
    func previousPeriodTracked(for period: TrackingPeriod, containing day: Date) -> TimeInterval {
        let (start, _) = bounds(for: period, containing: day)
        guard let previousDay = calendar.date(byAdding: .second, value: -1, to: start) else {
            return 0
        }
        let (previousStart, previousEnd) = bounds(for: period, containing: previousDay)
        let stats = DashboardStats(sessions: sessions, usage: usage,
                                   usageSnapshot: usageSnapshot,
                                   calendar: calendar, now: now)
        var total: TimeInterval = 0
        var cursor = previousStart
        var guardRail = 0
        while cursor < previousEnd && guardRail < 40 {
            guardRail += 1
            total += stats.trackedTotal(for: cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return total
    }

    /// One entry per calendar day, including idle ones, so the chart has a slot
    /// for every day and gaps read as gaps rather than as missing bars.
    func days(for period: TrackingPeriod, containing day: Date) -> [PeriodDay] {
        let (start, end) = bounds(for: period, containing: day)
        let stats = DashboardStats(sessions: sessions, usage: usage,
                                   usageSnapshot: usageSnapshot,
                                   calendar: calendar, now: now)
        var result: [PeriodDay] = []
        var cursor = start
        while cursor < end && result.count < 40 {
            result.append(PeriodDay(date: cursor,
                                    tracked: stats.trackedTotal(for: cursor),
                                    byWorkType: stats.focusQuality(for: cursor).byWorkType))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    /// One walk over the period. `DashboardStats` memoises a single day at a
    /// time, so asking it for days, log and totals separately rebuilt every day
    /// slice three times over — 93 passes over the usage array for a month, on
    /// every refresh. This does it once.
    func rollup(for period: TrackingPeriod, containing day: Date) -> PeriodRollup {
        let (start, end) = bounds(for: period, containing: day)
        let stats = DashboardStats(sessions: sessions, usage: usage,
                                   usageSnapshot: usageSnapshot,
                                   calendar: calendar, now: now)
        var allDays: [PeriodDay] = []
        var retainedEntries: [LogEntry] = []
        var allEntries: [LogEntry] = []
        var entriesByDay: [Date: [LogEntry]] = [:]
        var cursor = start
        while cursor < end && allDays.count < 40 {
            allDays.append(PeriodDay(date: cursor,
                                     tracked: stats.trackedTotal(for: cursor),
                                     byWorkType: stats.focusQuality(for: cursor).byWorkType))
            let dayEntries = Self.logEntries(on: cursor, stats: stats)
            allEntries.append(contentsOf: dayEntries)
            entriesByDay[cursor] = dayEntries
            Self.retainNewest(dayEntries, in: &retainedEntries)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        allEntries.sort { $0.session.start > $1.session.start }
        retainedEntries.sort { $0.session.start > $1.session.start }
        var totals: [Date: TimeInterval] = [:]
        for entry in retainedEntries { totals[entry.day, default: 0] += entry.session.attended }
        return PeriodRollup(days: allDays,
                            log: retainedEntries,
                            entriesByDay: entriesByDay,
                            totalLogEntries: allEntries.count,
                            exactAppGroups: Self.appGroups(from: allEntries),
                            dayTotals: totals,
                            summary: summarise(days: allDays, entries: allEntries))
    }

    func summary(for period: TrackingPeriod, containing day: Date) -> PeriodSummary {
        rollup(for: period, containing: day).summary
    }

    private func summarise(days allDays: [PeriodDay], entries: [LogEntry]) -> PeriodSummary {
        // The summary and the chart consume the exact same canonical series.
        // Work-type composition remains on `PeriodDay.byWorkType` and cannot
        // leak into either the bars or their average.
        let trackedSeries = PeriodChartData.tracked(allDays)
        let active = trackedSeries.filter { $0.seconds > 0 }
        let tracked = trackedSeries.reduce(0) { $0 + $1.seconds }
        return PeriodSummary(
            tracked: tracked,
            activeDays: active.count,
            totalDays: allDays.count,
            // Divided by ACTIVE days, not calendar days: averaging a five-day
            // week over seven understates every working day by nearly a third.
            averagePerActiveDay: active.isEmpty ? 0 : tracked / Double(active.count),
            longest: entries.map(\.session).max { $0.attended < $1.attended })
    }

    /// Every grouped session in the period, newest first.
    func log(for period: TrackingPeriod, containing day: Date) -> [LogEntry] {
        let (start, end) = bounds(for: period, containing: day)
        let stats = DashboardStats(sessions: sessions, usage: usage,
                                   usageSnapshot: usageSnapshot,
                                   calendar: calendar, now: now)
        var entries: [LogEntry] = []
        var cursor = start
        var visited = 0
        while cursor < end && visited < 40 {
            visited += 1
            Self.retainNewest(Self.logEntries(on: cursor, stats: stats), in: &entries)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return entries.sorted { $0.session.start > $1.session.start }
    }

    /// All grouped app sessions on one day. Sorting here makes same-day overflow
    /// deterministic before `retainNewest` drops the oldest prefix.
    private static func logEntries(on day: Date, stats: DashboardStats) -> [LogEntry] {
        var result: [LogEntry] = []
        for rank in stats.rankedApps(for: day) {
            for session in stats.sessions(for: day, bundleID: rank.bundleID) {
                result.append(LogEntry(session: session, day: day))
            }
        }
        return result.sorted { left, right in
            if left.session.start != right.session.start {
                return left.session.start < right.session.start
            }
            if left.session.end != right.session.end {
                return left.session.end < right.session.end
            }
            return left.session.id < right.session.id
        }
    }

    /// Days are visited oldest first. Append a chronologically ordered day, then
    /// remove only the oldest overflow so the newest 500 survive. Every rollup
    /// consumer is derived after this retention step from the identical array.
    private static func retainNewest(_ newEntries: [LogEntry],
                                     in retained: inout [LogEntry]) {
        retained.append(contentsOf: newEntries)
        let overflow = retained.count - maximumLogEntries
        if overflow > 0 { retained.removeFirst(overflow) }
    }

    /// Collapses a period's log into one row per app, largest first. Ties break
    /// on name so the order cannot shuffle between refreshes.
    static func appGroups(from entries: [LogEntry]) -> [LogAppGroup] {
        var order: [String] = []
        var byApp: [String: [LogEntry]] = [:]
        for entry in entries {
            if byApp[entry.session.bundleID] == nil { order.append(entry.session.bundleID) }
            byApp[entry.session.bundleID, default: []].append(entry)
        }
        let overall = entries.reduce(0) { $0 + $1.session.attended }
        let groups = order.compactMap { bundleID -> LogAppGroup? in
            guard let sessions = byApp[bundleID], let first = sessions.first else { return nil }
            let total = sessions.reduce(0) { $0 + $1.session.attended }
            return LogAppGroup(bundleID: bundleID,
                               appName: first.session.appName,
                               total: total,
                               visits: sessions.reduce(0) { $0 + $1.session.visits },
                               sessions: sessions,
                               share: overall > 0 ? total / overall : 0)
        }
        return groups.sorted {
            $0.total == $1.total ? $0.appName < $1.appName : $0.total > $1.total
        }
    }

    /// Splits the tail off the list. Nothing is discarded — the caller shows the
    /// minor apps behind one line, and every share is still computed over the
    /// whole period, so the percentages do not shift when the tail is hidden.
    static func splitMinor(_ groups: [LogAppGroup])
        -> (major: [LogAppGroup], minor: [LogAppGroup]) {
        let major = groups.filter { $0.total >= FocusConstants.minorAppFloor }
        let minor = groups.filter { $0.total < FocusConstants.minorAppFloor }
        // Never collapse a lone straggler: "+1 app under 30s" costs the same
        // row it saves.
        return minor.count > 1 ? (major, minor) : (groups, [])
    }

    /// Totals keyed by day, for the log's day headers.
    func dayTotals(for period: TrackingPeriod, containing day: Date) -> [Date: TimeInterval] {
        var totals: [Date: TimeInterval] = [:]
        for entry in log(for: period, containing: day) {
            totals[entry.day, default: 0] += entry.session.attended
        }
        return totals
    }
}
