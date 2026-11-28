import Foundation

/// Hand off to agent (Labs): the person says their agent is at work and steps
/// back. The session runs on in the Agent lane, marked declared, with no
/// local signal needed (an agent's cloud task shows none); the You lane stops
/// and no away question is asked. Input brings the person back, and the
/// unattended limit ends it on its own, back-dated to the limit.
extension SessionEngine {
    /// Whether the running session is handed off now.
    var isHandedOff: Bool { state == .running && handOffSince != nil }

    /// Hands the running session to the agent working in `app`.
    func handOff(app: String?) {
        guard state == .running, store.offersHandOff, handOffSince == nil, agentSpans != nil else { return }
        let moment = now()
        handOffSince = moment
        agentSpans?.append(AgentSpan(start: moment, end: moment, since: moment, app: app, declared: true))
        persist()
        onStateChanged?(state)
    }

    /// One presence sample while handed off, with the person's real last
    /// input. The quiet seconds the sampler sends the transition table are
    /// not that: after an agent's signal or a film stops they count from
    /// there, and read as input they ended a hand-off at the agent's last
    /// local step, the very case it is for.
    func observeHandOff(lastInput: Date) {
        guard isHandedOff, let since = handOffSince else { return }
        let moment = now()
        if !store.offersHandOff {
            // Labs turned off mid-hand-off: it ends now, as a button press would.
            takeBackFromAgent()
            return
        }
        if lastInput > since.addingTimeInterval(FocusConstants.handOffGrace) {
            endHandOff(at: lastInput)
            persist()
            onStateChanged?(state)
            return
        }
        let limit = store.agentUnattendedLimit
        if !FocusConstants.isNever(limit), moment >= since.addingTimeInterval(limit) {
            let end = since.addingTimeInterval(limit)
            endHandOff(at: end)
            enterPause(reason: .idle, at: end)
            persist()
            onStateChanged?(state)
            return
        }
        if var spans = agentSpans, let last = spans.indices.last, spans[last].isDeclared {
            let before = spans[last].end
            spans[last].end = max(before, moment)
            agentSpans = spans
            // A checkpoint a minute, so a crash loses no more of the hand-off.
            if Int(moment.timeIntervalSinceReferenceDate / 60) != Int(before.timeIntervalSinceReferenceDate / 60) {
                persist()
            }
        }
    }

    /// The person ends the hand-off by hand: their own time runs from now.
    func takeBackFromAgent() {
        guard isHandedOff else { return }
        endHandOff(at: now())
        persist()
        onStateChanged?(state)
    }

    /// Ends the hand-off at `moment`: its declared span closes there.
    func endHandOff(at moment: Date) {
        guard handOffSince != nil else { return }
        handOffSince = nil
        handOffClosedAt = min(moment, now())
        guard var spans = agentSpans, let last = spans.indices.last, spans[last].isDeclared else { return }
        spans[last].end = max(spans[last].start, min(moment, now()))
        agentSpans = spans
    }

    /// A relaunch within the presence window carries the hand-off on, with a
    /// new declared span from now (the gap was not seen); anything longer was
    /// a crash or a shutdown, and the hand-off closed at the checkpoint,
    /// where `restoreAgentSpans` has already cut its span. A correction's
    /// rollback comes through here too, and loses the seconds since its
    /// checkpoint from the lane: never more than a minute, by the checkpoints.
    func restoreHandOff(_ since: Date?, savedAt: Date) {
        handOffSince = nil
        guard let since, var spans = agentSpans else { return }
        // The hand-off ran to the checkpoint whatever happens next.
        if let last = spans.indices.last, spans[last].isDeclared {
            spans[last].end = max(spans[last].end, max(spans[last].start, savedAt))
            agentSpans = spans
        }
        guard store.offersHandOff else { return }
        let moment = now()
        let limit = store.agentUnattendedLimit
        guard moment.timeIntervalSince(savedAt) <= AgentPresence.window,
              FocusConstants.isNever(limit) || moment < since.addingTimeInterval(limit) else { return }
        handOffSince = since
        let app = agentSpans?.last(where: \.isDeclared)?.app
        agentSpans?.append(AgentSpan(start: moment, end: moment, since: since, app: app, declared: true))
    }
}
