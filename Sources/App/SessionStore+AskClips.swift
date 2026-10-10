import Foundation

/// A search hit's part of a range: the work of its records that falls
/// inside it, the days that work lands on, and the stretches of the
/// records inside the range.
struct AskClip {
    let hit: HistorySearchHit
    let worked: TimeInterval
    let days: Set<Date>
    let spans: [DateInterval]
}

/// Ask Daybook's session lists and the pieces every lookup shares: the
/// sessions a range holds, clipped to it, and how its dates are named.
extension SessionStore {
    // MARK: - Sessions

    /// The newest ten sessions in the range that match the words, or every
    /// session in it when there are none, so "what did I do yesterday?"
    /// needs no word to search for.
    func askSessions(_ range: AskRange, words: String) -> String {
        let words = words.trimmingCharacters(in: .whitespacesAndNewlines)
        let filter = words.isEmpty ? nil : HistoryFilter(query: words)
        let found = askHits(matching: filter, in: range)
        // Asked what a note said about something, with no period named, the
        // model searched today alone and said there was nothing (probe,
        // 2026-10-10), so a search that finds nothing in a shorter range says
        // what the whole record holds as well.
        let everywhere = found.isEmpty && filter != nil && range != .allTime
            ? askHits(matching: filter, in: .allTime) : []
        guard !everywhere.isEmpty else {
            return AskFacts.sessions(range, words: words, lines: askLines(found), matched: found.count,
                                     sessionRunning: askSessionIsMissed(range))
        }
        return AskFacts.sessionsElsewhere(range, words: words, lines: askLines(everywhere), matched: everywhere.count,
                                          sessionRunning: askSessionIsMissed(.allTime))
    }

    /// The newest ten, each dated by the first day of the range it has work
    /// on, so a session begun last night is not listed under yesterday's date
    /// for today, and timed from where it enters that day: one begun at 11pm
    /// and paused until midnight reads 12:00am on the day it has work.
    private func askLines(_ found: [AskClip]) -> [AskSessionLine] {
        found.prefix(10).map { clip in
            let day = clip.days.min() ?? clip.hit.day
            let start = clip.spans.map(\.start).min().map { max($0, day) }
            return AskSessionLine(day: askDay(day), time: start.map(askTime) ?? "",
                                  name: clip.hit.name, worked: clip.worked, note: clip.hit.noteSnippet)
        }
    }

    // MARK: - Shared

    /// Whether a search over the range misses a session still going: one is
    /// in progress and overlaps the range. A search reads saved sessions,
    /// and the running one is saved when it ends. Overlap, not "the range
    /// holds today": a session begun at 11pm and still going at 12:30am has
    /// work in yesterday, and "what did I do yesterday?" must say so.
    func askSessionIsMissed(_ range: AskRange) -> Bool {
        guard engine.state != .idle else { return false }
        let interval = askInterval(range)
        return engine.sessionStartDate < interval.end && now() > interval.start
    }

    func askInterval(_ range: AskRange) -> DateInterval {
        range.interval(now: now(), firstDay: historyTop().firstDay, calendar: periodCalendar)
    }

    /// The sessions a search finds that touch the range, each clipped to it:
    /// one that crosses midnight is found by the part inside, not by the day
    /// it began, and brings only that part's work. A nil filter finds every
    /// session. The range is half-open: `DateInterval.contains` takes its
    /// end, which would count Monday's session in last week. The search is
    /// not capped: it lists newest first and stops at its limit before the
    /// range is applied, so any cap would drop the oldest sessions from a
    /// long range's count. A session with no work inside the range, paused
    /// all through it, is not a hit for word totals and lists
    /// (`needingWork`); an app's session count keeps it, as History's app
    /// filter does, since the app was in front inside it.
    func askHits(matching filter: HistoryFilter?, in range: AskRange, needingWork: Bool = true) -> [AskClip] {
        let interval = askInterval(range)
        let records = Dictionary(engine.archive.records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let hits = historySearchHits(matching: filter ?? HistoryFilter(), limit: .max, listingAll: filter == nil)
        return hits.compactMap { hit -> AskClip? in
            let inside = hit.recordIDs.compactMap { records[$0] }.filter { askTouches($0, interval) }
            let worked = inside.reduce(0) { $0 + $1.workSeconds(in: (interval.start, interval.end)) }
            guard !inside.isEmpty, !needingWork || worked > 0 else { return nil }
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

    // MARK: - Names

    /// A date named in the calendar the period was worked out in.
    private func askText(_ format: String, _ date: Date) -> String {
        DateFormats.australian(format, in: periodCalendar.timeZone).string(from: date)
    }

    /// `Tue 14 Nov`, with the year when it is not this year's, so a best day
    /// over all time cannot be read as this year's.
    func askDay(_ date: Date, weekday: Bool = true) -> String {
        let calendar = periodCalendar
        let thisYear = calendar.component(.year, from: date) == calendar.component(.year, from: now())
        return askText((weekday ? "EEE " : "") + "d MMM" + (thisYear ? "" : " yyyy"), date)
    }

    /// The dates a relative range covers: `Sat 10 Oct`, `5 Oct – 11 Oct`,
    /// `September 2026`, `2026`; nil for all time and for a range named by
    /// its date already.
    func askDates(_ range: AskRange) -> String? {
        let interval = askInterval(range)
        switch range {
        case .allTime, .day, .month, .year: return nil
        case .last30Days:
            let last = periodCalendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.start
            return "\(askDay(interval.start, weekday: false)) – \(askDay(last, weekday: false))"
        default:
            return range.level.map { askLabel(HistoryPlace(level: $0, span: interval)) }
        }
    }

    /// `9:10am`.
    func askTime(_ date: Date) -> String {
        askText("h:mma", date).lowercased()
    }

    /// A History row's period: `Tue 14 Nov`, `13 Nov – 19 Nov`, `November 2023`, `2023`.
    func askLabel(_ place: HistoryPlace) -> String {
        switch place.level {
        case .year: return askText("yyyy", place.start)
        case .month: return askText("MMMM yyyy", place.start)
        case .week:
            let last = periodCalendar.date(byAdding: .day, value: -1, to: place.span.end) ?? place.start
            return "\(askDay(place.start, weekday: false)) – \(askDay(last, weekday: false))"
        case .day: return askDay(place.start)
        }
    }
}
