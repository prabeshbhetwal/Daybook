import Foundation

/// Story shows stretches in chronological order. The compact Sessions digest
/// may fold a resumed thread; doing so here would move the afternoon above the
/// lunch break and hide the interval between them.
enum StoryMoment: Identifiable, Equatable {
    case entry(DayEntry)
    case appUse(DateInterval, seconds: TimeInterval)
    case unrecorded(DateInterval)

    var start: Date {
        switch self {
        case .entry(let entry): return entry.start
        case .appUse(let span, _), .unrecorded(let span): return span.start
        }
    }

    var end: Date {
        switch self {
        case .entry(let entry): return entry.end
        case .appUse(let span, _), .unrecorded(let span): return span.end
        }
    }

    var id: String {
        switch self {
        case .entry(.session(let session)):
            return (session.isRunning ? "live-" : "record-") + session.id.uuidString
        case .entry(.rest(let rest)): return "rest-" + rest.id.uuidString
        case .appUse(let span, _): return "app-\(span.start.timeIntervalSince1970)"
        case .unrecorded(let span): return "gap-\(span.start.timeIntervalSince1970)"
        }
    }
}

enum StoryChronology {
    static func build(records: [SessionRecord], running: RunningThread?,
                      usage: [AppUsageSession], day: Date, now: Date,
                      calendar: Calendar = .current) -> [StoryMoment] {
        guard let bounds = calendar.dateInterval(of: .day, for: day) else { return [] }
        var entries = records.filter { $0.end > bounds.start && $0.start < bounds.end }
            .flatMap { record in
                SessionDigest.entries(records: [record], running: nil, now: now,
                                      day: day, calendar: calendar)
            }
        if let running {
            entries += SessionDigest.entries(records: [], running: running, now: now,
                                              day: day, calendar: calendar)
        }
        let occupied = merge(entries.map { entry -> DateInterval in
            switch entry {
            case .session(let session): return DateInterval(start: session.start, end: session.end)
            case .rest(let rest): return DateInterval(start: rest.start, end: rest.end)
            }
        })
        let recorded = usage.compactMap { session -> DateInterval? in
            let start = max(session.start, bounds.start)
            let end = min(session.end, bounds.end)
            return end > start ? DateInterval(start: start, end: end) : nil
        }
        var result = entries.map(StoryMoment.entry)
        // Represent app use not already explained by a session or named rest.
        let evidence = recorded.flatMap { subtract($0, occupied: occupied) }
        let loose = mergeLoose(evidence, occupied: occupied)
        for span in loose {
            // Bounds may bridge a small unknown gap. Sum only actual outside
            // evidence, preserving the archive's canonical (even overlapping
            // legacy) values rather than inventing observation inside the gap.
            let seconds = evidence.reduce(0.0) { total, observed in
                total + max(0, min(span.end, observed.end)
                    .timeIntervalSince(max(span.start, observed.start)))
            }
            if seconds > 0 { result.append(.appUse(span, seconds: seconds)) }
        }
        // Only internal, evidenced boundaries: no invented wake/start-of-day or
        // away classification. Tiny switch gaps are left implicit, not inflated.
        let coverage = merge(occupied + recorded)
        for pair in zip(coverage, coverage.dropFirst()) {
            if pair.1.start.timeIntervalSince(pair.0.end) >= 60 {
                result.append(.unrecorded(DateInterval(start: pair.0.end, end: pair.1.start)))
            }
        }
        return result.sorted {
            $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start
        }
    }

    private static func merge(_ ranges: [DateInterval], bridging: TimeInterval = 0) -> [DateInterval] {
        var result: [DateInterval] = []
        for range in ranges.sorted(by: { $0.start < $1.start }) where range.duration > 0 {
            if let last = result.last, range.start.timeIntervalSince(last.end) <= bridging {
                result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, range.end))
            } else { result.append(range) }
        }
        return result
    }

    /// Groups ordinary tiny unrecorded switch gaps, but never bridges through a
    /// known focus/rest interval. Such an occupied interval is evidence, not a
    /// presentation detail that a compact row may erase.
    private static func mergeLoose(_ ranges: [DateInterval], occupied: [DateInterval]) -> [DateInterval] {
        var result: [DateInterval] = []
        for range in ranges.sorted(by: { $0.start < $1.start }) where range.duration > 0 {
            guard let last = result.last else { result.append(range); continue }
            if range.start <= last.end {
                result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, range.end))
                continue
            }
            let gap = DateInterval(start: last.end, end: range.start)
            let crossesOccupied = gap.duration > 0 && occupied.contains { interval in
                interval.end > gap.start && interval.start < gap.end
            }
            if range.start.timeIntervalSince(last.end) <= 60 && !crossesOccupied {
                result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, range.end))
            } else {
                result.append(range)
            }
        }
        return result
    }

    private static func subtract(_ range: DateInterval, occupied: [DateInterval]) -> [DateInterval] {
        var start = range.start
        var result: [DateInterval] = []
        for covered in occupied where covered.end > start && covered.start < range.end {
            if covered.start > start {
                result.append(DateInterval(start: start, end: min(covered.start, range.end)))
            }
            start = max(start, covered.end)
            if start >= range.end { return result }
        }
        if start < range.end { result.append(DateInterval(start: start, end: range.end)) }
        return result
    }
}
