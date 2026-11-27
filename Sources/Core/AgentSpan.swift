import Foundation

/// One stretch an AI agent was seen working with nobody at the keyboard: a
/// piece of the Agent lane (docs/specs/2026-11-27-agent-lane-design.md). It
/// runs from the first agent signal after the last input to the last signal,
/// never to where the five-minute presence window ran out.
struct AgentSpan: Codable, Equatable {
    var start: Date
    var end: Date
    /// The last input before the agent began. Unattended time is measured
    /// from here, so a span cut by a split or at midnight keeps one limit.
    var since: Date
    /// The agent's app, whose category the lane's time takes. Nil when no
    /// work app could be told.
    var app: String?

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }

    /// This span cut to `low ..< high`, or nil when nothing is left.
    func clipped(from low: Date, to high: Date) -> AgentSpan? {
        let from = max(start, low), to = min(end, high)
        guard to > from else { return nil }
        return AgentSpan(start: from, end: to, since: since, app: app)
    }
}

/// The Agent lane's arithmetic. Pure; the engine records the spans, and goals
/// and views read them through here.
enum AgentLane {
    /// `spans` cut to `bounds` and clear of `paused`: the lane only where the
    /// session counted. A pause moved back over an agent's run (the long-away
    /// cap) takes that run out of the lane with it.
    static func counted(_ spans: [AgentSpan], in bounds: DateInterval, paused: [DateInterval]) -> [AgentSpan] {
        let pauses = paused.sorted { $0.start < $1.start }
        return spans.flatMap { span -> [AgentSpan] in
            guard var rest = span.clipped(from: bounds.start, to: bounds.end) else { return [] }
            var pieces: [AgentSpan] = []
            for pause in pauses where pause.end > rest.start && pause.start < rest.end {
                if let before = rest.clipped(from: rest.start, to: pause.start) { pieces.append(before) }
                guard let after = rest.clipped(from: pause.end, to: rest.end) else { return pieces }
                rest = after
            }
            return pieces + [rest]
        }
    }

    /// The lane's seconds inside `bounds`, overlaps counted once.
    static func seconds(_ spans: [AgentSpan], in bounds: DateInterval? = nil) -> TimeInterval {
        let clipped = bounds.map { b in spans.compactMap { $0.clipped(from: b.start, to: b.end) } } ?? spans
        return merged(clipped.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) })
            .reduce(0) { $0 + $1.duration }
    }

    /// What goals may take from the lane: nothing unless the person counts
    /// agent time with their own, and then only up to `limit` after the last
    /// input. Past it the lane is still recorded and shown.
    static func goalSpans(_ spans: [AgentSpan], policy: AgentQuietPolicy, limit: TimeInterval) -> [AgentSpan] {
        guard policy == .countAsWork else { return [] }
        if FocusConstants.isNever(limit) { return spans }
        return spans.compactMap { $0.clipped(from: $0.start, to: $0.since.addingTimeInterval(limit)) }
    }

    /// `head` then `tail`, with a run the split cut in two made whole again.
    static func joined(_ head: [AgentSpan], _ tail: [AgentSpan]) -> [AgentSpan] {
        guard var last = head.last, let first = tail.first, last.end == first.start,
              last.since == first.since, last.app == first.app else { return head + tail }
        last.end = first.end
        return head.dropLast() + [last] + tail.dropFirst()
    }

    /// Overlapping intervals become one, in order.
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

    /// `ranges` less every interval in `cover`, in order.
    static func subtracting(_ cover: [DateInterval], from ranges: [DateInterval]) -> [DateInterval] {
        let holes = merged(cover)
        return ranges.flatMap { range -> [DateInterval] in
            var result: [DateInterval] = []
            var cursor = range.start
            for hole in holes where hole.end > cursor && hole.start < range.end {
                if hole.start > cursor { result.append(DateInterval(start: cursor, end: hole.start)) }
                cursor = max(cursor, hole.end)
            }
            if range.end > cursor { result.append(DateInterval(start: cursor, end: range.end)) }
            return result
        }
    }
}

extension SessionRecord {
    /// The record's Agent lane as it counted: cut to the record and clear of
    /// its known pauses, so an edited record never shows lane time outside
    /// itself. Nil for a record from before the lane.
    var agentLane: [AgentSpan]? {
        agentSpans.map { AgentLane.counted($0, in: DateInterval(start: start, end: max(start, end)),
                                           paused: pausedSpans ?? []) }
    }

    /// Seconds an agent held this record, inside `bounds` when given.
    func agentSeconds(in bounds: DateInterval? = nil) -> TimeInterval {
        agentLane.map { AgentLane.seconds($0, in: bounds) } ?? 0
    }
}

/// How goals read the Agent lane: the person's Agent at work choice and the
/// unattended limit.
struct AgentGoalRule: Equatable {
    var policy: AgentQuietPolicy
    var limit: TimeInterval

    /// Goals count only the person's own time.
    static let youOnly = AgentGoalRule(policy: .trackSeparately, limit: FocusConstants.defaultAgentUnattendedLimit)

    func goalSpans(_ spans: [AgentSpan]) -> [AgentSpan] { AgentLane.goalSpans(spans, policy: policy, limit: limit) }
}

extension PersistenceStore {
    var agentGoalRule: AgentGoalRule { AgentGoalRule(policy: agentQuietPolicy, limit: agentUnattendedLimit) }
}
