import Foundation

/// The Agent lane: when an agent held the session with nobody at the keyboard.
/// Recorded as spans, never a total, so every cut that slices a record's
/// pauses slices these the same way.
extension SessionEngine {
    /// An agent was seen working at `signal`, the latest signal of a quiet
    /// stretch whose first signal was `first`, after the last input at
    /// `lastInput`. Only while the session runs on the agent's account.
    ///
    /// Quiet under the idle threshold is still the person's (reading,
    /// thinking), so the lane starts no earlier than that. A run already in
    /// the lane grows to the new signal; one silent longer than the presence
    /// window (a relaunch, a pause) starts a new span at this signal rather
    /// than bridge the gap.
    func noteAgentAtWork(first: Date, signal: Date, lastInput: Date, app: String?) {
        guard state == .running, store.agentQuietPolicy.keepsSessionRunning,
              var spans = agentSpans, signal <= now() else { return }
        let youUntil = lastInput.addingTimeInterval(store.idlePauseThreshold)
        guard signal > youUntil else { return }
        let sameQuiet = spans.last.map { abs($0.since.timeIntervalSince(lastInput)) < 1 } ?? false
        if let last = spans.last, sameQuiet, signal.timeIntervalSince(last.end) <= AgentPresence.window {
            spans[spans.count - 1].end = max(last.end, signal)
        } else {
            let opening = sameQuiet ? signal : max(first, youUntil)
            let start = min(max(opening, sessionStartDate), signal)
            spans.append(AgentSpan(start: start, end: signal, since: lastInput, app: app))
        }
        agentSpans = spans
    }

    /// The running record's lane up to `end`: cut to the session and clear of
    /// its pauses, the open one included. Nil for a session begun before the
    /// lane existed, which shows no split.
    func agentSpansSoFar(until end: Date) -> [AgentSpan]? {
        guard let agentSpans else { return nil }
        var paused = pausedSpans
        if let pauseStartDate, end > pauseStartDate { paused.append(DateInterval(start: pauseStartDate, end: end)) }
        return AgentLane.counted(agentSpans, in: DateInterval(start: sessionStartDate, end: max(sessionStartDate, end)),
                                 paused: paused)
    }

    /// A relaunch keeps the lane up to the checkpoint and no further: an
    /// agent on a Mac that went down was not seen working after it.
    func restoreAgentSpans(_ saved: [AgentSpan]?, savedAt: Date) {
        agentSpans = saved.map { spans in spans.compactMap { $0.clipped(from: $0.start, to: savedAt) } }
    }

    /// The running session's lane so far; nil when idle or begun before the lane.
    var runningAgentSpans: [AgentSpan]? {
        state == .idle ? nil : agentSpansSoFar(until: now())
    }
}
