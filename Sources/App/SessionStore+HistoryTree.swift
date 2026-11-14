import Foundation

/// What the store keeps of History's tree between archive changes. Rows,
/// summaries and the front view's read models are built from `byDate` once;
/// today's live figures are laid over them on each read rather than rebuilt
/// into them.
struct HistoryTreeCache {
    let key: JournalKey
    let top: HistoryTop
    let byDate: [Date: HistoryDay]
    /// Today as the index knew it, so a read can tell whether today moved.
    let cachedToday: HistoryDay?
    var rows: [String: [HistoryRow]] = [:]
    var summaries: [String: HistorySummary] = [:]
    /// The day grid as the index knew it. `gridBuilt` tells a grid that does
    /// not exist (a week on top, or no record) from one not built yet.
    var gridBuilt = false
    var grid: HistoryDayGrid?
    /// What the whole record says about its days, as the index knew them.
    var record: HistoryRecord?
    /// Each place's seconds by category, by place id, with today left out.
    var categories: [String: [WorkType: TimeInterval]] = [:]
}

extension SessionStore {
    /// Monday-first, so weeks in History are Monday to Sunday. Read each
    /// time, so a Mac that changes time zone is not held to the old one.
    static var historyCalendar: Calendar { HistoryTreeBuilder.calendar(.current) }

    /// The one calendar Review, Insights, the story, History and its search
    /// work their periods out in: Gregorian in the Mac's zone, weeks from
    /// Monday, so every period matches its Gregorian title.
    var periodCalendar: Calendar { (periodCalendarBase ?? .current).forPeriods }

    /// The top of History's tree for the current record and today.
    func historyTop() -> HistoryTop {
        tree().top
    }

    /// The rows under a place, or the root rows for nil. Cached until the
    /// archive changes; rows holding today are brought up to the live
    /// figures on every read, the rest are returned as cached.
    func historyRows(under parent: HistoryPlace?) -> [HistoryRow] {
        let calendar = periodCalendar
        var state = tree()
        let key = parent?.id ?? "root"
        let rows: [HistoryRow]
        if let cached = state.rows[key] {
            rows = cached
        } else {
            historyTreeComputeCount &+= 1
            rows = HistoryTreeBuilder.rows(under: parent, top: state.top, byDate: state.byDate, calendar: calendar)
            state.rows[key] = rows
            historyTreeCache = state
        }
        return HistoryTreeBuilder.patching(rows, byDate: state.byDate, cachedToday: state.cachedToday,
                                           live: liveToday(calendar), calendar: calendar)
    }

    /// The headline's figures for the top period, live for today.
    func historySummary() -> HistorySummary {
        historySummary(for: nil)
    }

    /// A place's figures and its best child, or the top period's for nil.
    /// Cached as the rows are; today's change is laid over the cached total.
    func historySummary(for place: HistoryPlace?) -> HistorySummary {
        let calendar = periodCalendar
        var state = tree()
        let key = place?.id ?? "root"
        let top = place.map { HistoryTop(place: $0, firstDay: $0.span.start, today: state.top.today, calendar: calendar) } ?? state.top
        let summary: HistorySummary
        if let cached = state.summaries[key] {
            summary = cached
        } else {
            historyTreeComputeCount &+= 1
            summary = HistoryTreeBuilder.summary(top: top, byDate: state.byDate, calendar: calendar)
            state.summaries[key] = summary
            historyTreeCache = state
        }
        return HistoryTreeBuilder.patching(summary, top: top, byDate: state.byDate, cachedToday: state.cachedToday,
                                           live: liveToday(calendar), calendar: calendar)
    }

    /// The `level` period inside a span with the most focus, live for today:
    /// any range's best day, week or month, from the same day index as the rows.
    func historyBest(_ level: HistoryLevel, in span: DateInterval) -> (place: HistoryPlace, focused: TimeInterval)? {
        let calendar = periodCalendar
        return HistoryTreeBuilder.best(level, in: span, byDate: tree().byDate, live: liveToday(calendar),
                                       calendar: calendar)
    }

    /// A place's focus by category, largest first, live for today. Read from
    /// the same day index as the rows, so a card's split and its figure agree.
    /// The days are walked once per archive state, today left out; today's
    /// live figures are added on each read.
    func historyCategories(for place: HistoryPlace) -> [WorkTypeShare] {
        let calendar = periodCalendar
        var state = tree()
        let today = state.top.today
        var seconds: [WorkType: TimeInterval]
        if let cached = state.categories[place.id] {
            seconds = cached
        } else {
            historyTreeComputeCount &+= 1
            seconds = [:]
            var cursor = calendar.startOfDay(for: place.span.start)
            while cursor < place.span.end {
                if cursor != today { Self.add(state.byDate[cursor], to: &seconds) }
                cursor = HistoryTreeBuilder.dayAfter(cursor, calendar: calendar)
            }
            state.categories[place.id] = seconds
            historyTreeCache = state
        }
        if calendar.startOfDay(for: place.span.start) <= today, today < place.span.end {
            Self.add(liveToday(calendar) ?? state.byDate[today], to: &seconds)
        }
        return WorkTypeShare.shares(from: seconds)
    }

    /// A place's category split as the bar parts its row draws; the same
    /// figures as `historyCategories(for:)`.
    func historySplit(for place: HistoryPlace) -> [HistorySplitPart] {
        HistorySplit.parts(historyCategories(for: place))
    }

    /// The day grid of the whole record, live for today. Built once per
    /// archive state; a running session only redraws today's cell.
    func historyDayGrid() -> HistoryDayGrid? {
        let calendar = periodCalendar
        var state = tree()
        if !state.gridBuilt {
            historyTreeComputeCount &+= 1
            state.grid = HistoryDayGridBuilder.grid(top: state.top, byDate: state.byDate, calendar: calendar)
            state.gridBuilt = true
            historyTreeCache = state
        }
        guard let grid = state.grid, let live = liveToday(calendar), live != state.cachedToday else { return state.grid }
        return HistoryDayGridBuilder.patching(grid, live: live, today: state.top.today, calendar: calendar)
    }

    /// What stands out about each root row, by place id, live for today. The
    /// record the rows are judged against is walked once per archive state;
    /// each read is one pass over the patched rows.
    func historyRowFacts() -> [String: HistoryRowFacts] {
        let calendar = periodCalendar
        // Before `tree()`: reading the rows writes the cache this one reads back.
        let rows = historyRows(under: nil)
        var state = tree()
        let record: HistoryRecord
        if let cached = state.record {
            record = cached
        } else {
            historyTreeComputeCount &+= 1
            record = HistoryRecord.of(byDate: state.byDate)
            state.record = record
            historyTreeCache = state
        }
        return HistoryRowFactsBuilder.facts(
            rows: rows, top: state.top,
            record: record.patched(live: liveToday(calendar), cachedToday: state.cachedToday, calendar: calendar),
            calendar: calendar)
    }

    private static func add(_ day: HistoryDay?, to seconds: inout [WorkType: TimeInterval]) {
        for (type, value) in day?.focusByWorkType ?? [:] { seconds[type, default: 0] += value }
    }

    private func liveToday(_ calendar: Calendar) -> HistoryDay? {
        let today = calendar.startOfDay(for: now())
        return historyDays.first { calendar.isDate($0.date, inSameDayAs: today) }
    }

    private func tree() -> HistoryTreeCache {
        let calendar = periodCalendar
        let key = JournalKey(evidence: evidenceRevision, indexGeneration: historyIndexGeneration,
                             dayCount: historyDays.count, oldest: historyDays.last?.date)
        let today = calendar.startOfDay(for: now())
        if let cached = historyTreeCache, cached.key == key, cached.top.today == today { return cached }
        historyTreeComputeCount &+= 1
        let byDate = HistoryTreeBuilder.index(historyDays, calendar: calendar)
        let fresh = HistoryTreeCache(key: key,
                                     top: HistoryTreeBuilder.top(days: historyDays, today: now(), calendar: calendar),
                                     byDate: byDate, cachedToday: byDate[today])
        historyTreeCache = fresh
        return fresh
    }
}
