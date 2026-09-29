import Foundation

/// A month in History's journal: its figures, and one focus total for each
/// of its calendar days, for the thin bars under its name.
struct JournalMonth: Identifiable, Equatable {
    let start: Date
    let focused: TimeInterval
    let tracked: TimeInterval
    let focusedDays: Int
    /// Focused seconds per calendar day, the 1st first.
    let dailyFocus: [TimeInterval]

    var id: Date { start }
    var averagePerFocusedDay: TimeInterval { focusedDays > 0 ? focused / Double(focusedDays) : 0 }
}

/// A day the journal lists under its own header. While History is searched,
/// `threads` holds the sessions that matched; nil lists every session.
struct JournalDay: Identifiable, Equatable {
    let date: Date
    let focused: TimeInterval
    let tracked: TimeInterval
    let sessions: Int
    var threads: Set<UUID>? = nil

    var id: Date { date }
    /// At the Mac, but no session: the journal says so in one line, above
    /// any break the day recorded.
    var isAppUseOnly: Bool { sessions == 0 && focused == 0 && tracked > 0 }
}

/// Days in a row with nothing recorded, inside one month, read as one line.
struct JournalQuiet: Identifiable, Equatable {
    let first: Date
    let last: Date

    var id: Date { last }
    var isSingleDay: Bool { first == last }
}

enum JournalEntry: Identifiable, Equatable {
    case month(JournalMonth)
    case day(JournalDay)
    case quiet(JournalQuiet)

    var id: String {
        switch self {
        case .month(let month): return Self.monthID(month.start)
        case .day(let day): return Self.dayID(day.date)
        case .quiet(let quiet): return "quiet-\(Int(quiet.last.timeIntervalSince1970))"
        }
    }

    static func monthID(_ start: Date) -> String { "month-\(Int(start.timeIntervalSince1970))" }
    static func dayID(_ date: Date) -> String { "day-\(Int(date.timeIntervalSince1970))" }
}

/// What History's rail describes: a month, a day, or one session on a day.
/// A session is its thread on that day, as it is one card in the story.
enum HistorySelection: Hashable {
    case month(Date)
    case day(Date)
    case session(thread: UUID, day: Date)

    /// The day a day or a session belongs to; nil for a month.
    var day: Date? {
        switch self {
        case .month: return nil
        case .day(let day), .session(_, let day): return day
        }
    }

    func monthStart(calendar: Calendar = .current) -> Date {
        let date: Date
        switch self {
        case .month(let start): date = start
        case .day(let day), .session(_, let day): date = day
        }
        return calendar.dateInterval(of: .month, for: date)?.start ?? date
    }
}

/// Builds the journal from History's day index. Pure, with no store and no
/// clock, so the checks can hand it any archive and any today.
enum HistoryJournalBuilder {
    /// Newest first, from today back to the first recorded day and no further.
    /// Today always has its own row; any other day without focus, app use, a
    /// session or a recorded break joins the quiet run it sits in.
    static func entries(days: [HistoryDay], today: Date,
                        calendar: Calendar = .current) -> [JournalEntry] {
        let today = calendar.startOfDay(for: today)
        let byDate = index(days, calendar: calendar)
        let oldest = min(byDate.keys.min() ?? today, today)
        var result: [JournalEntry] = []
        var quiet: (newest: Date, oldest: Date)?
        func flushQuiet() {
            if let run = quiet { result.append(.quiet(JournalQuiet(first: run.oldest, last: run.newest))) }
            quiet = nil
        }
        var openMonth: Date?
        var cursor = today
        while cursor >= oldest {
            let monthStart = calendar.dateInterval(of: .month, for: cursor)?.start ?? cursor
            if monthStart != openMonth {
                flushQuiet()
                result.append(.month(month(starting: monthStart, byDate: byDate, calendar: calendar)))
                openMonth = monthStart
            }
            let row = byDate[cursor]
            if cursor == today || row.map(hasEvidence) == true {
                flushQuiet()
                result.append(.day(JournalDay(date: cursor, focused: row?.focused ?? 0,
                                              tracked: row?.tracked ?? 0, sessions: row?.sessions ?? 0)))
            } else {
                quiet = (quiet?.newest ?? cursor, cursor)
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        flushQuiet()
        return result
    }

    /// Search results as a journal: only the months and days holding a match,
    /// each totalling its matches, each day narrowed to the sessions that
    /// matched. `hits` arrive newest first, as `historySearchHits` lists them.
    /// A break is not a session and its length is not focus, so a break hit
    /// adds nothing: no day, no month, no figure.
    static func entries(matching hits: [HistorySearchHit],
                        calendar: Calendar = .current) -> [JournalEntry] {
        let hits = hits.filter { $0.workType.countsAsFocus }
        var result: [JournalEntry] = []
        var openMonth: Date?
        var monthHits: [HistorySearchHit] = []
        func flushMonth() {
            guard let start = openMonth, !monthHits.isEmpty else { return }
            var worked: [Date: TimeInterval] = [:]
            var threads: [Date: Set<UUID>] = [:]
            var order: [Date] = []
            for hit in monthHits {
                let day = calendar.startOfDay(for: hit.day)
                if worked[day] == nil { order.append(day) }
                worked[day, default: 0] += hit.worked
                threads[day, default: []].insert(hit.threadID)
            }
            let count = calendar.range(of: .day, in: .month, for: start)?.count ?? 31
            let daily = (0..<count).map { offset -> TimeInterval in
                guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return 0 }
                return worked[date] ?? 0
            }
            result.append(.month(JournalMonth(start: start, focused: daily.reduce(0, +), tracked: 0,
                                              focusedDays: order.count, dailyFocus: daily)))
            for day in order {
                result.append(.day(JournalDay(date: day, focused: worked[day] ?? 0, tracked: 0,
                                              sessions: threads[day]?.count ?? 0,
                                              threads: threads[day] ?? [])))
            }
        }
        for hit in hits {
            let start = calendar.dateInterval(of: .month, for: hit.day)?.start ?? hit.day
            if start != openMonth {
                flushMonth()
                openMonth = start
                monthHits = []
            }
            monthHits.append(hit)
        }
        flushMonth()
        return result
    }

    /// Today's row and its month, brought up to the live figures. The rest of
    /// the journal stays cached; only today moves while a session runs.
    static func patching(_ entries: [JournalEntry], today live: HistoryDay?,
                         calendar: Calendar = .current) -> [JournalEntry] {
        guard let live else { return entries }
        let day = calendar.startOfDay(for: live.date)
        guard let dayIndex = entries.firstIndex(where: {
            if case .day(let row) = $0 { return row.date == day }
            return false
        }), case .day(let old) = entries[dayIndex] else { return entries }
        var patched = entries
        patched[dayIndex] = .day(JournalDay(date: day, focused: live.focused,
                                            tracked: live.tracked, sessions: live.sessions))
        // A day's month is the nearest header above it.
        if let monthIndex = entries[..<dayIndex].lastIndex(where: {
            if case .month = $0 { return true }
            return false
        }), case .month(let month) = entries[monthIndex] {
            var daily = month.dailyFocus
            let offset = calendar.dateComponents([.day], from: month.start, to: day).day ?? 0
            if daily.indices.contains(offset) { daily[offset] = live.focused }
            patched[monthIndex] = .month(JournalMonth(
                start: month.start, focused: daily.reduce(0, +),
                tracked: month.tracked - old.tracked + live.tracked,
                focusedDays: daily.filter { $0 > 0 }.count, dailyFocus: daily))
        }
        return patched
    }

    /// The row ↑ or ↓ lands on. Months, days and sessions are stops in
    /// reading order; quiet lines and breaks are not. `threads` lists a day's
    /// sessions in the order its rows show them. It is only asked about the
    /// day being left and the day being entered, never the whole journal.
    static func step(from current: HistorySelection, by delta: Int,
                     entries: [JournalEntry], threads: (Date) -> [UUID]) -> HistorySelection {
        guard delta != 0 else { return current }
        let stops: [HistorySelection] = entries.compactMap {
            switch $0 {
            case .month(let month): return .month(month.start)
            case .day(let day): return .day(day.date)
            case .quiet: return nil
            }
        }
        if case .session(let thread, let day) = current {
            let list = threads(day)
            if let index = list.firstIndex(of: thread) {
                let next = index + delta
                if list.indices.contains(next) { return .session(thread: list[next], day: day) }
                if next < 0 { return .day(day) }
            }
            return neighbour(of: .day(day), in: stops, forward: true, threads: threads) ?? current
        }
        if delta > 0, case .day(let day) = current, let first = threads(day).first {
            return .session(thread: first, day: day)
        }
        return neighbour(of: current, in: stops, forward: delta > 0, threads: threads) ?? current
    }

    private static func neighbour(of stop: HistorySelection, in stops: [HistorySelection],
                                  forward: Bool, threads: (Date) -> [UUID]) -> HistorySelection? {
        guard let index = stops.firstIndex(of: stop) else { return stops.first }
        let next = index + (forward ? 1 : -1)
        guard stops.indices.contains(next) else { return nil }
        // Moving up onto a day lands on its last session: the row just above.
        if !forward, case .day(let day) = stops[next], let last = threads(day).last {
            return .session(thread: last, day: day)
        }
        return stops[next]
    }

    /// Jump to date: a day with its own row is selected; a quiet day selects
    /// its month, since it has no row to select.
    static func selection(forJump date: Date, in entries: [JournalEntry],
                          calendar: Calendar = .current) -> HistorySelection {
        let day = calendar.startOfDay(for: date)
        let listed = entries.contains { $0.id == JournalEntry.dayID(day) }
        return listed ? .day(day) : .month(calendar.dateInterval(of: .month, for: day)?.start ?? day)
    }

    /// The row to scroll to for a selection: its day's header, or its month's.
    static func anchorID(for selection: HistorySelection, in entries: [JournalEntry],
                         calendar: Calendar = .current) -> String? {
        let wanted = selection.day.map { JournalEntry.dayID(calendar.startOfDay(for: $0)) }
            ?? JournalEntry.monthID(selection.monthStart(calendar: calendar))
        return entries.contains { $0.id == wanted } ? wanted : nil
    }

    /// One month's figures from the day index, whether or not it is listed.
    static func month(starting start: Date, days: [HistoryDay],
                      calendar: Calendar = .current) -> JournalMonth {
        month(starting: start, byDate: index(days, calendar: calendar), calendar: calendar)
    }

    /// A journal day's rows from its projection, newest first, narrowed to
    /// `only` while History is searched. Breaks never match a search.
    static func rows(_ projection: StoryDayProjection, only: Set<UUID>?) -> [DayEntry] {
        projection.sessions
            .filter { entry in
                guard let only else { return true }
                if case .session(let session) = entry { return only.contains(session.threadID) }
                return false
            }
            .sorted { $0.start > $1.start }
    }

    private static func month(starting start: Date, byDate: [Date: HistoryDay],
                              calendar: Calendar) -> JournalMonth {
        let count = calendar.range(of: .day, in: .month, for: start)?.count ?? 31
        var daily: [TimeInterval] = []
        var tracked: TimeInterval = 0
        for offset in 0..<count {
            let row = calendar.date(byAdding: .day, value: offset, to: start).flatMap { byDate[$0] }
            daily.append(row?.focused ?? 0)
            tracked += row?.tracked ?? 0
        }
        return JournalMonth(start: start, focused: daily.reduce(0, +), tracked: tracked,
                            focusedDays: daily.filter { $0 > 0 }.count, dailyFocus: daily)
    }

    private static func index(_ days: [HistoryDay], calendar: Calendar) -> [Date: HistoryDay] {
        var byDate: [Date: HistoryDay] = [:]
        for day in days { byDate[calendar.startOfDay(for: day.date)] = day }
        return byDate
    }

    /// Break records add a work type but never focus or a session, so a day
    /// holding only a recorded break still has something to show.
    private static func hasEvidence(_ day: HistoryDay) -> Bool {
        day.focused > 0 || day.tracked > 0 || day.sessions > 0 || !day.workTypes.isEmpty
    }
}

struct JournalKey: Equatable {
    let evidence: SessionStore.EvidenceRevision
    /// Bumps on every full rebuild of `historyDays`, which can lag the
    /// evidence revision; the cache must not settle on days from before it.
    let indexGeneration: Int
    let dayCount: Int
    let oldest: Date?
}

/// A search's journal holds while the search and the archive behind it do.
struct SearchJournalKey: Equatable {
    let filter: HistoryFilter
    let evidence: SessionStore.EvidenceRevision
    let indexGeneration: Int
}

extension SessionStore {
    /// The journal History lists. Cached until the archive behind it changes;
    /// while a session runs, only today's row and its month are brought up
    /// to date. A search builds its own narrowed journal from the matches,
    /// cached the same way until the search or the archive changes.
    func historyJournal() -> [JournalEntry] {
        let calendar = Calendar.current
        if historyFilter.isActive {
            let key = SearchJournalKey(filter: historyFilter, evidence: evidenceRevision,
                                       indexGeneration: historyIndexGeneration)
            if let cached = searchJournalCache, cached.key == key { return cached.entries }
            searchJournalComputeCount &+= 1
            let entries = HistoryJournalBuilder.entries(matching: historySearchHits(limit: .max), calendar: calendar)
            searchJournalCache = (key, entries)
            return entries
        }
        let key = JournalKey(evidence: evidenceRevision, indexGeneration: historyIndexGeneration,
                             dayCount: historyDays.count,
                             oldest: historyDays.last?.date)
        let entries: [JournalEntry]
        if let cached = journalCache, cached.key == key {
            entries = cached.entries
        } else {
            journalComputeCount &+= 1
            entries = HistoryJournalBuilder.entries(days: historyDays, today: now(), calendar: calendar)
            journalCache = (key, entries)
        }
        return HistoryJournalBuilder.patching(entries, today: historyDays.first, calendar: calendar)
    }

    /// A journal day's rows, in the order the journal shows them.
    func journalRows(on day: Date, only: Set<UUID>?) -> [DayEntry] {
        HistoryJournalBuilder.rows(storyDayProjection(on: day), only: only)
    }

    /// The sessions a journal day lists, as ↑/↓ walk them.
    func journalThreads(on day: Date, only: Set<UUID>?) -> [UUID] {
        journalRows(on: day, only: only).compactMap { entry in
            if case .session(let session) = entry { return session.threadID }
            return nil
        }
    }

    /// The session a selection names, if that day still has it.
    func journalSession(thread: UUID, on day: Date) -> DaySession? {
        for entry in storyDayProjection(on: day).sessions {
            if case .session(let session) = entry, session.threadID == thread { return session }
        }
        return nil
    }

    /// The first note saved against any stretch of the session, trimmed.
    func journalNote(for session: DaySession) -> String? {
        for id in session.recordIDs {
            let note = (metadataArchive.metadata(for: id)?.note ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty { return note }
        }
        return nil
    }
}
