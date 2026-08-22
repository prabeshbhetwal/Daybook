import Foundation

/// A run of activity with no gap long enough to elide.
struct TimelineCluster: Identifiable, Equatable {
    let start: Date
    let end: Date
    /// Position across the band, 0...1.
    let xStart: Double
    let xEnd: Double

    var id: Date { start }
    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

/// An elided stretch where nothing happened. Drawn as a narrow labelled
/// separator: the fact is kept, only the pixels are reclaimed.
struct TimelineGap: Identifiable, Equatable {
    let start: Date
    let end: Date
    let xStart: Double
    let xEnd: Double

    var id: Date { start }
    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

/// Owns every coordinate decision for the timeline: where clusters sit, where
/// gaps collapse, and the two mappings between time and position.
///
/// The view asks this for positions and computes none itself — that is what
/// stops the band, the axis and the pointer from drifting apart. Pure, so all of
/// it is covered headlessly.
struct TimelineLayout {

    let clusters: [TimelineCluster]
    let gaps: [TimelineGap]

    init(segments: [TimelineSegment],
         gapThreshold: TimeInterval = FocusConstants.timelineGapThreshold,
         separatorShare: Double = 0.035,
         minimumClusterShare: Double = 0.04) {

        // 1. Cluster: a gap at or over the threshold ends the run.
        let ordered = segments.sorted { $0.start < $1.start }
        var ranges: [(start: Date, end: Date)] = []
        for segment in ordered {
            if var last = ranges.last,
               segment.start.timeIntervalSince(last.end) < gapThreshold {
                last.end = max(last.end, segment.end)
                ranges[ranges.count - 1] = last
            } else {
                ranges.append((segment.start, max(segment.end, segment.start)))
            }
        }
        guard !ranges.isEmpty else {
            clusters = []
            gaps = []
            return
        }

        // 2. Allocate: separators take a fixed share, clusters split the rest in
        //    proportion to duration, with a floor so a short burst stays visible
        //    rather than vanishing between two separators.
        let separatorTotal = separatorShare * Double(max(0, ranges.count - 1))
        let available = max(0.1, 1 - separatorTotal)
        let durations = ranges.map { max(1, $0.end.timeIntervalSince($0.start)) }
        let totalDuration = durations.reduce(0, +)

        let proportional = durations.map { available * ($0 / totalDuration) }
        let lifted = proportional.map { Swift.max($0, minimumClusterShare) }
        let liftedTotal = lifted.reduce(0, +)
        let shares = lifted.map { $0 * available / liftedTotal }

        var builtClusters: [TimelineCluster] = []
        var builtGaps: [TimelineGap] = []
        var cursor = 0.0
        for (index, range) in ranges.enumerated() {
            if index > 0 {
                let previous = ranges[index - 1]
                builtGaps.append(TimelineGap(start: previous.end,
                                             end: range.start,
                                             xStart: cursor,
                                             xEnd: cursor + separatorShare))
                cursor += separatorShare
            }
            builtClusters.append(TimelineCluster(start: range.start,
                                                 end: range.end,
                                                 xStart: cursor,
                                                 xEnd: cursor + shares[index]))
            cursor += shares[index]
        }
        clusters = builtClusters
        gaps = builtGaps
    }

    var isEmpty: Bool { clusters.isEmpty }

    /// Position across the band for an instant, or nil when it falls inside an
    /// elided gap — such an instant has no position, and drawing it at 0 would
    /// smear the segment across the whole band.
    func fraction(for date: Date) -> Double? {
        for cluster in clusters where date >= cluster.start && date <= cluster.end {
            let span = max(1, cluster.end.timeIntervalSince(cluster.start))
            let progress = date.timeIntervalSince(cluster.start) / span
            return cluster.xStart + progress * (cluster.xEnd - cluster.xStart)
        }
        return nil
    }

    /// The instant at a position, for hover. nil over a separator.
    func date(at fraction: Double) -> Date? {
        for cluster in clusters where fraction >= cluster.xStart && fraction <= cluster.xEnd {
            let width = max(0.0001, cluster.xEnd - cluster.xStart)
            let progress = (fraction - cluster.xStart) / width
            let span = cluster.end.timeIntervalSince(cluster.start)
            return cluster.start.addingTimeInterval(progress * span)
        }
        return nil
    }

    /// Whole hours inside clusters only. An elided gap has no hours to draw, so
    /// the axis skips empty time without any special casing in the view.
    func hourTicks(calendar: Calendar = .current) -> [Date] {
        var ticks: [Date] = []
        for cluster in clusters {
            guard var cursor = calendar.dateInterval(of: .hour, for: cluster.start)?.start
            else { continue }
            if cursor < cluster.start { cursor = cursor.addingTimeInterval(3_600) }
            while cursor <= cluster.end && ticks.count < 48 {
                ticks.append(cursor)
                cursor = cursor.addingTimeInterval(3_600)
            }
        }
        return ticks
    }
}
