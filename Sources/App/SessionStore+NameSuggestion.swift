import Foundation

/// Name suggestions' store side: which unnamed sessions from today and
/// yesterday are offered, what the on-device model reads about one, and what
/// Name it and Keep as is leave behind. Days are `periodCalendar`'s.
extension SessionStore {
    private static let nameSuggestionMinimumWorked: TimeInterval = 600
    private static let nameHistoryDays = 60

    /// Today's then yesterday's ended, unnamed focus sessions with worked ≥ 600, not kept, newest first.
    /// A thread on both days, or twice on one, is offered once: from where it
    /// started, with all of its time on the two days. One that began before
    /// yesterday is not offered: its day is the day it started.
    func nameSuggestionTargets() -> [DaySession] {
        let days = suggestionDays()
        let kept = engine.store.nameSuggestionKept
        let began = Dictionary(engine.archive.records.map { ($0.id, $0.start) }, uniquingKeysWith: min)
        var threads: [UUID: DaySession] = [:]
        for day in [days.yesterday, days.today] {
            for case .session(let piece) in storyDayProjection(on: day, calendar: periodCalendar).sessions {
                threads[piece.threadID] = threads[piece.threadID].map { Self.joined($0, piece) } ?? piece
            }
        }
        return threads.values.filter {
            !$0.isRunning && $0.workType.countsAsFocus && $0.worked >= Self.nameSuggestionMinimumWorked
                && $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !kept.contains($0.threadID.uuidString)
                && !$0.recordIDs.contains { began[$0, default: days.yesterday] < days.yesterday }
        }.sorted { $0.start > $1.start }
    }

    /// What the rail asks again on: the session archive and the notes
    /// (`evidenceRevision`'s sessions, metadata and day), the corrections (a
    /// rename on a card), Keep as is, and the day. Cheap, because a body reads
    /// it on every tick. Not app use: the tracker checkpoints the usage
    /// archive every minute and on every refresh, so its revisions move
    /// without anything new to name.
    var nameSuggestionKey: Int {
        let evidence = evidenceRevision
        var hasher = Hasher()
        hasher.combine(evidence.sessions)
        hasher.combine(evidence.metadata)
        hasher.combine(evidence.day)
        hasher.combine(corrections.count)
        hasher.combine(engine.store.nameSuggestionKept)
        hasher.combine(periodCalendar.startOfDay(for: now()))
        return hasher.finalize()
    }

    /// The facts for the model, or nil when the session has neither app
    /// evidence nor a note.
    func nameFacts(for session: DaySession) -> NameFacts? {
        let apps = appUse(historySortedUsage(), within: session.spans)
            .sorted { ($0.value.total, $1.value.name) > ($1.value.total, $0.value.name) }
        let note = journalNote(for: session).map(Self.nameNote)
        guard !apps.isEmpty || note != nil else { return nil }
        let history = nameHistory()
        let candidates = NameCandidates.rank(
            appSeconds: apps.reduce(into: [:]) { $0[$1.key] = $1.value.total },
            workType: session.workType, history: history.entries)

        let zone = periodCalendar.timeZone
        let clock = DateFormats.australian("h:mm a", in: zone)
        let half = DateFormats.australian("a", in: zone)
        // "9:10–10:30 am", but "11:30 pm–12:40 am" across noon or midnight.
        let from = half.string(from: session.start) == half.string(from: session.end)
            ? DateFormats.australian("h:mm", in: zone).string(from: session.start)
            : clock.string(from: session.start)
        var lines = ["Session: \(DateFormats.australian("EEE d MMM", in: zone).string(from: session.start)), "
                     + "\(from)–\(clock.string(from: session.end)), \(DurationText.compact(session.worked)) focused, "
                     + "category \(session.workType.displayName)."]
        if !apps.isEmpty {
            lines.append("Apps: " + apps.map { "\($0.value.name) \(DurationText.compact($0.value.total))" }
                .joined(separator: ", ") + ".")
        }
        if let note { lines.append("Note: “\(note)”") }
        if !candidates.isEmpty { lines.append("Earlier names that fit:") }
        for (index, candidate) in candidates.enumerated() {
            let usual = candidate.usualApps.map { history.appNames[$0] ?? historyAppName(for: $0) }
            lines.append("\(index + 1). \(candidate.name) (usually \(usual.joined(separator: ", ")); "
                         + "\(candidate.usualWorkType.displayName))")
        }
        // The ranking is in the key: a rename elsewhere can tie or overturn it.
        let ranking = candidates.map { "\($0.name)=\($0.score)" }.joined(separator: ",")
        let sessionKey = "\(session.threadID)|\(session.end)|\(session.workType.id)|\(note ?? "")"
        return NameFacts(text: lines.joined(separator: "\n"), candidates: candidates,
                         appNames: apps.map(\.value.name),
                         sessionKey: sessionKey, cacheKey: "\(sessionKey)|\(ranking)")
    }

    /// "this morning's 1h 20m session", "yesterday evening's 45m session", "last night's 2h session",
    /// and "yesterday's 30m session" for one begun after midnight yesterday
    func nameSuggestionLead(for session: DaySession) -> String {
        // Half-open: a session begun on the stroke of midnight is today's.
        let yesterday = session.start < suggestionDays().today
        let words: String
        switch Self.timeOfDay(session.start, calendar: periodCalendar) {
        // Begun after midnight, 9 am's "tonight" was hours ago: last night's.
        // Begun after midnight yesterday, that night was two nights ago.
        case "night":
            let afterMidnight = periodCalendar.component(.hour, from: session.start) < 5
            words = yesterday && afterMidnight ? "yesterday's"
                : yesterday || afterMidnight ? "last night's" : "tonight's"
        case let part: words = yesterday ? "yesterday \(part)'s" : "this \(part)'s"
        }
        return "\(words) \(DurationText.compact(session.worked)) session"
    }

    /// The earlier names a fresh suggestion may match, once each ignoring
    /// case and accents, in their latest spelling, most recent first.
    func earlierSessionNames() -> [String] {
        var seen = Set<String>()
        return nameHistory().entries.sorted { $0.end > $1.end }
            .filter { seen.insert(SearchWords.fold($0.name)).inserted }
            .map(\.name)
    }

    /// Name it: an ordinary rename, so the Story offers Undo.
    @discardableResult
    func acceptNameSuggestion(_ name: String, for session: DaySession) -> Bool {
        renameSession(session, to: name)
    }

    /// Keep as is: the thread is not offered again. Threads with nothing
    /// ending since yesterday began can never be offered, so they are dropped.
    func keepSessionUnnamed(_ session: DaySession) {
        let since = suggestionDays().yesterday
        let recent = Set(engine.archive.records.filter { $0.end > since }.map(\.threadID.uuidString))
        var kept = engine.store.nameSuggestionKept.intersection(recent)
        kept.insert(session.threadID.uuidString)
        engine.store.nameSuggestionKept = kept
    }

    // MARK: - Helpers

    /// A note as one line of at most 200 characters, so a pasted page or a
    /// line break cannot pass for another line of the facts.
    private static func nameNote(_ note: String) -> String {
        String(note.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(200))
            .trimmingCharacters(in: .whitespaces)
    }

    private func suggestionDays() -> (yesterday: Date, today: Date) {
        let calendar = periodCalendar
        let today = calendar.startOfDay(for: now())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today).map { calendar.startOfDay(for: $0) }
        return (yesterday ?? today, today)
    }

    /// One thread's pieces as one session, from the earlier piece's start.
    private static func joined(_ a: DaySession, _ b: DaySession) -> DaySession {
        let (first, last) = a.start <= b.start ? (a, b) : (b, a)
        // A record across midnight is a piece of each day.
        let ids = first.recordIDs + last.recordIDs.filter { !first.recordIDs.contains($0) }
        return DaySession(id: first.id, threadID: first.threadID,
                          name: last.name.isEmpty ? first.name : last.name, workType: first.workType,
                          start: first.start, end: max(a.end, b.end), worked: a.worked + b.worked,
                          stretches: ids.count, spans: first.spans + last.spans, recordIDs: ids,
                          isRunning: a.isRunning || b.isRunning)
    }

    /// Apps in front for at least `HistoryAppLens.minimumUse` inside the spans.
    private func appUse(_ usage: SortedUsage, within spans: [DateInterval])
        -> [String: (name: String, total: TimeInterval, longest: TimeInterval)] {
        usage.uniqueUse(within: spans).filter { $0.value.total >= HistoryAppLens.minimumUse }
    }

    /// Named focus records that ended in the last 60 days: typed names and
    /// rule names, never generic auto names or names that spell a category.
    /// With the display name of every app they used.
    private func nameHistory() -> (entries: [NameHistoryEntry], appNames: [String: String]) {
        let calendar = periodCalendar
        guard let back = calendar.date(byAdding: .day, value: -Self.nameHistoryDays,
                                       to: calendar.startOfDay(for: now())) else { return ([], [:]) }
        let from = calendar.startOfDay(for: back)   // a day without a midnight lands the step on 01:00
        let rules = Set(engine.store.activityRules.map {
            SearchWords.fold($0.name.trimmingCharacters(in: .whitespacesAndNewlines))
        })
        let usage = historySortedUsage()
        var appNames: [String: String] = [:]
        let entries = engine.archive.records.compactMap { record -> NameHistoryEntry? in
            let name = record.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard record.end > from, !name.isEmpty, record.workType.countsAsFocus,
                  !record.isAuto || rules.contains(SearchWords.fold(name)),
                  SessionNaming.category(named: name) == nil else { return nil }
            let apps = appUse(usage, within: [DateInterval(start: record.start, end: max(record.start, record.end))])
            for (bundleID, app) in apps { appNames[bundleID] = app.name }
            return NameHistoryEntry(name: name, workType: record.workType, end: record.end,
                                    appSeconds: apps.mapValues(\.total))
        }
        return (entries, appNames)
    }
}
