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
            if let future = askStillToCome(range) { return future }
            return words.map { askMatchingTotals(range, words: $0) } ?? askTotals(range)
        case let .bestHours(range):
            return askStillToCome(range) ?? askBestHours(range)
        case let .findSessions(words, range):
            return askStillToCome(range) ?? askSessions(range, words: words)
        case let .appTime(range, app):
            return askStillToCome(range) ?? askAppTime(range, app: app)
        case let .compare(first, second, words):
            return askStillToCome(first) ?? askStillToCome(second) ?? askCompare(first, second, words: words)
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

    /// What a lookup says about a period that begins after today, which has
    /// nothing to count yet; nil for any other.
    private func askStillToCome(_ range: AskRange) -> String? {
        askInterval(range).start > periodCalendar.startOfDay(for: now()) ? AskFacts.stillToCome(range) : nil
    }

    // MARK: - Focus totals

    /// History's headline for the range: its total, sessions and focused days.
    private func askSummary(_ range: AskRange) -> HistorySummary {
        historySummary(for: range.level.map { HistoryPlace(level: $0, span: askInterval(range)) })
    }

    private func askTotals(_ range: AskRange) -> String {
        let today = periodCalendar.startOfDay(for: now())
        let interval = askInterval(range)
        let summary = askSummary(range)
        var totals = AskTotals(dates: askDates(range), focused: summary.focused, sessions: summary.sessions,
                               focusedDays: summary.focusedDays)
        if range.isOneDay {
            totals.firstStart = askFirstStart(range)
        } else {
            // A day is its own best and has no breakdown. A longer range
            // names its best day, and its best week and month when it holds
            // them, whatever unit History's headline happens to pick: asked
            // for the best day of the year, the model was handed a month.
            let units: [HistoryLevel] = range.level == .week ? [.day]
                : range.level == .month ? [.day, .week] : [.day, .week, .month]
            totals.best = units.compactMap { unit in
                historyBest(unit, in: interval).map { best in
                    let current = best.place.span.holds(today)
                    let label = askLabel(best.place)
                    let now = unit == .day ? "today" : "this \(unit.spokenName)"
                    return AskBest(unit: unit.spokenName, label: current ? "\(now) (\(label))" : label,
                                   focused: best.focused, isCurrent: current)
                }
            }
            // Rows are newest first in History; here they read oldest first, and
            // run from the first recorded day to today, not from the start of the
            // period, which may be days before anything was recorded.
            let first = historyTop().firstDay
            let place = range.level.map { HistoryPlace(level: $0, span: interval) }
            let rows = historyRows(under: place).filter { $0.place.start <= today && $0.place.span.end > first }
            if let level = rows.first?.place.level {
                totals.parts = (level.spokenName, rows.reversed().map { (label: askLabel($0.place), focused: $0.focused) })
            }
        }
        totals.longest = askLongest(askHits(matching: nil, in: range))
        return AskFacts.focusTotals(range, words: nil, totals)
    }

    private func askMatchingTotals(_ range: AskRange, words: String) -> String {
        let clips = askHits(matching: HistoryFilter(query: words), in: range).filter { $0.hit.workType.countsAsFocus }
        var totals = AskTotals(dates: askDates(range), focused: clips.reduce(0) { $0 + $1.worked },
                               sessions: Set(clips.map(\.hit.threadID)).count,
                               focusedDays: Set(clips.flatMap(\.days)).count)
        totals.longest = askLongest(clips)
        // Asked how long Safari was used, the model searched for the word
        // and gave the time of the sessions Safari was used in (probe,
        // 2026-10-10), so words that name an app bring the app's own time.
        totals.app = askApp(words, among: historySortedUsage().uniqueUse(within: [askInterval(range)]))
            .map { (name: $0.name, total: $0.total) }
        return AskFacts.focusTotals(range, words: words, totals, sessionRunning: askSessionIsMissed(range))
    }

    /// When the first session of a day began: a saved one, or the one
    /// running now, which is saved only when it ends. One begun the night
    /// before began, as far as this day goes, at midnight.
    private func askFirstStart(_ range: AskRange) -> String? {
        let interval = askInterval(range)
        var starts = askHits(matching: nil, in: range).flatMap(\.spans).map(\.start)
        if engine.state != .idle, engine.sessionStartDate < interval.end, now() > interval.start {
            starts.append(max(engine.sessionStartDate, interval.start))
        }
        return starts.min().map(askTime)
    }

    /// The finished session with the most work inside the range.
    private func askLongest(_ clips: [AskClip]) -> (name: String, day: String, worked: TimeInterval)? {
        clips.filter { $0.hit.workType.countsAsFocus }.max { $0.worked < $1.worked }.map {
            (name: $0.hit.name, day: askDay($0.days.min() ?? $0.hit.day), worked: $0.worked)
        }
    }

    // MARK: - Comparison

    private func askCompare(_ first: AskRange, _ second: AskRange, words: String?) -> String {
        let today = periodCalendar.startOfDay(for: now())
        func side(_ range: AskRange) -> AskSide {
            let focused = words.map { words in
                askHits(matching: HistoryFilter(query: words), in: range).filter { $0.hit.workType.countsAsFocus }
                    .reduce(0) { $0 + $1.worked }
            } ?? askSummary(range).focused
            return AskSide(range: range, focused: focused, isCurrent: askInterval(range).holds(today),
                           dates: askDates(range))
        }
        return AskFacts.comparison(side(first), side(second), words: words,
                                   sessionRunning: askSessionIsMissed(first) || askSessionIsMissed(second))
    }

    // MARK: - Best hours

    private func askBestHours(_ range: AskRange) -> String {
        let calendar = periodCalendar
        let interval = askInterval(range)
        let reading: InsightReading
        let span: String
        if interval.duration <= 86_400 * 1.5 {
            reading = insightReading(scope: .day, anchoredAt: interval.start, limit: 1, calendar: calendar)
            span = range == .today ? "Today" : range == .yesterday ? "Yesterday" : range.title
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
            span = "Over the \(weeks == 1 ? "week" : "\(weeks) weeks") to \(askDay(readTo, weekday: false))"
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
        let running = askSessionIsMissed(range)
        guard let match = askApp(query, among: use) else {
            return AskFacts.appTime(range, app: (query: query, name: nil, total: 0, sessions: 0), top: [],
                                    sessionRunning: running)
        }
        // A session counts when the app was in front for `minimumUse` inside
        // the part of the session that falls in the range, as History's app
        // filter decides it, not when the app merely overlaps the session.
        let used = askHits(matching: HistoryFilter(appBundleID: match.id), in: range, needingWork: false).filter {
            (sorted.uniqueUse(within: $0.spans)[match.id]?.total ?? 0) >= HistoryAppLens.minimumUse
        }
        let sessions = Set(used.map(\.hit.threadID)).count
        return AskFacts.appTime(range, app: (query: query, name: match.name, total: match.total, sessions: sessions),
                                top: [], sessionRunning: running)
    }

    /// The app a name means among those used: "safari." finds Safari, as
    /// case, accents and full stops don't count. The one with the most use
    /// on a partial match; the first bundle ID on a tie.
    private func askApp(_ query: String, among use: [String: (name: String, total: TimeInterval, longest: TimeInterval)])
        -> (id: String, name: String, total: TimeInterval)? {
        let wanted = SearchWords.fold(query.replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines))
        var match: (id: String, name: String, total: TimeInterval)?
        for (id, name) in historyAppNames where !wanted.isEmpty && SearchWords.fold(name).contains(wanted) {
            guard let total = use[id]?.total else { continue }
            let better = match.map { total > $0.total || (total == $0.total && id < $0.id) } ?? true
            if better { match = (id: id, name: name, total: total) }
        }
        return match
    }
}
