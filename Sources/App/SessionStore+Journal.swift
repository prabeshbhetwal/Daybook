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
/// `threads` holds the sessions that matched, by thread, and the breaks that
/// matched, by record; nil lists every row.
struct JournalDay: Identifiable, Equatable {
    let date: Date
    let focused: TimeInterval
    let tracked: TimeInterval
    let sessions: Int
    var threads: Set<UUID>? = nil
    /// Breaks that matched a search. Always 0 outside one.
    var breaks = 0

    var id: Date { date }
    /// At the Mac, but no session: the journal says so in one line, above
    /// any break the day recorded.
    var isAppUseOnly: Bool { sessions == 0 && focused == 0 && tracked > 0 }
}

enum JournalEntry: Identifiable, Equatable {
    case month(JournalMonth)
    case day(JournalDay)

    var id: String {
        switch self {
        case .month(let month): return Self.monthID(month.start)
        case .day(let day): return Self.dayID(day.date)
        }
    }

    static func monthID(_ start: Date) -> String { "month-\(Int(start.timeIntervalSince1970))" }
    static func dayID(_ date: Date) -> String { "day-\(Int(date.timeIntervalSince1970))" }
}

/// The search's results as month and day figures, and a day's rows. Pure,
/// so the checks can hand it any hits.
enum HistoryJournalBuilder {
    /// Search results as a journal: only the months and days holding a match,
    /// each totalling its matches, each day narrowed to the sessions that
    /// matched. `hits` arrive newest first, as `historySearchHits` lists them.
    /// A break that matched lists as its row under its day, but it is not a
    /// session and its length is not focus: it adds no session and no figure.
    static func entries(matching hits: [HistorySearchHit],
                        calendar: Calendar = .current) -> [JournalEntry] {
        var result: [JournalEntry] = []
        var openMonth: Date?
        var monthHits: [HistorySearchHit] = []
        func flushMonth() {
            guard let start = openMonth, !monthHits.isEmpty else { return }
            var worked: [Date: TimeInterval] = [:]
            var sessions: [Date: Set<UUID>] = [:]
            var listed: [Date: Set<UUID>] = [:]
            var breaks: [Date: Int] = [:]
            var order: [Date] = []
            for hit in monthHits {
                let day = calendar.startOfDay(for: hit.day)
                if listed[day] == nil { order.append(day) }
                if hit.workType.countsAsFocus {
                    worked[day, default: 0] += hit.worked
                    sessions[day, default: []].insert(hit.threadID)
                    listed[day, default: []].insert(hit.threadID)
                } else {
                    breaks[day, default: 0] += 1
                    listed[day, default: []].formUnion(hit.recordIDs.isEmpty ? [hit.id] : hit.recordIDs)
                }
            }
            let count = calendar.range(of: .day, in: .month, for: start)?.count ?? 31
            let daily = (0..<count).map { offset -> TimeInterval in
                guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return 0 }
                return worked[date] ?? 0
            }
            result.append(.month(JournalMonth(start: start, focused: daily.reduce(0, +), tracked: 0,
                                              focusedDays: sessions.count, dailyFocus: daily)))
            for day in order {
                result.append(.day(JournalDay(date: day, focused: worked[day] ?? 0, tracked: 0,
                                              sessions: sessions[day]?.count ?? 0,
                                              threads: listed[day] ?? [],
                                              breaks: breaks[day] ?? 0)))
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
                switch entry {
                case .session(let session): return only.contains(session.threadID)
                case .rest(let rest): return only.contains(rest.id)
                }
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
    /// The days and sessions a search matched, newest first, cached until
    /// the search or the archive behind it changes. Empty when nothing is
    /// searched: the tree lists the record then.
    func historyJournal() -> [JournalEntry] {
        guard historyFilter.isActive else { return [] }
        let calendar = Calendar.current
        let key = SearchJournalKey(filter: historyFilter, evidence: evidenceRevision,
                                   indexGeneration: historyIndexGeneration)
        if let cached = searchJournalCache, cached.key == key { return cached.entries }
        searchJournalComputeCount &+= 1
        let entries = HistoryJournalBuilder.entries(matching: historySearchHits(limit: .max), calendar: calendar)
        searchJournalCache = (key, entries)
        return entries
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

    /// The one line of a session's notes its row shows: while History is
    /// searched, the first line holding a word of the search, so the row
    /// says why it matched; otherwise the first line of the note.
    func journalNoteLine(for session: DaySession) -> String? {
        let words = SearchWords.words(in: historyFilter.query)
        if !words.isEmpty {
            for id in session.recordIDs {
                let note = metadataArchive.metadata(for: id)?.note ?? ""
                if let line = note.split(whereSeparator: \.isNewline)
                    .map({ $0.trimmingCharacters(in: .whitespaces) })
                    .first(where: { line in words.contains { SearchWords.fold(line).contains($0) } }) {
                    return line
                }
            }
        }
        return journalNote(for: session).flatMap { $0.split(whereSeparator: \.isNewline).first.map(String.init) }
    }
}
