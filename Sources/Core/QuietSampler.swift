import Foundation

/// Tells a quiet stretch apart, one sample at a time, into idle and watched —
/// a film, a call, an AI agent at work — and says where idle counts from once
/// the watching ends. Pure, so each sample's reading can be checked with an
/// injected clock; the store feeds it once a second.
struct QuietSampler {
    private var lastSampleWatching = false
    private var lastSampleFilm = false
    /// Where idle counts from once watching ends: a film ends when it is no
    /// longer seen, an agent's run at its last step.
    private var watchingEndedAt: Date?
    /// The agent's last step in this quiet stretch. A film still on after the
    /// agent stops is watched from here, not from the keypress before the agent,
    /// or the film's pause would take the agent's counted work back.
    private var lastAgentSeen: Date?

    /// Recent input: nothing to tell apart, and any watching is over.
    mutating func noteInput() { self = QuietSampler() }

    /// - Parameters:
    ///   - quiet: seconds since the last key or click.
    ///   - film: something on screen holds the display awake (`WatchDetector`).
    ///   - agentSeen: `AgentPresence.lastSeen`; nil when no agent counts now.
    ///   - idlePaused: the session already paused as idle. Watching that starts
    ///     then is nobody's — autoplay, an agent left running — and its end
    ///     read as someone back: a fifteen-minute command between an agent's
    ///     pings ended an idle pause with the user still out, and asked about
    ///     25 minutes of an 80-minute absence.
    /// - Returns: the engine's event, and the quiet seconds for the usage tracker.
    mutating func read(now: Date, quiet: TimeInterval, film: Bool, agentSeen: Date?,
                       idlePaused: Bool) -> (event: SessionEvent, trackerSeconds: TimeInterval) {
        // A clock stepped back leaves these in the future. They prove nothing,
        // then or once the clock catches up: kept, one came due half an hour
        // later as "the watching just ended" and asked about an absence with
        // nobody back. A negative idle would have read the same way.
        if let end = watchingEndedAt, end > now { watchingEndedAt = nil }
        if let seen = lastAgentSeen, seen > now { lastAgentSeen = nil }
        let film = film && !idlePaused
        let agentSeen = idlePaused ? nil : agentSeen
        if let agentSeen { lastAgentSeen = agentSeen }
        if film || agentSeen != nil {
            lastSampleWatching = true
            lastSampleFilm = film
            watchingEndedAt = nil
            let seconds = agentSeen == nil ? since(lastAgentSeen, quiet: quiet, now: now) : quiet
            return (.watchingObserved(seconds: seconds, byAgent: agentSeen != nil), quiet)
        }
        if lastSampleWatching { watchingEndedAt = lastSampleFilm ? now : lastAgentSeen ?? now }
        lastSampleWatching = false
        // Once the watching stops, idle counts from then — not from the last
        // keypress before the film, which would put the film into the absence.
        let effective = since(watchingEndedAt, quiet: quiet, now: now)
        return (.idleObserved(seconds: effective), effective)
    }

    /// Quiet measured from `anchor` when that is later than the last input.
    private func since(_ anchor: Date?, quiet: TimeInterval, now: Date) -> TimeInterval {
        anchor.map { min(quiet, now.timeIntervalSince($0)) } ?? quiet
    }
}
