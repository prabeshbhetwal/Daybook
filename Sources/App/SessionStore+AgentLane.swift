import Foundation

/// Feeds the engine's Agent lane from the presence sampler, and reads it back
/// for the menu panel and History.
extension SessionStore {
    /// Keeps the first agent signal of the quiet stretch since `lastInput`:
    /// a span opens there, not where a minute of quiet first let it be seen.
    func noteAgentSignal(_ signal: Date?, lastInput: Date) {
        guard let signal, signal > lastInput else { return }
        if firstAgentSignal.map({ $0 <= lastInput }) ?? true { firstAgentSignal = signal }
    }

    /// The agent held the session at `signal`: the lane runs to it.
    func noteAgentAtWork(signal: Date, lastInput: Date) {
        let first = firstAgentSignal.flatMap { $0 > lastInput ? $0 : nil } ?? signal
        engine.noteAgentAtWork(first: first, signal: signal, lastInput: lastInput, app: agentApp())
    }

    /// An agent's hooks pinged while the person works in another app: the
    /// lanes overlap, the agent in its app's category and the person in the
    /// one in front. With the agent's app in front it is the person's work.
    func noteAgentAlongside(now: Date, lastInput: Date) {
        guard let ping = lastAgentPing, now.timeIntervalSince(ping) <= AgentPresence.window,
              AgentPresence.worksAlongside(front: engine.currentAppBundleID, agentApp: engine.activeDetectedApp),
              let app = engine.activeDetectedApp else { return }
        engine.noteAgentAlongside(signal: ping, lastInput: lastInput, app: app)
    }

    /// Hands the running session to the agent (Labs): the Agent lane carries
    /// it, declared, until input or the unattended limit.
    func handOffToAgent() {
        engine.handOff(app: agentApp())
        refresh()
    }

    /// The person takes the session back from the agent.
    func takeBackFromAgent() {
        engine.takeBackFromAgent()
        refresh()
    }

    /// The app the agent works in, whose category its lane takes: the one in
    /// front if it is a work app, else the session's own app if that is one.
    private func agentApp() -> String? {
        [engine.currentAppBundleID, engine.activeDetectedApp].compactMap { $0 }.first(where: AgentPresence.isWorkApp)
    }

    /// The lane across a History row's records, cut to `bounds`; nil when none of them has one.
    func agentLane(of session: DaySession, in bounds: DateInterval, at moment: Date) -> [AgentSpan]? {
        let lanes = session.recordIDs.map { id -> [AgentSpan]? in
            if engine.state != .idle, id == engine.activeRecordID { return engine.agentSpansSoFar(until: moment) }
            return engine.archive.records.first(where: { $0.id == id })?.agentLane
        }
        guard lanes.contains(where: { $0 != nil }) else { return nil }
        return lanes.flatMap { $0 ?? [] }.compactMap { $0.clipped(from: bounds.start, to: bounds.end) }
    }

    /// The Agent lane's share of the day's activity goals, by purpose raw value: under Count
    /// with my time, the part inside the unattended limit and inside focus stretches, in the
    /// agent app's own category. Empty under every other choice.
    func agentFocusByPurpose(_ sessions: [DaySession], on day: Date, rule: AgentGoalRule) -> [String: TimeInterval] {
        guard rule.policy == .countAsWork,
              let bounds = Calendar.current.dateInterval(of: .day, for: day) else { return [:] }
        let overrides = engine.store.purposeOverrides
        var spans: [AppPurpose: [AgentSpan]] = [:]
        var together: [AppPurpose: TimeInterval] = [:]
        for session in sessions {
            let focus = focusIntervals(of: session)
            let phases = sessionActivity(for: session)?.phases ?? []
            for span in rule.goalSpans(agentLane(of: session, in: bounds, at: now()) ?? []) {
                let purpose = PurposeMap.purpose(for: span.app, activity: .active, overrides: overrides)
                let pieces = focus.compactMap { span.clipped(from: $0.start, to: $0.end) }
                guard span.isAlongside else { spans[purpose, default: []] += pieces; continue }
                // The union within a category: what the person's own time already credits to this
                // activity is not counted again, at the share each phase credited it.
                let yours = phases.map { (span: DateInterval(start: $0.start, end: max($0.start, $0.end)),
                                          credit: $0.credited[purpose.rawValue] ?? 0) }
                for piece in pieces {
                    together[purpose, default: 0] += AgentLane.unclaimed(DateInterval(start: piece.start, end: piece.end),
                                                                         by: yours)
                }
            }
        }
        var result = Dictionary(uniqueKeysWithValues: spans.map { ($0.key.rawValue, AgentLane.seconds($0.value)) })
        for (purpose, seconds) in together { result[purpose.rawValue, default: 0] += seconds }
        return result
    }
}
