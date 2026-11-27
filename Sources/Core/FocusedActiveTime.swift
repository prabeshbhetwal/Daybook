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
    ///   - runningPaused: the in-flight session's known pauses. Nil when they
    ///     are not known exactly, which leaves the whole span to the cap.
    static func seconds(on day: Date,
                        records: [SessionRecord],
                        usage: [AppUsageSession],
                        running: (start: Date, end: Date)?,
                        runningWork: TimeInterval? = nil,
                        runningPaused: [DateInterval]? = nil,
                        runningAgent: [AgentSpan]? = nil,
                        agent: AgentGoalRule = .youOnly,
                        calendar: Calendar = .current) -> TimeInterval {
        guard let bounds = SessionRecord.dayBounds(day, calendar: calendar) else {
            return 0
        }
        return seconds(in: DateInterval(start: bounds.start, end: bounds.end),
                       records: records, usage: usage, running: running,
                       runningWork: runningWork, runningPaused: runningPaused,
                       runningAgent: runningAgent, agent: agent)
    }

    /// Focused-active seconds inside any bounded interval. This is the same
    /// intersection used for today's goal and historical same-clock-time pace.
    static func seconds(in interval: DateInterval,
                        records: [SessionRecord],
                        usage: [AppUsageSession],
                        running: (start: Date, end: Date)?,
                        runningWork: TimeInterval? = nil,
                        runningPaused: [DateInterval]? = nil,
                        runningAgent: [AgentSpan]? = nil,
                        agent: AgentGoalRule = .youOnly) -> TimeInterval {
        guard interval.duration > 0 else { return 0 }
        let bounds = (start: interval.start, end: interval.end)
        // A running session with no work here (one in a category that does not count) credits nothing, and its
        // span must not widen the union below either.
        let running = runningWork == 0 ? nil : running
        // Only what can touch the interval: anything else clips to nothing and
        // credits exactly zero below. `>=` keeps a zero-length record ending on
        // the opening instant, which `workSeconds(in:)` still assigns here.
        // Today's goal reads this every second over the whole history.
        let focusRecords = records.filter {
            $0.end >= bounds.start && $0.start < bounds.end && $0.workType.countsAsFocus
        }
        // Known pauses are not focus. Credited across the whole span, app use
        // inside an explicit pause filled the goal while no work was logged.
        // The Agent lane is not the person's: it leaves the hands-on figure, and
        // comes back only as far as the agent rule lets it (`AgentLane.goalSpans`).
        func you(_ span: Span, paused: [DateInterval]?, lane: [AgentSpan]?) -> [Span] {
            without(lane, worked(span, paused: paused))
        }
        func agentPart(_ lane: [AgentSpan]?) -> [Span] {
            clip(agent.goalSpans(lane ?? []).map { (start: $0.start, end: $0.end) }, to: bounds)
        }
        var focus = focusRecords.flatMap { you(($0.start, $0.end), paused: $0.exactPausedSpans, lane: $0.agentLane) }
        var agentFocus = focusRecords.flatMap { agentPart($0.agentLane) }
        if let running {
            focus += you(running, paused: runningPaused, lane: runningAgent)
            agentFocus += agentPart(runningAgent)
        }

        let handsOn = merged(clip(usage.compactMap { session -> Span? in
                                      session.end > bounds.start && session.start < bounds.end
                                          ? (start: session.start, end: session.end) : nil
                                  },
                                  to: bounds))
        // The union intersection de-duplicates overlapping records, so no
        // second is ever counted twice however the archive overlaps.
        // The agent's counted part joins the hands-on focus as one set, so a
        // minute another record already counts as yours is not counted again.
        let union = length(merged(intersect(merged(clip(focus, to: bounds)), handsOn) + agentFocus))

        // A record's credit is additionally capped at the work actually done in
        // it. A span includes paused stretches, and a session paused on a
        // distraction app is *hands-on by definition* — the dwell that paused
        // it required using the app — so without this cap an hour of YouTube
        // inside a session filled an hour of the focus goal. The cap is a
        // ceiling, never below the truth: real focused-active time can exceed
        // neither the hands-on overlap nor the recorded work.
        var capped: TimeInterval = 0
        for record in focusRecords {
            let credit = overlap(clip(you((record.start, record.end), paused: record.exactPausedSpans,
                                          lane: record.agentLane), to: bounds), handsOn)
                + length(merged(agentPart(record.agentLane)))
            capped += min(credit, record.workSeconds(in: bounds))
        }
        if let running {
            let credit = overlap(clip(you(running, paused: runningPaused, lane: runningAgent), to: bounds), handsOn)
                + length(merged(agentPart(runningAgent)))
            capped += min(credit, runningWork ?? credit)
        }
        return min(union, capped)
    }

    private typealias Span = (start: Date, end: Date)

    /// The span less its pauses, in order. Nil pauses leave the whole span.
    private static func worked(_ span: Span, paused: [DateInterval]?) -> [Span] {
        guard let paused, !paused.isEmpty else { return [span] }
        var result: [Span] = []
        var cursor = span.start
        for pause in paused.sorted(by: { $0.start < $1.start }) {
            let low = max(pause.start, cursor), high = min(pause.end, span.end)
            guard high > low else { continue }
            if low > cursor { result.append((start: cursor, end: low)) }
            cursor = high
        }
        if span.end > cursor { result.append((start: cursor, end: span.end)) }
        return result
    }

    /// `spans` less the Agent lane.
    private static func without(_ lane: [AgentSpan]?, _ spans: [Span]) -> [Span] {
        guard let lane, !lane.isEmpty else { return spans }
        let cover = lane.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }
        return AgentLane.subtracting(cover, from: spans.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) })
            .map { (start: $0.start, end: $0.end) }
    }

    private static func length(_ spans: [Span]) -> TimeInterval {
        spans.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    }

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
        length(intersect(left, right))
    }

    private static func intersect(_ left: [Span], _ right: [Span]) -> [Span] {
        var result: [Span] = []
        var i = 0
        var j = 0
        while i < left.count, j < right.count {
            let low = max(left[i].start, right[j].start)
            let high = min(left[i].end, right[j].end)
            if high > low { result.append((start: low, end: high)) }
            if left[i].end < right[j].end { i += 1 } else { j += 1 }
        }
        return result
    }
}
