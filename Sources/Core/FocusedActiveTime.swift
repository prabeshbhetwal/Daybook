import Foundation

/// Seconds that are both inside a declared focus session and within reach of
/// real input.
///
/// Neither half is sufficient alone, and the app shipped both mistakes. Session
/// wall-clock counted an untouched machine, so a four-hour goal read as met on
/// two and a half hours of use. Raw hands-on time would let an hour of messaging
/// fill a *focus* goal. The intersection is the only figure that can be filled
/// solely by work the user declared and demonstrably did.
enum FocusedActiveTime {

    /// - Parameters:
    ///   - running: the in-flight session's span, or nil when idle.
    ///   - runningWork: the in-flight session's worked seconds inside this day,
    ///     for the same cap the records get. Nil leaves the running span
    ///     uncapped.
    static func seconds(on day: Date,
                        records: [SessionRecord],
                        usage: [AppUsageSession],
                        running: (start: Date, end: Date)?,
                        runningWork: TimeInterval? = nil,
                        calendar: Calendar = .current) -> TimeInterval {
        guard let bounds = SessionRecord.dayBounds(day, calendar: calendar) else {
            return 0
        }
        return seconds(in: DateInterval(start: bounds.start, end: bounds.end),
                       records: records, usage: usage, running: running,
                       runningWork: runningWork)
    }

    /// Focused-active seconds inside any bounded interval. This is the same
    /// intersection used for today's goal and historical same-clock-time pace.
    static func seconds(in interval: DateInterval,
                        records: [SessionRecord],
                        usage: [AppUsageSession],
                        running: (start: Date, end: Date)?,
                        runningWork: TimeInterval? = nil) -> TimeInterval {
        guard interval.duration > 0 else { return 0 }
        let bounds = (start: interval.start, end: interval.end)
        // Only what can touch the interval: anything else clips to nothing and
        // credits exactly zero below. `>=` keeps a zero-length record ending on
        // the opening instant, which `workSeconds(in:)` still assigns here.
        // Today's goal reads this every second over the whole history.
        let focusRecords = records.filter {
            $0.workType.countsAsFocus && $0.end >= bounds.start && $0.start < bounds.end
        }
        var focus = focusRecords.map { (start: $0.start, end: $0.end) }
        if let running { focus.append(running) }

        let handsOn = merged(clip(usage.compactMap { session -> Span? in
                                      session.end > bounds.start && session.start < bounds.end
                                          ? (start: session.start, end: session.end) : nil
                                  },
                                  to: bounds))
        // The union intersection de-duplicates overlapping records, so no
        // second is ever counted twice however the archive overlaps.
        let union = overlap(merged(clip(focus, to: bounds)), handsOn)

        // A record's credit is additionally capped at the work actually done in
        // it. A span includes paused stretches, and a session paused on a
        // distraction app is *hands-on by definition* — the dwell that paused
        // it required using the app — so without this cap an hour of YouTube
        // inside a session filled an hour of the focus goal. The cap is a
        // ceiling, never below the truth: real focused-active time can exceed
        // neither the hands-on overlap nor the recorded work.
        var capped: TimeInterval = 0
        for record in focusRecords {
            let credit = overlap(clip([(record.start, record.end)], to: bounds),
                                 handsOn)
            capped += min(credit, record.workSeconds(in: bounds))
        }
        if let running {
            let credit = overlap(clip([running], to: bounds), handsOn)
            capped += min(credit, runningWork ?? credit)
        }
        return min(union, capped)
    }

    private typealias Span = (start: Date, end: Date)

    private static func clip(_ ranges: [Span], to bounds: Span) -> [Span] {
        ranges.compactMap { range in
            let low = max(range.start, bounds.start)
            let high = min(range.end, bounds.end)
            return high > low ? (start: low, end: high) : nil
        }
    }

    /// Overlapping ranges become one. Without this, two sessions covering the
    /// same hour would each claim it and the goal would fill twice as fast.
    private static func merged(_ ranges: [Span]) -> [Span] {
        let ordered = ranges.sorted { $0.start < $1.start }
        var result: [Span] = []
        for range in ordered {
            if let last = result.last, range.start <= last.end {
                result[result.count - 1].end = max(last.end, range.end)
            } else {
                result.append(range)
            }
        }
        return result
    }

    /// Both inputs are sorted and disjoint by the time they reach here, so this
    /// is a linear sweep rather than the quadratic pass the dashboard's
    /// focus-quality figure still uses.
    private static func overlap(_ left: [Span], _ right: [Span]) -> TimeInterval {
        var total: TimeInterval = 0
        var i = 0
        var j = 0
        while i < left.count, j < right.count {
            let low = max(left[i].start, right[j].start)
            let high = min(left[i].end, right[j].end)
            if high > low { total += high.timeIntervalSince(low) }
            if left[i].end < right[j].end { i += 1 } else { j += 1 }
        }
        return total
    }
}
