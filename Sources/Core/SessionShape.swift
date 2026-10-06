import Foundation

/// What one session's recording actually shows: which app held the front, how
/// often the front changed, and why each stretch of app use ended. Every clause
/// is gated on its own evidence, so a session with no usage recording says so
/// rather than describing a shape nobody observed.
///
/// `Core` only — no Design or SwiftUI. The phrasing matches `Tokens.duration`.
enum SessionShape {

    struct Bin: Equatable, Identifiable {
        let id: Int
        let start: Date
        let end: Date
        let recordedSeconds: TimeInterval
        let dominantBundleID: String?
        var fraction: Double {
            let span = end.timeIntervalSince(start)
            return span > 0 ? min(1, max(0, recordedSeconds / span)) : 0
        }
    }

    static func bins(segments: [TimelineSegment], in bounds: DateInterval) -> [Bin] {
        bins(activity: RecordedActivity(segments: segments, spans: [bounds]), in: bounds)
    }

    /// Retains the legacy eight-bin contract for existing consumers while using
    /// the canonical foreground projection rather than re-summing raw records.
    /// `count` lets a chart ask for as many cells as it has room to draw.
    static func bins(activity: RecordedActivity, in bounds: DateInterval, count: Int = 8) -> [Bin] {
        guard bounds.duration > 0, bounds.duration.isFinite, count > 0 else { return [] }
        let width = bounds.duration / Double(count)
        return (0..<count).map { index in
            let start = bounds.start.addingTimeInterval(Double(index) * width)
            let end = index == count - 1 ? bounds.end : start.addingTimeInterval(width)
            var byApp: [String: [DateInterval]] = [:]
            for interval in activity.intervals {
                guard let bundleID = interval.bundleID else { continue }
                let low = max(start, interval.start), high = min(end, interval.end)
                guard high > low else { continue }
                byApp[bundleID, default: []].append(DateInterval(start: low, end: high))
            }
            var amounts: [(id: String, seconds: TimeInterval)] = []
            for (id, spans) in byApp { amounts.append((id, coveredSeconds(spans))) }
            amounts.sort { first, second in
                first.seconds == second.seconds ? first.id < second.id : first.seconds > second.seconds
            }
            return Bin(id: index, start: start, end: end,
                       recordedSeconds: coveredSeconds(byApp.values.flatMap { $0 }),
                       dominantBundleID: amounts.first?.id)
        }
    }

    /// A stretch of consecutive cells that agree on what was in front. This is
    /// what an activity strip draws: a run per change of app, never a sliver
    /// per interval. Nil `bundleID` means the cells were mostly unrecorded.
    struct Run: Equatable, Identifiable {
        let id: Int
        let start: Date
        let end: Date
        let bundleID: String?
        let cells: Int
        let recordedSeconds: TimeInterval
        var isGap: Bool { bundleID == nil }
    }

    /// The session's app use as runs over a fixed number of cells.
    ///
    /// Drawing one rectangle per recorded interval is honest at ten intervals
    /// and a barcode at three hundred: a busy afternoon switches apps every
    /// few seconds, each switch became a 2pt sliver plus 2pt of spacing, and
    /// the row overran its own width so nothing was proportional any more.
    /// Cells fix the resolution to what the strip can show. Each takes the
    /// app that held the front for most of it, reads as a gap when less than
    /// `gapBelow` of it was recorded, and merges with a neighbour that agrees.
    /// Cells are shared between the session's spans by duration, and runs
    /// never cross a span, so time between stretches is not drawn as either.
    /// Every span is drawn: rounding each share on its own over-spent the
    /// cells and the last stretches, often the longest, silently fell off.
    static func runs(activity: RecordedActivity, cellCount: Int,
                     gapBelow: Double = 0.5) -> [Run] {
        guard cellCount > 0 else { return [] }
        let spans = fitted(activity.bounds.filter { $0.duration > 0 }, into: cellCount)
        let total = spans.reduce(0) { $0 + $1.duration }
        guard total > 0, total.isFinite else { return [] }
        var runs: [Run] = []
        for (span, cells) in zip(spans, shares(of: spans, cells: cellCount, total: total)) {
            for bin in bins(activity: activity, in: span, count: cells) {
                let owner = bin.fraction < gapBelow ? nil : bin.dominantBundleID
                if let last = runs.last, last.end == bin.start, last.bundleID == owner {
                    runs[runs.count - 1] = Run(id: last.id, start: last.start, end: bin.end,
                                               bundleID: owner, cells: last.cells + 1,
                                               recordedSeconds: last.recordedSeconds + bin.recordedSeconds)
                } else {
                    runs.append(Run(id: runs.count, start: bin.start, end: bin.end, bundleID: owner,
                                    cells: 1, recordedSeconds: bin.recordedSeconds))
                }
            }
        }
        return runs
    }

    /// More stretches than cells cannot each have one, so the two with the
    /// shortest time between them are drawn as one until they fit. The time
    /// between reads as unrecorded instead of the later stretches vanishing.
    private static func fitted(_ bounds: [DateInterval], into cells: Int) -> [DateInterval] {
        var spans = bounds.sorted { $0.start < $1.start }
        while spans.count > cells {
            let gaps = spans.indices.dropLast().map { spans[$0 + 1].start.timeIntervalSince(spans[$0].end) }
            guard let index = gaps.indices.min(by: { gaps[$0] < gaps[$1] }) else { break }
            spans[index] = DateInterval(start: spans[index].start,
                                        end: max(spans[index].end, spans[index + 1].end))
            spans.remove(at: index + 1)
        }
        return spans
    }

    /// One cell each, then the rest by duration, largest remainder first, so
    /// the counts add up to exactly `cells`. Needs no more spans than cells.
    private static func shares(of spans: [DateInterval], cells: Int, total: TimeInterval) -> [Int] {
        let spare = Double(cells - spans.count)
        let exact = spans.map { spare * $0.duration / total }
        var counts = exact.map { 1 + Int($0) }
        let remainders = exact.map { $0 - $0.rounded(.down) }
        let order = remainders.indices.sorted {
            remainders[$0] == remainders[$1] ? $0 < $1 : remainders[$0] > remainders[$1]
        }
        for index in order.prefix(max(0, cells - counts.reduce(0, +))) { counts[index] += 1 }
        return counts
    }

    /// Coverage describes time observed, not keystrokes. Duplicate or
    /// overlapping historical records cannot inflate a bar above its interval.
    private static func coveredSeconds(_ spans: [DateInterval]) -> TimeInterval {
        var merged: [DateInterval] = []
        for span in spans.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, span.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, span.end))
            } else { merged.append(span) }
        }
        return merged.reduce(0) { $0 + $1.duration }
    }

    /// One session's evidence, already clipped to that session's stretches.
    struct Input: Equatable {
        /// App stretches that intersect the session, in start order.
        let segments: [TimelineSegment]
        /// The work the session was logged as, which decides whether watching
        /// without input counts.
        let workType: WorkType
        /// How many separate records the thread has on this day.
        let stretches: Int
        /// Canonical worked seconds for the session.
        let worked: TimeInterval
        /// Canonical foreground projection, when the caller already knows the
        /// supplied session spans. Older callers can still provide segments.
        let activity: RecordedActivity

        init(segments: [TimelineSegment],
             workType: WorkType,
             stretches: Int,
             worked: TimeInterval) {
            let visible = segments.filter { $0.seconds > 0 }.sorted { $0.start < $1.start }
            self.segments = visible
            self.workType = workType
            self.stretches = stretches
            self.worked = worked
            if let first = visible.map(\.start).min(), let last = visible.map(\.end).max(), last > first {
                // Compatibility callers expose worked time but not the session
                // spans. Preserve their former missing-recording qualification
                // without affecting the explicit-span Story projection.
                let end = max(last, first.addingTimeInterval(max(0, worked)))
                activity = RecordedActivity(segments: visible, spans: [DateInterval(start: first, end: end)])
            } else {
                activity = RecordedActivity(segments: [], spans: [])
            }
        }

        init(segments: [TimelineSegment], activity: RecordedActivity,
             workType: WorkType, stretches: Int, worked: TimeInterval) {
            self.segments = segments.filter { $0.seconds > 0 }.sorted { $0.start < $1.start }
            self.activity = activity
            self.workType = workType
            self.stretches = stretches
            self.worked = worked
        }
    }

    /// The sentences, in reading order. Empty when nothing was observed, which
    /// the surface shows as its own line rather than as an empty shape.
    static func sentences(_ input: Input) -> [String] {
        guard !input.segments.isEmpty else { return [] }
        var lines: [String] = []
        if let front = frontClause(input) { lines.append(front) }
        if let moving = movementClause(input) { lines.append(moving) }
        if let away = awayClause(input) { lines.append(away) }
        if let watching = watchingClause(input) { lines.append(watching) }
        if let gap = recordingGapClause(input) { lines.append(gap) }
        return lines
    }

    static func paragraph(_ input: Input) -> String? {
        let lines = sentences(input)
        return lines.isEmpty ? nil : lines.joined(separator: " ")
    }

    /// The Story card already states coverage and gaps in its factual caption,
    /// and its app list already ranks the leading app first. Keep only
    /// evidence that adds interpretation there, without changing the fuller
    /// paragraph contract used by existing callers.
    static func storyProse(_ input: Input) -> String? {
        guard !input.segments.isEmpty else { return nil }
        var lines: [String] = []
        if let movement = movementClause(input) { lines.append(movement) }
        if let away = awayClause(input) { lines.append(away) }
        if let watching = watchingClause(input) { lines.append(watching) }
        return lines.isEmpty ? nil : lines.joined(separator: " ")
    }

    // MARK: - Clauses

    /// Which app held the front, and for how much of what was recorded. Stated
    /// against recorded time, never against the session's length, so a partly
    /// recorded session does not read as a mostly idle one.
    private static func frontClause(_ input: Input) -> String? {
        let recorded = input.activity.coverage
        guard recorded > 0 else { return nil }
        let ranks = input.activity.appRanks
        guard let top = ranks.first else { return nil }
        if ranks.count == 1 {
            return "\(top.appName) was in front for all \(duration(recorded)) recorded."
        }
        return "\(top.appName) was in front for \(duration(top.total)) of the "
            + "\(duration(recorded)) recorded, across \(ranks.count) apps."
    }

    /// How often the front actually changed. The first app observed is context
    /// rather than a switch, and a same-app boundary is persistence detail.
    private static func movementClause(_ input: Input) -> String? {
        let observed = input.activity.intervals.compactMap(\.bundleID)
        var switches = 0
        var previous: String?
        for bundleID in observed {
            if let previous, previous != bundleID { switches += 1 }
            previous = bundleID
        }
        guard switches > 0 else { return nil }
        return switches == 1
            ? "You moved between apps once."
            : "You moved between apps \(switches) times."
    }

    /// Stretches that ended because input stopped or the Mac locked. These are
    /// recorded reasons, not inferences about what you were doing.
    private static func awayClause(_ input: Input) -> String? {
        let idle = input.segments.filter { $0.endReason == .idle }.count
        let locked = input.segments.filter { $0.endReason == .systemLock }.count
        var parts: [String] = []
        if idle > 0 {
            parts.append(idle == 1
                         ? "input stopped once"
                         : "input stopped \(idle) times")
        }
        if locked > 0 {
            parts.append(locked == 1 ? "the Mac locked once" : "the Mac locked \(locked) times")
        }
        guard !parts.isEmpty else { return nil }
        return "Along the way \(parts.joined(separator: " and "))."
    }

    /// Why time without input still counted. Only said when there was such
    /// time, and only for the work types where watching is the work.
    private static func watchingClause(_ input: Input) -> String? {
        guard input.workType.countsWhileWatching,
              input.segments.contains(where: { $0.endReason == .idle }) else { return nil }
        return "\(input.workType.displayName) treats watching as the work itself. "
            + "Recorded app use is shown separately."
    }

    /// The session's own coverage. Worked time beyond what app recording saw is
    /// stated plainly rather than left as a silent discrepancy.
    private static func recordingGapClause(_ input: Input) -> String? {
        let gap = input.activity.gapDuration
        guard gap >= 60 else { return nil }
        return "\(duration(gap)) of this session has no app recording."
    }

    /// `Core` cannot import the Design layer, so it carries the same phrasing
    /// as `Tokens.duration`: `2h 15m`, `4h`, `15m`.
    private static func duration(_ seconds: TimeInterval) -> String {
        DurationText.precise(seconds)
    }
}
