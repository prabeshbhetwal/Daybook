import Foundation

/// A session-local projection of foreground-app evidence. Source records can
/// overlap in legacy or checkpoint data, but the Mac cannot have two foreground
/// apps at once. This projection therefore retains the union of observed time,
/// chooses one stable foreground app for each conflicting slice, and represents
/// the remaining supplied session spans as explicit recording gaps.
struct RecordedActivity: Equatable {
    struct Interval: Identifiable, Equatable {
        let start: Date
        let end: Date
        /// Nil identifies a source-recording gap, not rest or an inferred away
        /// interval. App identity is present only when it was observed.
        let bundleID: String?
        let appName: String?
        let colourIndex: Int?

        var id: String {
            "\(start.timeIntervalSinceReferenceDate)-\(end.timeIntervalSinceReferenceDate)-\(bundleID ?? "gap")"
        }
        var recordedSeconds: TimeInterval { bundleID == nil ? 0 : duration }
        var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
        var isGap: Bool { bundleID == nil }
    }

    let intervals: [Interval]
    let bounds: [DateInterval]
    /// Conflicting source records were present. The retained duration remains
    /// factual, while the visible limitation explains the chosen foreground.
    let hasConflictingForegroundEvidence: Bool

    var coverage: TimeInterval { intervals.reduce(0) { $0 + $1.recordedSeconds } }
    var gapDuration: TimeInterval { intervals.filter(\.isGap).reduce(0) { $0 + $1.duration } }
    var elapsed: TimeInterval { bounds.reduce(0) { $0 + $1.duration } }
    var hasRecordedActivity: Bool { coverage > 0 }

    var appRanks: [AppRank] {
        var totals: [String: (name: String, total: TimeInterval, longest: TimeInterval)] = [:]
        for interval in intervals {
            guard let id = interval.bundleID, let name = interval.appName, interval.duration > 0 else { continue }
            let existing = totals[id] ?? (name, 0, 0)
            totals[id] = (name, existing.total + interval.duration, max(existing.longest, interval.duration))
        }
        return totals.map { id, item in
            AppRank(bundleID: id, appName: item.name, total: item.total,
                    share: coverage > 0 ? item.total / coverage : 0, longest: item.longest)
        }.sorted {
            $0.total == $1.total
                ? ($0.appName == $1.appName ? $0.bundleID < $1.bundleID : $0.appName < $1.appName)
                : $0.total > $1.total
        }
    }

    init(segments: [TimelineSegment], spans: [DateInterval]) {
        bounds = Self.merged(spans)
        guard !bounds.isEmpty else {
            intervals = []
            hasConflictingForegroundEvidence = false
            return
        }

        let ordered = segments.enumerated().compactMap { offset, segment -> Source? in
            guard segment.seconds > 0, segment.start.isFiniteDate, segment.end.isFiniteDate else { return nil }
            return Source(segment: segment, order: offset)
        }.sorted { first, second in
            if first.segment.start != second.segment.start { return first.segment.start < second.segment.start }
            if first.segment.end != second.segment.end { return first.segment.end < second.segment.end }
            return first.order < second.order
        }

        var projected: [Interval] = []
        var conflict = false
        for span in bounds {
            let clipped = ordered.compactMap { source -> Source? in
                let start = max(source.segment.start, span.start)
                let end = min(source.segment.end, span.end)
                guard end > start else { return nil }
                var result = source
                result.start = start
                result.end = end
                return result
            }
            let points = Array(Set(([span.start, span.end] + clipped.flatMap { [$0.start, $0.end] })))
                .sorted()
            for pair in zip(points, points.dropFirst()) {
                let start = pair.0, end = pair.1
                guard end > start else { continue }
                let active = clipped.filter { $0.start < end && $0.end > start }
                if Set(active.map { $0.segment.bundleID }).count > 1 { conflict = true }
                let selected = active.first
                Self.append(start: start, end: end, source: selected, to: &projected)
            }
        }
        intervals = projected
        hasConflictingForegroundEvidence = conflict
    }

    private struct Source {
        var segment: TimelineSegment
        let order: Int
        var start: Date { get { segment.start } set { segment = TimelineSegment(id: segment.id, bundleID: segment.bundleID, appName: segment.appName, start: newValue, end: segment.end, colorIndex: segment.colorIndex, endReason: segment.endReason) } }
        var end: Date { get { segment.end } set { segment = TimelineSegment(id: segment.id, bundleID: segment.bundleID, appName: segment.appName, start: segment.start, end: newValue, colorIndex: segment.colorIndex, endReason: segment.endReason) } }
    }

    private static func merged(_ spans: [DateInterval]) -> [DateInterval] {
        var result: [DateInterval] = []
        for span in spans.filter({ $0.duration.isFinite && $0.duration > 0 }).sorted(by: { $0.start < $1.start }) {
            guard let last = result.last else { result.append(span); continue }
            if span.start <= last.end {
                result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, span.end))
            } else {
                result.append(span)
            }
        }
        return result
    }

    private static func append(start: Date, end: Date, source: Source?, to intervals: inout [Interval]) {
        let next = Interval(start: start, end: end, bundleID: source?.segment.bundleID,
                            appName: source?.segment.appName, colourIndex: source?.segment.colorIndex)
        if let last = intervals.last,
           last.end == next.start,
           last.bundleID == next.bundleID,
           last.appName == next.appName,
           last.colourIndex == next.colourIndex {
            intervals[intervals.count - 1] = Interval(start: last.start, end: next.end,
                                                       bundleID: last.bundleID, appName: last.appName,
                                                       colourIndex: last.colourIndex)
        } else {
            intervals.append(next)
        }
    }
}

private extension Date {
    var isFiniteDate: Bool { timeIntervalSinceReferenceDate.isFinite }
}
