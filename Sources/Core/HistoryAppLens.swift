import Foundation

/// App stretches sorted by start, so the stretches inside a span are found by
/// bisection instead of a walk over the whole record.
struct SortedUsage {
    /// Every stretch History can draw, in start order.
    let stretches: [AppUsageSession]
    /// Stretches up to `shortLimit`: a span looks back only that far for one
    /// that reaches into it.
    private let short: [AppUsageSession]
    /// The rare longer ones, checked against every span. Looking back as far
    /// as the longest stretch made one day-long stretch slow every search.
    private let long: [AppUsageSession]

    static let shortLimit: TimeInterval = 2 * 3_600

    init(_ usage: [AppUsageSession]) {
        // A stretch longer than History draws any record is damaged, and is
        // refused here as `HistoryStats` refuses it.
        let bound = TimeInterval(HistoryStats.maximumCalendarDaysPerRecord) * 86_400
        let drawable = usage.filter { (stretch: AppUsageSession) -> Bool in
            stretch.end > stretch.start && stretch.seconds <= bound
        }
        stretches = drawable.sorted { $0.start < $1.start }
        short = stretches.filter { $0.seconds <= Self.shortLimit }
        long = stretches.filter { $0.seconds > Self.shortLimit }
    }

    /// Seconds each app was in front inside the spans, by bundle ID.
    func seconds(within spans: [DateInterval]) -> [String: TimeInterval] {
        var totals: [String: TimeInterval] = [:]
        forEachOverlap(spans) { stretch, piece in totals[stretch.bundleID, default: 0] += piece.duration }
        return totals
    }

    /// Each stretch's part inside each span, with the stretch it came from.
    func forEachOverlap(_ spans: [DateInterval], _ body: (AppUsageSession, DateInterval) -> Void) {
        func visit(_ stretch: AppUsageSession, _ span: DateInterval) {
            let start = max(stretch.start, span.start)
            let end = min(stretch.end, span.end)
            if end > start { body(stretch, DateInterval(start: start, end: end)) }
        }
        for span in spans {
            var index = firstIndex(startingAtOrAfter: span.start.addingTimeInterval(-Self.shortLimit))
            while index < short.count, short[index].start < span.end {
                visit(short[index], span)
                index += 1
            }
            for stretch in long where stretch.start < span.end { visit(stretch, span) }
        }
    }

    private func firstIndex(startingAtOrAfter date: Date) -> Int {
        var low = 0
        var high = short.count
        while low < high {
            let middle = (low + high) / 2
            if short[middle].start < date { low = middle + 1 } else { high = middle }
        }
        return low
    }
}

/// One app as History tells it: the focus sessions it was used in and how
/// much of each, its use outside every session, and when in the day it fell.
/// Pure, so the figures are checked without a window.
struct HistoryAppLens: Equatable {
    /// Under this, an app's time in a session is a flicker in passing, and
    /// the session is not listed as one that used it.
    static let minimumUse: TimeInterval = 10

    /// A session (one thread's stretches on one day) the app was used in.
    struct SessionUse: Equatable {
        let threadID: UUID
        let day: Date
        let workType: WorkType
        /// First start to last end of the session's stretches.
        let span: DateInterval
        let seconds: TimeInterval
        /// Where the app was in front, clipped to the session.
        let moments: [DateInterval]
    }

    /// One sitting with the app outside every focus session.
    struct OutsideUse: Equatable {
        let day: Date
        let span: DateInterval
        let seconds: TimeInterval
    }

    struct DayUse: Equatable {
        let day: Date
        var inSession: TimeInterval = 0
        var outside: TimeInterval = 0
    }

    let bundleID: String
    /// Newest first.
    let sessions: [SessionUse]
    /// Newest first.
    let outside: [OutsideUse]
    /// Days the app was used, oldest first.
    let days: [DayUse]
    /// Seconds per clock hour, 0 to 23, inside and outside sessions.
    let hoursInSession: [TimeInterval]
    let hoursOutside: [TimeInterval]
    /// The other apps in front during the listed sessions; shares are of all
    /// app use in them, this app's included.
    let alongside: [AppRank]
    let lastUsed: Date?

    var inSession: TimeInterval { days.reduce(0) { $0 + $1.inSession } }
    var outsideTotal: TimeInterval { days.reduce(0) { $0 + $1.outside } }

    static func build(bundleID: String, records: [SessionRecord], usage: SortedUsage,
                      calendar: Calendar) -> HistoryAppLens {
        let focus = records.filter { $0.workType.countsAsFocus && $0.end > $0.start }
        let listed = sessions(of: bundleID, in: focus, usage: usage, calendar: calendar)

        var days: [Date: DayUse] = [:]
        // A session's time belongs to the day it started, as History files the
        // session itself: a day's figure then matches the cards under it.
        for (day, seconds) in listed.byDay { days[day, default: DayUse(day: day)].inSession += seconds }
        var hoursIn = Array(repeating: TimeInterval(0), count: 24)
        var hoursOut = Array(repeating: TimeInterval(0), count: 24)
        var outsidePieces: [DateInterval] = []
        let covered = merged(focus.map { DateInterval(start: $0.start, end: $0.end) })
        let mine = usage.stretches.filter { $0.bundleID == bundleID }
        for stretch in mine {
            let parts = split(DateInterval(start: stretch.start, end: stretch.end), by: covered)
            for piece in parts.inside {
                forEachHour(of: piece, calendar: calendar) { hourStart, seconds in
                    hoursIn[calendar.component(.hour, from: hourStart)] += seconds
                }
            }
            for piece in parts.outside {
                forEachHour(of: piece, calendar: calendar) { hourStart, seconds in
                    let day = calendar.startOfDay(for: hourStart)
                    days[day, default: DayUse(day: day)].outside += seconds
                    hoursOut[calendar.component(.hour, from: hourStart)] += seconds
                }
                outsidePieces += splitAtMidnight(piece, calendar: calendar)
            }
        }

        return HistoryAppLens(bundleID: bundleID, sessions: listed.uses,
                              outside: sittings(outsidePieces, calendar: calendar),
                              days: days.values.sorted { $0.day < $1.day },
                              hoursInSession: hoursIn, hoursOutside: hoursOut,
                              alongside: listed.alongside, lastUsed: mine.map(\.end).max())
    }

    /// The sessions that used the app for at least `minimumUse`, the other
    /// apps in front during them, and the app's time in every session by the
    /// day the session started, flickers included.
    private static func sessions(of bundleID: String, in focus: [SessionRecord], usage: SortedUsage,
                                 calendar: Calendar)
        -> (uses: [SessionUse], alongside: [AppRank], byDay: [Date: TimeInterval]) {
        struct Key: Hashable { let thread: UUID; let day: Date }
        var groups: [Key: [SessionRecord]] = [:]
        for record in focus {
            groups[Key(thread: record.threadID, day: calendar.startOfDay(for: record.start)), default: []].append(record)
        }
        var uses: [SessionUse] = []
        var byDay: [Date: TimeInterval] = [:]
        var others: [String: (name: String, total: TimeInterval, longest: TimeInterval)] = [:]
        var overall: TimeInterval = 0
        for (key, records) in groups {
            let spans = records.map { DateInterval(start: $0.start, end: $0.end) }
            var moments: [DateInterval] = []
            var pieces: [(AppUsageSession, DateInterval)] = []
            usage.forEachOverlap(spans) { stretch, piece in
                pieces.append((stretch, piece))
                if stretch.bundleID == bundleID { moments.append(piece) }
            }
            let seconds = moments.reduce(0) { $0 + $1.duration }
            if seconds > 0 { byDay[key.day, default: 0] += seconds }
            guard seconds >= minimumUse, let first = spans.map(\.start).min(),
                  let last = spans.map(\.end).max() else { continue }
            uses.append(SessionUse(threadID: key.thread, day: key.day, workType: records[0].workType,
                                   span: DateInterval(start: first, end: last), seconds: seconds,
                                   moments: moments.sorted { $0.start < $1.start }))
            for (stretch, piece) in pieces {
                overall += piece.duration
                guard stretch.bundleID != bundleID else { continue }
                var entry = others[stretch.bundleID] ?? (stretch.appName, 0, 0)
                entry.total += piece.duration
                entry.longest = max(entry.longest, piece.duration)
                others[stretch.bundleID] = entry
            }
        }
        var alongside: [AppRank] = []
        for (bundle, entry) in others {
            alongside.append(AppRank(bundleID: bundle, appName: entry.name, total: entry.total,
                                     share: overall > 0 ? entry.total / overall : 0, longest: entry.longest))
        }
        alongside.sort { $0.total == $1.total ? $0.bundleID < $1.bundleID : $0.total > $1.total }
        return (uses.sorted { $0.span.start > $1.span.start }, alongside, byDay)
    }

    /// Overlapping or touching intervals joined, in order.
    static func merged(_ intervals: [DateInterval]) -> [DateInterval] {
        var result: [DateInterval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = result.last, interval.start <= last.end {
                result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                result.append(interval)
            }
        }
        return result
    }

    /// The parts of `interval` inside and outside `covered`, which is merged.
    static func split(_ interval: DateInterval, by covered: [DateInterval])
        -> (inside: [DateInterval], outside: [DateInterval]) {
        var inside: [DateInterval] = []
        var outside: [DateInterval] = []
        // Merged covers are disjoint and in order, so their ends rise too:
        // bisect to the first that ends after the interval starts.
        var low = 0
        var high = covered.count
        while low < high {
            let middle = (low + high) / 2
            if covered[middle].end <= interval.start { low = middle + 1 } else { high = middle }
        }
        var cursor = interval.start
        var index = low
        while index < covered.count, covered[index].start < interval.end {
            let cover = covered[index]
            if cover.start > cursor { outside.append(DateInterval(start: cursor, end: cover.start)) }
            let start = max(cover.start, cursor)
            let end = min(cover.end, interval.end)
            if end > start { inside.append(DateInterval(start: start, end: end)) }
            cursor = max(cursor, end)
            index += 1
        }
        if interval.end > cursor { outside.append(DateInterval(start: cursor, end: interval.end)) }
        return (inside, outside)
    }

    /// Outside pieces joined into sittings: a gap shorter than the app-use
    /// session gap keeps one sitting, and a sitting never crosses midnight.
    private static func sittings(_ pieces: [DateInterval], calendar: Calendar) -> [OutsideUse] {
        var result: [OutsideUse] = []
        for piece in pieces.sorted(by: { $0.start < $1.start }) {
            let day = calendar.startOfDay(for: piece.start)
            if let last = result.last, last.day == day,
               piece.start.timeIntervalSince(last.span.end) <= AppUsageConstants.sessionGap {
                result[result.count - 1] = OutsideUse(day: day,
                                                      span: DateInterval(start: last.span.start,
                                                                         end: max(last.span.end, piece.end)),
                                                      seconds: last.seconds + piece.duration)
            } else {
                result.append(OutsideUse(day: day, span: piece, seconds: piece.duration))
            }
        }
        return result.reversed()
    }

    private static func splitAtMidnight(_ piece: DateInterval, calendar: Calendar) -> [DateInterval] {
        var result: [DateInterval] = []
        var cursor = piece.start
        while cursor < piece.end {
            // The day's real end: where a clock skips midnight, start of day
            // plus one day lands an hour past it.
            let next = calendar.dateInterval(of: .day, for: cursor)?.end ?? piece.end
            let end = min(next, piece.end)
            result.append(DateInterval(start: cursor, end: end))
            cursor = end
        }
        return result
    }

    private static func forEachHour(of piece: DateInterval, calendar: Calendar,
                                    _ body: (Date, TimeInterval) -> Void) {
        var cursor = piece.start
        while cursor < piece.end {
            guard let hour = calendar.dateInterval(of: .hour, for: cursor) else { return }
            let end = min(hour.end, piece.end)
            body(hour.start, end.timeIntervalSince(cursor))
            cursor = end
        }
    }
}
