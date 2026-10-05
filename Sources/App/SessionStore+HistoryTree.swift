import Foundation

/// What the store keeps of History's tree between archive changes. Rows and
/// summaries are built from `byDate` once; today's live figures are laid
/// over them on each read rather than rebuilt into them.
struct HistoryTreeCache {
    let key: JournalKey
    let top: HistoryTop
    let byDate: [Date: HistoryDay]
    /// Today as the index knew it, so a read can tell whether today moved.
    let cachedToday: HistoryDay?
    var rows: [String: [HistoryRow]] = [:]
    var summaries: [String: HistorySummary] = [:]
}

extension SessionStore {
    /// Monday-first, so weeks in History are Monday to Sunday. Read each
    /// time, so a Mac that changes time zone is not held to the old one.
    static var historyCalendar: Calendar { HistoryTreeBuilder.calendar(.current) }

    /// The top of History's tree for the current record and today.
    func historyTop() -> HistoryTop {
        tree().top
    }

    /// The rows under a place, or the root rows for nil. Cached until the
    /// archive changes; rows holding today are brought up to the live
    /// figures on every read, the rest are returned as cached.
    func historyRows(under parent: HistoryPlace?) -> [HistoryRow] {
        let calendar = Self.historyCalendar
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
        let calendar = Self.historyCalendar
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

    /// A place's focus by category, largest first, live for today. Read from
    /// the same day index as the rows, so a card's split and its figure agree.
    func historyCategories(for place: HistoryPlace) -> [WorkTypeShare] {
        let calendar = Self.historyCalendar
        let state = tree()
        let today = calendar.startOfDay(for: now())
        let live = liveToday(calendar)
        var seconds: [WorkType: TimeInterval] = [:]
        var cursor = calendar.startOfDay(for: place.span.start)
        while cursor < place.span.end {
            let day = cursor == today ? (live ?? state.byDate[cursor]) : state.byDate[cursor]
            for (type, value) in day?.focusByWorkType ?? [:] { seconds[type, default: 0] += value }
            cursor = HistoryTreeBuilder.dayAfter(cursor, calendar: calendar)
        }
        return WorkTypeShare.shares(from: seconds)
    }

    private func liveToday(_ calendar: Calendar) -> HistoryDay? {
        let today = calendar.startOfDay(for: now())
        return historyDays.first { calendar.isDate($0.date, inSameDayAs: today) }
    }

    private func tree() -> HistoryTreeCache {
        let calendar = Self.historyCalendar
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
