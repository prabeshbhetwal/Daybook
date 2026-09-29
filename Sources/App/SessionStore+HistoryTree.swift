import Foundation

extension SessionStore {
    /// Monday-first, so weeks in History are Monday to Sunday.
    static let historyCalendar = HistoryTreeBuilder.calendar(.current)

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
            rows = HistoryTreeBuilder.rows(under: parent, top: state.top, days: historyDays, calendar: calendar)
            state.rows[key] = rows
            historyTreeCache = state
        }
        return HistoryTreeBuilder.patching(rows, top: state.top, live: liveToday(calendar), days: historyDays,
                                           calendar: calendar)
    }

    /// The headline's figures for the top period, live for today.
    func historySummary() -> HistorySummary {
        HistoryTreeBuilder.summary(top: historyTop(), days: historyDays, calendar: Self.historyCalendar)
    }

    private func liveToday(_ calendar: Calendar) -> HistoryDay? {
        let today = calendar.startOfDay(for: now())
        return historyDays.first { calendar.isDate($0.date, inSameDayAs: today) }
    }

    private func tree() -> (key: JournalKey, top: HistoryTop, rows: [String: [HistoryRow]]) {
        let key = JournalKey(evidence: evidenceRevision, indexGeneration: historyIndexGeneration,
                             dayCount: historyDays.count, oldest: historyDays.last?.date)
        let today = Self.historyCalendar.startOfDay(for: now())
        if let cached = historyTreeCache, cached.key == key, cached.top.today == today { return cached }
        historyTreeComputeCount &+= 1
        let top = HistoryTreeBuilder.top(days: historyDays, today: now(), calendar: Self.historyCalendar)
        let fresh = (key, top, [String: [HistoryRow]]())
        historyTreeCache = fresh
        return fresh
    }
}
