import Foundation

/// What one session's recording actually shows: which app held the front, how
/// often the front changed, and why each stretch of app use ended. Every clause
/// is gated on its own evidence, so a session with no usage recording says so
/// rather than describing a shape nobody observed.
///
/// `Core` only — no Design or SwiftUI. The phrasing matches `Tokens.duration`.
enum SessionShape {

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

        init(segments: [TimelineSegment],
             workType: WorkType,
             stretches: Int,
             worked: TimeInterval) {
            self.segments = segments.sorted { $0.start < $1.start }
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

    // MARK: - Clauses

    /// Which app held the front, and for how much of what was recorded. Stated
    /// against recorded time, never against the session's length, so a partly
    /// recorded session does not read as a mostly idle one.
    private static func frontClause(_ input: Input) -> String? {
        let recorded = input.segments.reduce(0) { $0 + $1.seconds }
        guard recorded > 0 else { return nil }
        var byApp: [String: (name: String, seconds: TimeInterval)] = [:]
        for segment in input.segments {
            let existing = byApp[segment.bundleID]
            byApp[segment.bundleID] = (segment.appName,
                                       (existing?.seconds ?? 0) + segment.seconds)
        }
        guard let top = byApp.values.max(by: { $0.seconds < $1.seconds }) else { return nil }
        if byApp.count == 1 {
            return "\(top.name) was in front for all \(duration(recorded)) recorded."
        }
        return "\(top.name) was in front for \(duration(top.seconds)) of the "
            + "\(duration(recorded)) recorded, across \(byApp.count) apps."
    }

    /// How often the front actually changed. The first app observed is context
    /// rather than a switch, and a same-app boundary is persistence detail.
    private static func movementClause(_ input: Input) -> String? {
        var switches = 0
        var previous: String?
        for segment in input.segments {
            if let previous, previous != segment.bundleID { switches += 1 }
            previous = segment.bundleID
        }
        guard switches > 0 else {
            return input.segments.count > 1 ? "You stayed in one app throughout." : nil
        }
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
        return "It is counted in full because \(input.workType.displayName) "
            + "treats watching as the work itself."
    }

    /// The session's own coverage. Worked time beyond what app recording saw is
    /// stated plainly rather than left as a silent discrepancy.
    private static func recordingGapClause(_ input: Input) -> String? {
        let recorded = input.segments.reduce(0) { $0 + $1.seconds }
        let gap = input.worked - recorded
        guard gap >= 60 else { return nil }
        return "\(duration(gap)) of this session has no app recording."
    }

    /// `Core` cannot import the Design layer, so it carries the same phrasing
    /// as `Tokens.duration`: `2h 15m`, `4h`, `15m`.
    private static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        guard hours > 0 else { return "\(minutes)m" }
        return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
    }
}
