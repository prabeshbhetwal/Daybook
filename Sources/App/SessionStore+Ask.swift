import Foundation

/// Ask Daybook's lookups. Every figure is read through the store methods
/// History and Insights draw from, so an answer cannot differ from the
/// screen; `AskFacts` only words it. Nothing here writes: no file, no
/// preference, and not the search filter History is showing. The one change a
/// lookup makes is to History's in-memory day index, when it is behind.
extension SessionStore {
    func askLookup(_ request: AskRequest) -> String {
        askBringHistoryUpToDate()
        switch request {
        case let .focusTotals(range, words):
            return words.map { askMatchingTotals(range, words: $0) } ?? askTotals(range)
        case let .bestHours(range): return askBestHours(range)
        case let .findSessions(words, range): return askSessions(range, words: words)
        case let .appTime(range, app): return askAppTime(range, app: app)
        }
    }

    /// History's day index is built while History is open. The Ask sheet is
    /// not History, so a lookup brings the index up to date itself when the
    /// store says it is behind: a refresh pending, evidence that moved since
    /// the last build, or a session running, whose day grows by the second.
    /// It is the refresh History runs on opening, chosen by the same rule,
    /// and History stays hidden. Otherwise it does nothing.
    private func askBringHistoryUpToDate() {
        let revision = evidenceRevision
        let pending = reviewRefreshPending || reviewLiveTailRefreshPending
        guard pending || reviewEvidenceRevision != revision || engine.state != .idle else { return }
        refreshReview(rebuildingHistory: reviewRefreshPending
                      || reviewEvidenceRevision?.sameArchive(as: revision) != true)
    }

    // MARK: - Focus totals

    private func askTotals(_ range: AskRange) -> String {
        let today = periodCalendar.startOfDay(for: now())
        let place = range.level.map { HistoryPlace(level: $0, span: askInterval(range)) }
        let summary = historySummary(for: place)
        // One day is its own best and has no breakdown: neither is given.
        let singleDay = range == .today || range == .yesterday
        let best: (unit: String, label: String, focused: TimeInterval)? = singleDay ? nil : summary.best.map {
            (unit: $0.place.level.spokenName, label: askLabel($0.place), focused: $0.focused)
        }
        // Rows are newest first in History; here they read oldest first, and
        // run from the first recorded day to today, not from the start of the
        // period, which may be days before anything was recorded.
        var parts: (name: String, items: [(label: String, focused: TimeInterval)])?
        if !singleDay {
            let first = historyTop().firstDay
            let rows = historyRows(under: place).filter { $0.place.start <= today && $0.place.span.end > first }
            if let level = rows.first?.place.level {
                parts = (level.spokenName, rows.reversed().map { (label: askLabel($0.place), focused: $0.focused) })
            }
        }
        return AskFacts.focusTotals(range, words: nil, focused: summary.focused, sessions: summary.sessions,
                                    focusedDays: summary.focusedDays, best: best, parts: parts)
    }

    private func askMatchingTotals(_ range: AskRange, words: String) -> String {
        let clips = askHits(matching: HistoryFilter(query: words), in: range).filter { $0.hit.workType.countsAsFocus }
        return AskFacts.focusTotals(range, words: words, focused: clips.reduce(0) { $0 + $1.worked },
                                    sessions: Set(clips.map(\.hit.threadID)).count,
                                    focusedDays: Set(clips.flatMap(\.days)).count, best: nil, parts: nil,
                                    sessionRunning: askSessionIsMissed(range))
    }

    // MARK: - Sessions

    private func askSessions(_ range: AskRange, words: String) -> String {
        guard !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return AskFacts.needsWords }
        let found = askHits(matching: HistoryFilter(query: words), in: range)
        // Dated by the first day of the range the session has work on, so a
        // session begun last night is not listed under yesterday's date for today.
        let hits = found.prefix(10).map {
            (day: askText("EEE d MMM", $0.days.min() ?? $0.hit.day), name: $0.hit.name, worked: $0.worked,
             note: $0.hit.noteSnippet)
        }
        return AskFacts.sessions(range, words: words, hits: hits, matched: found.count,
                                 sessionRunning: askSessionIsMissed(range))
    }

    // MARK: - Best hours

    private func askBestHours(_ range: AskRange) -> String {
        let calendar = periodCalendar
        let interval = askInterval(range)
        let reading: InsightReading
        let span: String
        if interval.duration <= 86_400 * 1.5 {
            reading = insightReading(scope: .day, anchoredAt: interval.start, limit: 1, calendar: calendar)
            span = range == .yesterday ? "Yesterday" : "Today"
        } else {
            // Insights reads no further than today, so a range that runs on
            // past it is read to today.
            let last = min(calendar.startOfDay(for: now()),
                           calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.start)
            let firstWeek = calendar.dateInterval(of: .weekOfYear, for: interval.start)?.start ?? interval.start
            let days = max(0, calendar.dateComponents([.day], from: firstWeek, to: last).day ?? 0)
            let weeks = min(14, days / 7 + 1)
            reading = insightReading(scope: .week, anchoredAt: last, limit: weeks, calendar: calendar)
            // Insights reads whole weeks: to the Sunday that ends the week
            // holding `last`, or to today when that week is not over.
            let weekEnd = calendar.dateInterval(of: .weekOfYear, for: last)?.end ?? last
            let readTo = min(calendar.startOfDay(for: now()),
                             calendar.date(byAdding: .day, value: -1, to: weekEnd) ?? last)
            span = "Over the \(weeks == 1 ? "week" : "\(weeks) weeks") to \(askText("d MMM", readTo))"
        }
        return AskFacts.bestHours(range, span: span, window: reading.facts.bestWindow,
                                  strongest: reading.facts.bestWindowPhrase)
    }

    // MARK: - App time

    private func askAppTime(_ range: AskRange, app: String?) -> String {
        let sorted = historySortedUsage()
        let use = sorted.uniqueUse(within: [askInterval(range)])
        guard let query = app else {
            // AskFacts keeps the top five.
            var ranked: [(name: String, total: TimeInterval)] = []
            for (id, entry) in use { ranked.append((name: historyAppName(for: id), total: entry.total)) }
            ranked.sort { $0.total == $1.total ? $0.name < $1.name : $0.total > $1.total }
            return AskFacts.appTime(range, app: nil, top: ranked)
        }
        // "safari." finds Safari: case, accents and full stops don't count.
        let wanted = SearchWords.fold(query.replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines))
        // The app with the most use in the range; the first bundle ID on a tie.
        var match: (id: String, name: String, total: TimeInterval)?
        for (id, name) in historyAppNames where !wanted.isEmpty && SearchWords.fold(name).contains(wanted) {
            guard let total = use[id]?.total else { continue }
            let better = match.map { total > $0.total || (total == $0.total && id < $0.id) } ?? true
            if better { match = (id: id, name: name, total: total) }
        }
        let running = askSessionIsMissed(range)
        guard let match else {
            return AskFacts.appTime(range, app: (query: query, name: nil, total: 0, sessions: 0), top: [],
                                    sessionRunning: running)
        }
        // A session counts when the app was in front for `minimumUse` inside
        // the part of the session that falls in the range, as History's app
        // filter decides it, not when the app merely overlaps the session.
        let used = askHits(matching: HistoryFilter(appBundleID: match.id), in: range).filter {
            (sorted.uniqueUse(within: $0.spans)[match.id]?.total ?? 0) >= HistoryAppLens.minimumUse
        }
        let sessions = Set(used.map(\.hit.threadID)).count
        return AskFacts.appTime(range, app: (query: query, name: match.name, total: match.total, sessions: sessions),
                                top: [], sessionRunning: running)
    }

    // MARK: - Shared

    /// Whether a search over the range misses a session still going: one is
    /// in progress, and the range holds today. A search reads saved sessions,
    /// and the running one is saved when it ends.
    private func askSessionIsMissed(_ range: AskRange) -> Bool {
        guard engine.state != .idle else { return false }
        let today = periodCalendar.startOfDay(for: now())
        let interval = askInterval(range)
        return interval.start <= today && today < interval.end
    }

    private func askInterval(_ range: AskRange) -> DateInterval {
        range.interval(now: now(), firstDay: historyTop().firstDay, calendar: periodCalendar)
    }

    /// A search hit's part of a range: the work of its records that falls
    /// inside it, the days that work lands on, and the stretches of the
    /// records inside the range.
    private struct AskClip {
        let hit: HistorySearchHit
        let worked: TimeInterval
        let days: Set<Date>
        let spans: [DateInterval]
    }

    /// The sessions a search finds that touch the range, each clipped to it:
    /// one that crosses midnight is found by the part inside, not by the day
    /// it began, and brings only that part's work. The range is half-open:
    /// `DateInterval.contains` takes its end, which would count Monday's
    /// session in last week. The search is not capped: it lists newest first
    /// and stops at its limit before the range is applied, so any cap would
    /// drop the oldest sessions from a long range's count. A session with no
    /// work inside the range, paused all through it, is not a hit for it.
    private func askHits(matching filter: HistoryFilter, in range: AskRange) -> [AskClip] {
        let interval = askInterval(range)
        let records = Dictionary(engine.archive.records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return historySearchHits(matching: filter, limit: .max).compactMap { hit -> AskClip? in
            let inside = hit.recordIDs.compactMap { records[$0] }.filter { askTouches($0, interval) }
            let worked = inside.reduce(0) { $0 + $1.workSeconds(in: (interval.start, interval.end)) }
            guard worked > 0 else { return nil }
            return AskClip(hit: hit, worked: worked,
                           days: inside.reduce(into: Set<Date>()) { $0.formUnion(askDays(of: $1, in: interval)) },
                           spans: inside.map {
                               let start = max($0.start, interval.start)
                               return DateInterval(start: start, end: max(start, min($0.end, interval.end)))
                           })
        }
    }

    /// Whether a record overlaps the range; one with no length, by the
    /// instant it happened, as `workSeconds(in:)` places it.
    private func askTouches(_ record: SessionRecord, _ interval: DateInterval) -> Bool {
        record.span > 0 ? record.start < interval.end && record.end > interval.start
                        : record.end >= interval.start && record.end < interval.end
    }

    /// The days of the range that hold some of a record's work, as History
    /// attributes it to days.
    private func askDays(of record: SessionRecord, in interval: DateInterval) -> Set<Date> {
        let calendar = periodCalendar
        var days: Set<Date> = []
        var day = calendar.startOfDay(for: max(record.start, interval.start))
        let last = min(record.end, interval.end)
        for _ in 0..<HistoryStats.maximumCalendarDaysPerRecord {
            if record.workSeconds(on: day, calendar: calendar) > 0 { days.insert(calendar.startOfDay(for: day)) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next < last else { break }
            day = next
        }
        return days
    }

    /// A date named in the calendar the period was worked out in.
    private func askText(_ format: String, _ date: Date) -> String {
        DateFormats.australian(format, in: periodCalendar.timeZone).string(from: date)
    }

    /// A History row's period: `Tue 14 Nov`, `13 Nov – 19 Nov`, `November 2023`, `2023`.
    private func askLabel(_ place: HistoryPlace) -> String {
        switch place.level {
        case .year: return askText("yyyy", place.start)
        case .month: return askText("MMMM yyyy", place.start)
        case .week:
            let last = periodCalendar.date(byAdding: .day, value: -1, to: place.span.end) ?? place.start
            return "\(askText("d MMM", place.start)) – \(askText("d MMM", last))"
        case .day: return askText("EEE d MMM", place.start)
        }
    }
}
