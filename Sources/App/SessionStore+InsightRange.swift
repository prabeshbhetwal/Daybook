import Foundation

/// How often a category's own daily goal was met across a range.
struct InsightGoalRate: Identifiable, Equatable {
    let workType: WorkType
    let goal: TimeInterval
    let metDays: Int
    let focusedDays: Int
    var id: String { workType.rawValue }
    var share: Double { focusedDays > 0 ? Double(metDays) / Double(focusedDays) : 0 }
}

/// Everything the Insights canvas draws about a whole range, beyond the
/// per-period totals the projections already hold. Built in one pass over the
/// archive so the chart, the grid and the rail cannot disagree.
struct InsightReading {
    let periods: [StoryPeriodProjection]
    let facts: InsightRangeFacts
}

struct InsightReadingKey: Hashable {
    let scope: InsightRange
    let anchor: Date
    let limit: Int
    let evidence: SessionStore.EvidenceRevision
    let minute: Int
}

struct InsightRangeFacts: Equatable {
    /// Focused seconds by row and clock hour. What a row stands for follows
    /// the span being read: a day, a weekday, or a month.
    let grid: [[TimeInterval]]
    /// Short axis label per row: "THU 17", "MON", "SEP".
    let rowLabels: [String]
    /// How a sentence places each row: "on Thursday 17 September", "on Mondays",
    /// "in September".
    let rowPhrases: [String]
    let categories: [WorkTypeShare]
    let apps: [AppRank]
    let goalRates: [InsightGoalRate]

    static let empty = InsightRangeFacts(grid: [], rowLabels: [], rowPhrases: [],
                                         categories: [], apps: [], goalRates: [])

    var gridPeak: TimeInterval { grid.map { $0.max() ?? 0 }.max() ?? 0 }

    /// Focused seconds per clock hour, every weekday together.
    var hourTotals: [TimeInterval] {
        (0..<24).map { hour in grid.reduce(0) { $0 + $1[hour] } }
    }

    /// The two adjacent clock hours holding the most focus, or nil until half
    /// an hour of focus exists anywhere in the range.
    var bestWindow: (startHour: Int, seconds: TimeInterval)? {
        let totals = hourTotals
        guard totals.reduce(0, +) >= 1_800 else { return nil }
        var best = (startHour: 0, seconds: TimeInterval(-1))
        for start in 0..<23 {
            let sum = totals[start] + totals[start + 1]
            if sum > best.seconds { best = (start, sum) }
        }
        return best.seconds > 0 ? best : nil
    }

    /// Where the best window's focus mostly sits, as a phrase. Nil when the
    /// grid has a single row, since then it says nothing.
    var bestWindowPhrase: String? {
        guard grid.count > 1, let window = bestWindow else { return nil }
        var bestRow: Int?
        var bestSum: TimeInterval = 0
        for (row, hours) in grid.enumerated() {
            let sum = hours[window.startHour] + hours[window.startHour + 1]
            if sum > bestSum { bestSum = sum; bestRow = row }
        }
        return bestRow.flatMap { rowPhrases.indices.contains($0) ? rowPhrases[$0] : nil }
    }

    /// The clock hours worth drawing: the span that holds focus, padded by one
    /// hour and never narrower than eight, so a quiet range is not a wall of
    /// empty cells.
    var visibleHours: ClosedRange<Int> {
        let totals = hourTotals
        guard let first = totals.firstIndex(where: { $0 > 0 }),
              let last = totals.lastIndex(where: { $0 > 0 }) else { return 8...18 }
        var low = max(0, first - 1), high = min(23, last + 1)
        while high - low < 7 {
            if low > 0 { low -= 1 }
            if high - low < 7, high < 23 { high += 1 }
            if low == 0 && high == 23 { break }
        }
        return low...high
    }
}

extension SessionStore {
    /// The range's grid, category shares, apps and goal rates. `periods` are
    /// the projections the canvas already lists, so both describe the same days.
    /// Everything History draws for one span: its periods and the facts across
    /// them. Served from a one-entry cache until the evidence behind it
    /// changes, or until the current minute turns over when today is in the
    /// range — the only period whose figures can move without an archive write.
    ///
    /// The view reads this from `body`, and `body` runs once a second while a
    /// session ticks. Before this the reading was rebuilt each time: every
    /// day's projection, every session spread across the hour grid. A page of
    /// History held a core at full load for as long as it was open.
    func insightReading(scope: InsightRange,
                        anchoredAt anchor: Date,
                        limit: Int,
                        calendar: Calendar = .current) -> InsightReading {
        let calendar = calendar.forPeriods
        let day = calendar.startOfDay(for: anchor)
        let today = calendar.startOfDay(for: now())
        let minute = day >= today
            ? Int(now().timeIntervalSinceReferenceDate / 60) : 0
        let key = InsightReadingKey(scope: scope, anchor: day, limit: limit,
                                    evidence: evidenceRevision, minute: minute)
        if let cached = insightReadingCache[key] { return cached }
        insightReadingComputeCount &+= 1
        let periods = insightPeriodProjections(scope: scope, anchoredAt: anchor,
                                               limit: limit, calendar: calendar)
        let reading = InsightReading(periods: periods,
                                     facts: insightRangeFacts(periods: periods, scope: scope,
                                                              calendar: calendar))
        insightReadingCache[key] = reading
        insightReadingCacheOrder.append(key)
        while insightReadingCacheOrder.count > 8 {
            insightReadingCache.removeValue(forKey: insightReadingCacheOrder.removeFirst())
        }
        return reading
    }

    func insightRangeFacts(periods: [StoryPeriodProjection],
                           scope: InsightRange = .week,
                           calendar: Calendar = .current) -> InsightRangeFacts {
        let days = periods.flatMap(\.days)
        guard let first = days.map(\.date).min(), let last = days.map(\.date).max(),
              let rangeEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last))
        else { return .empty }
        let rangeStart = calendar.startOfDay(for: first)
        let rows = InsightGridRows(scope: scope, periods: periods, calendar: calendar)
        var grid = Array(repeating: Array(repeating: TimeInterval(0), count: 24), count: rows.labels.count)
        var byCategory: [WorkType: TimeInterval] = [:]

        /// Files each clock hour's own work under that hour. The hours are the
        /// calendar's real intervals: on the night clocks go back, setting the
        /// hour by number landed on the repeated hour's first pass, behind the
        /// cursor, and the walk stopped there with the rest of the day uncounted.
        /// The work comes from the pause-aware allocation, so a pause stays in
        /// the hours it happened instead of thinning every hour of the span.
        func spread(start: Date, end: Date, type: WorkType,
                    work: ((start: Date, end: Date)) -> TimeInterval) {
            var cursor = start
            while cursor < end {
                let hourEnd = calendar.dateInterval(of: .hour, for: cursor)?.end
                let sliceEnd = min(end, hourEnd.flatMap { $0 > cursor ? $0 : nil }
                                   ?? cursor.addingTimeInterval(3_600))
                let seconds = min(sliceEnd.timeIntervalSince(cursor), work((start: cursor, end: sliceEnd)))
                if let row = rows.row(for: cursor) {
                    grid[row][calendar.component(.hour, from: cursor)] += seconds
                }
                byCategory[type, default: 0] += seconds
                cursor = sliceEnd
            }
        }

        for record in engine.archive.records where record.workType.countsAsFocus {
            let start = max(record.start, rangeStart), end = min(record.end, rangeEnd)
            guard end > start else { continue }
            spread(start: start, end: end, type: record.workType, work: record.workSeconds(in:))
        }
        if engine.state != .idle, engine.activeWorkType.countsAsFocus {
            let start = max(engine.sessionStartDate, rangeStart), end = min(now(), rangeEnd)
            if end > start {
                spread(start: start, end: end, type: engine.activeWorkType, work: engine.elapsed(in:))
            }
        }

        let categories = WorkTypeShare.shares(from: byCategory)

        var appTotals: [String: (name: String, total: TimeInterval, longest: TimeInterval)] = [:]
        for app in days.flatMap(\.apps) {
            let existing = appTotals[app.bundleID]
            appTotals[app.bundleID] = (app.appName, (existing?.total ?? 0) + app.total,
                                       max(existing?.longest ?? 0, app.longest))
        }
        var appSum: TimeInterval = 0
        for value in appTotals.values { appSum += value.total }
        var apps: [AppRank] = []
        for (key, value) in appTotals {
            let share: Double = appSum > 0 ? value.total / appSum : 0
            apps.append(AppRank(bundleID: key, appName: value.name, total: value.total,
                                share: share, longest: value.longest))
        }
        apps.sort { (a: AppRank, b: AppRank) -> Bool in
            a.total == b.total ? a.appName < b.appName : a.total > b.total
        }

        let focusedDays = days.filter { $0.focused > 0 }
        let goalTypes = WorkType.startable.filter { ($0.dailyGoal ?? 0) > 0 }
        var met: [WorkType: Int] = [:]
        if !goalTypes.isEmpty {
            for day in focusedDays {
                let seconds = storyCategorySeconds(on: day.date)
                for type in goalTypes where (seconds[type] ?? 0) >= (type.dailyGoal ?? .infinity) {
                    met[type, default: 0] += 1
                }
            }
        }
        let goalRates = goalTypes.map {
            InsightGoalRate(workType: $0, goal: $0.dailyGoal ?? 0,
                            metDays: met[$0] ?? 0, focusedDays: focusedDays.count)
        }
        return InsightRangeFacts(grid: grid, rowLabels: rows.labels, rowPhrases: rows.phrases,
                                 categories: categories,
                                 apps: apps, goalRates: focusedDays.isEmpty ? [] : goalRates)
    }
}

/// What each row of the focus grid stands for. The rows follow the span the
/// reader chose, so the grid answers that span's question: which hours each
/// day, which hours each weekday, which hours each month.
struct InsightGridRows {
    let labels: [String]
    let phrases: [String]
    private let scope: InsightRange
    private let calendar: Calendar
    private let keys: [Date]
    private let weekdays: [Int]

    init(scope: InsightRange, periods: [StoryPeriodProjection], calendar: Calendar) {
        let calendar = calendar.forPeriods
        self.scope = scope
        self.calendar = calendar
        func text(_ format: String, _ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_AU")
            formatter.calendar = calendar
            formatter.dateFormat = format
            return formatter.string(from: date)
        }
        switch scope {
        case .week:
            let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
            weekdays = order
            keys = []
            let symbols = calendar.weekdaySymbols
            labels = order.map { String(symbols[$0 - 1].prefix(3)).uppercased() }
            phrases = order.map { "on \(symbols[$0 - 1])s" }
        case .day:
            weekdays = []
            // Newest first, as the periods arrive.
            keys = periods.map { calendar.startOfDay(for: $0.start) }
            labels = keys.map { text("EEE d", $0).uppercased() }
            phrases = keys.map { "on \(Tokens.longDate($0))" }
        case .month:
            weekdays = []
            keys = periods.map(\.start)
            labels = keys.map { text("MMM", $0).uppercased() }
            phrases = keys.map { "in \(text("MMMM", $0))" }
        }
    }

    func row(for moment: Date) -> Int? {
        switch scope {
        case .week:
            return weekdays.firstIndex(of: calendar.component(.weekday, from: moment))
        case .day:
            return keys.firstIndex(of: calendar.startOfDay(for: moment))
        case .month:
            guard let start = calendar.dateInterval(of: .month, for: moment)?.start else { return nil }
            return keys.firstIndex(of: start)
        }
    }
}
