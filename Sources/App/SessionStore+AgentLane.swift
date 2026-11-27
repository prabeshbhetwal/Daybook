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
        for session in sessions {
            let focus = focusIntervals(of: session)
            for span in rule.goalSpans(agentLane(of: session, in: bounds, at: now()) ?? []) {
                let purpose = PurposeMap.purpose(for: span.app, activity: .active, overrides: overrides)
                spans[purpose, default: []] += focus.compactMap { span.clipped(from: $0.start, to: $0.end) }
            }
        }
        return Dictionary(uniqueKeysWithValues: spans.map { ($0.key.rawValue, AgentLane.seconds($0.value)) })
    }
}
