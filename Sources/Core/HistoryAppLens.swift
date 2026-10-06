import Foundation

/// One app as History tells it: the focus sessions it was used in and how
/// much of each, its use outside every session, and when in the day it fell.
/// Pure, so the figures are checked without a window.
///
/// Every second is counted once. The app's own stretches are joined first,
/// so a stretch recorded twice is one time in front; and a second inside two
/// overlapping focus records belongs to the one that began first, so the
/// sessions' figures add up to the time in sessions.
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
        /// The session's focused time, so the app's share has one denominator
        /// wherever it is printed.
        let worked: TimeInterval
        /// Where the app was in front, clipped to the session.
        let moments: [DateInterval]

        var share: Double {
            let whole = worked > 0 ? worked : span.duration
            return whole > 0 ? min(1, seconds / whole) : 0
        }
    }

    /// The app's glances inside sessions on one day: each under `minimumUse`,
    /// so no session is listed for them, but the time is in the day's figure
    /// and the day still gets a line.
    struct PassingUse: Equatable {
        let day: Date
        let seconds: TimeInterval
        let sessions: Int
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
    let passing: [PassingUse]
    /// Newest first.
    let outside: [OutsideUse]
    /// Days the app was used, oldest first.
    let days: [DayUse]
    /// The app's time in sessions by the session's category; adds up to
    /// `inSession`.
    let inSessionByType: [WorkType: TimeInterval]
    /// Seconds per clock hour, 0 to 23, inside and outside sessions.
    let hoursInSession: [TimeInterval]
    let hoursOutside: [TimeInterval]
    /// The other apps in front during the listed sessions; shares are of all
    /// app use in them, this app's included.
    let alongside: [AppRank]
    let lastUsed: Date?
    /// Seconds of the whole that were recorded before the usage record became
    /// accurate, when a stretch could run on while nobody was at the Mac.
    let legacy: TimeInterval
    let accurateFrom: Date?

    var inSession: TimeInterval { days.reduce(0) { $0 + $1.inSession } }
    var outsideTotal: TimeInterval { days.reduce(0) { $0 + $1.outside } }
    var total: TimeInterval { inSession + outsideTotal }

    /// In and out of sessions on the days from `day` on, `day` included.
    func total(since day: Date) -> TimeInterval {
        days.reduce(0) { $1.day >= day ? $0 + $1.inSession + $1.outside : $0 }
    }

    /// The middle listed session's time with the app, or nil with none listed.
    var typicalSessionSeconds: TimeInterval? {
        let sorted = sessions.map(\.seconds).sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }

    /// 1 for the listed session that used the app longest.
    func rank(of use: SessionUse) -> Int {
        sessions.filter { $0.seconds > use.seconds }.count + 1
    }

    static func build(bundleID: String, records: [SessionRecord], usage: SortedUsage,
                      calendar: Calendar, accurateFrom: Date? = nil) -> HistoryAppLens {
        let focus = records.filter { $0.workType.countsAsFocus && $0.end > $0.start }
            .sorted { left, right in
                if left.start != right.start { return left.start < right.start }
                if left.end != right.end { return left.end > right.end }
                // The same span twice: one owner, the same on every rebuild.
                return left.threadID.uuidString < right.threadID.uuidString
            }
        let mine = usage.stretches.filter { $0.bundleID == bundleID }
        let used = merged(mine.map { DateInterval(start: $0.start, end: $0.end) })

        // Each record keeps only the part no earlier record covers. Records
        // are in start order, so what earlier ones cover from this start on
        // is exactly up to the latest end so far.
        struct Key: Hashable { let thread: UUID; let day: Date }
        struct Owned { let key: Key; let workType: WorkType; let span: DateInterval }
        var groups: [Key: [SessionRecord]] = [:]
        var owned: [Owned] = []
        var reach: Date?
        for record in focus {
            let key = Key(thread: record.threadID, day: calendar.startOfDay(for: record.start))
            groups[key, default: []].append(record)
            let start = max(record.start, reach ?? record.start)
            if record.end > start {
                owned.append(Owned(key: key, workType: record.workType, span: DateInterval(start: start, end: record.end)))
            }
            reach = max(reach ?? record.end, record.end)
        }

        var days: [Date: DayUse] = [:]
        var hoursIn = Array(repeating: TimeInterval(0), count: 24)
        var hoursOut = Array(repeating: TimeInterval(0), count: 24)
        var byType: [WorkType: TimeInterval] = [:]
        var moments: [Key: [DateInterval]] = [:]
        // A session's time belongs to the day it started, as History files the
        // session itself: a day's figure then matches the cards under it.
        for piece in owned {
            for moment in split(piece.span, by: used).inside {
                moments[piece.key, default: []].append(moment)
                days[piece.key.day, default: DayUse(day: piece.key.day)].inSession += moment.duration
                byType[piece.workType, default: 0] += moment.duration
                forEachHour(of: moment, calendar: calendar) { hourStart, seconds in
                    hoursIn[calendar.component(.hour, from: hourStart)] += seconds
                }
            }
        }

        var outsidePieces: [DateInterval] = []
        let covered = merged(owned.map(\.span))
        for interval in used {
            for piece in split(interval, by: covered).outside {
                forEachHour(of: piece, calendar: calendar) { hourStart, seconds in
                    let day = calendar.startOfDay(for: hourStart)
                    days[day, default: DayUse(day: day)].outside += seconds
                    hoursOut[calendar.component(.hour, from: hourStart)] += seconds
                }
                outsidePieces += splitAtMidnight(piece, calendar: calendar)
            }
        }

        var uses: [SessionUse] = []
        var passing: [Date: PassingUse] = [:]
        for (key, found) in moments {
            let seconds = found.reduce(0) { $0 + $1.duration }
            guard seconds > 0, let records = groups[key], let first = records.map(\.start).min(),
                  let last = records.map(\.end).max() else { continue }
            guard seconds >= minimumUse else {
                let earlier = passing[key.day]
                passing[key.day] = PassingUse(day: key.day, seconds: (earlier?.seconds ?? 0) + seconds,
                                              sessions: (earlier?.sessions ?? 0) + 1)
                continue
            }
            uses.append(SessionUse(threadID: key.thread, day: key.day, workType: records[0].workType,
                                   span: DateInterval(start: first, end: last), seconds: seconds,
                                   worked: records.reduce(0) { $0 + $1.workSeconds },
                                   moments: found.sorted { $0.start < $1.start }))
        }
        uses.sort { $0.span.start > $1.span.start }
        let ownedByKey = Dictionary(grouping: owned, by: \.key)
        let listedSpans = uses.flatMap { use in
            ownedByKey[Key(thread: use.threadID, day: use.day)]?.map(\.span) ?? []
        }

        return HistoryAppLens(bundleID: bundleID, sessions: uses,
                              passing: passing.values.sorted { $0.day > $1.day },
                              outside: sittings(outsidePieces, calendar: calendar),
                              days: days.values.sorted { $0.day < $1.day }, inSessionByType: byType,
                              hoursInSession: hoursIn, hoursOutside: hoursOut,
                              alongside: appsAlongside(bundleID, in: listedSpans, usage: usage),
                              lastUsed: used.last?.end,
                              legacy: accurateFrom.map { legacySeconds(used, before: $0) } ?? 0,
                              accurateFrom: accurateFrom)
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
