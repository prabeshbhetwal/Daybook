import Foundation

/// Ask's account of a session's stretches. The sessions, and the stretches
/// inside them, are the Story's own for each day (its day projection, the
/// running session included); a stretch's note and power line are read as the
/// journal and the session report read them. `AskFacts` only words them.
extension SessionStore {
    func askSessionDetail(_ range: AskRange, words: String?) -> AskLookupResult {
        let calendar = periodCalendar
        let wanted = askWantedThreads(range, words: words)
        var listed: [(thread: UUID, day: Date, detail: AskSessionDetail)] = []
        var everyDayRead = true
        // Newest first, and no further than ten sessions: a long history is counted, not read.
        walk: for day in wanted.keys.sorted(by: >) {
            for case let .session(session) in storyDayProjection(on: day, calendar: calendar).sessions.reversed()
            where wanted[day]?.contains(session.threadID) == true {
                listed.append((session.threadID, day, AskSessionDetail(
                    name: session.workType.sessionTitle(named: session.name), day: askDay(day), stretches: askStretches(of: session, on: day))))
                if listed.count == 10 { everyDayRead = false; break walk }
            }
        }
        // Counted from the days the search found, unless every one was read.
        let matched = everyDayRead ? listed.count : max(listed.count, wanted.values.reduce(0) { $0 + $1.count })
        let details = listed.map(\.detail)
        let shown = AskFacts.sessionDetailShown(details, matched: matched)
        let places = listed.prefix(shown).map {
            askSessionLink(thread: $0.thread, name: $0.detail.name, day: $0.day, role: .stretches)
        }
        return AskLookupResult(text: AskFacts.sessionDetail(range, words: words, sessions: details, matched: matched),
                               links: [askPeriodLink(range, role: .stretches)] + places)
    }

    /// The sessions to read, as the threads on each day of the range: those a
    /// search for the words finds, or all of them when there are none, and the
    /// session running now when it is inside the range and fits.
    private func askWantedThreads(_ range: AskRange, words: String?) -> [Date: Set<UUID>] {
        var wanted: [Date: Set<UUID>] = [:]
        for clip in askHits(matching: words.map { HistoryFilter(query: $0) }, in: range)
        where clip.hit.workType != .breakTime {
            for day in clip.days { wanted[day, default: []].insert(clip.hit.threadID) }
        }
        // A search reads saved sessions, and the running one is saved when it ends.
        if askSessionIsMissed(range), engine.activeWorkType != .breakTime, askRunningMatches(words) {
            let calendar = periodCalendar
            let interval = askInterval(range)
            var day = calendar.startOfDay(for: max(engine.sessionStartDate, interval.start))
            let last = min(now(), interval.end)
            for _ in 0..<HistoryStats.maximumCalendarDaysPerRecord {
                guard day < last else { break }
                wanted[day, default: []].insert(engine.activeThreadID)
                day = HistoryTreeBuilder.dayAfter(day, calendar: calendar)
            }
        }
        return wanted
    }

    /// Whether every word of the search is in the running session's name.
    private func askRunningMatches(_ words: String?) -> Bool {
        guard let words else { return true }
        let name = SearchWords.fold(engine.sessionName)
        return SearchWords.words(in: words).allSatisfy { name.contains($0) }
    }

    /// Each stretch the Story draws for the session on the day: its clipped
    /// start and end, the work inside the day, its first note line and the
    /// session report's power line. The running stretch has no end.
    private func askStretches(of session: DaySession, on day: Date) -> [AskStretchLine] {
        let calendar = periodCalendar
        return zip(session.recordIDs, session.spans).map { id, span in
            let power = powerSummary(for: [id], interval: span)?.headline
            let note = askFirstNoteLine(of: id)
            if session.isRunning, engine.state != .idle, id == engine.activeRecordID {
                let worked = runningThread(on: day, now: now(), calendar: calendar)?.worked ?? span.duration
                // Only the slice that holds now is still going; an earlier day's ended at midnight.
                return AskStretchLine(from: askTime(span.start), to: calendar.isDate(now(), inSameDayAs: day) ? nil
                                      : askTime(span.end), worked: worked, power: power, note: note)
            }
            let worked = engine.archive.records.first { $0.id == id }?.workSeconds(on: day, calendar: calendar)
                ?? span.duration
            return AskStretchLine(from: askTime(span.start), to: askTime(span.end), worked: worked, power: power,
                                  note: note)
        }
    }

    /// The first non-empty line of a stretch's note, as `journalNote(for:)` reads the note.
    func askFirstNoteLine(of recordID: UUID) -> String? {
        (metadataArchive.metadata(for: recordID)?.note ?? "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }
}
