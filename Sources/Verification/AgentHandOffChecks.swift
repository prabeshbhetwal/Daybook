import Foundation

/// Phase 2 of the Agent lane (docs/specs/2026-11-27-agent-lane-design.md):
/// Hand off to agent in Labs, and the two lanes in different activities at
/// once without either being counted twice.
enum AgentHandOffChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Handed off, the session runs on as declared agent time until input brings you back", handOffHolds),
        ("A hand-off ends on its own at the unattended limit, back-dated to it", handOffLimit),
        ("A relaunch keeps a hand-off going; a crash closes it at the checkpoint", handOffRestore),
        ("An agent working while you use another app keeps both lanes, never summed", lanesOverlap),
        ("A lock, a reset or Labs turned off ends a hand-off where it happens", { handOffEnds() }),
        ("Time after you stop typing is the agent's alone, never marked as shared", { unattendedFollowsShared() }),
        ("A lock after a long hand-off keeps the declared time, and the agent's own app in front is yours", { lockKeepsDeclared() }),
        ("Alongside time already credited to the activity is not counted again, share by share", { unionByShare() }),
    ]

    private static let editor = "com.microsoft.VSCode"

    private static func handedOffEngine(_ clock: TestClock) -> SessionEngine {
        let engine = SelfTest.makeEngine(clock)
        engine.store.idlePauseThreshold = 5 * 60
        engine.store.agentUnattendedLimit = 30 * 60
        engine.store.offersHandOff = true
        engine.start(workType: .deepWork, intent: "Hand off")
        clock.advance(60)
        engine.handOff(app: editor)
        return engine
    }

    /// Quiet since the hand-off, sampled once a minute for `minutes`, the way
    /// the presence sampler sends it: the true last input to the hand-off.
    /// The table gets, for the first ten minutes, quiet counted from a local
    /// agent's last signal two minutes back (not input), and after that the
    /// whole quiet of a cloud task, well past the idle threshold.
    private static func quiet(_ engine: SessionEngine, _ clock: TestClock, minutes: Int, since: Date) {
        for minute in 0..<minutes {
            clock.advance(60)
            engine.observeHandOff(lastInput: since)
            let quiet = clock.value.timeIntervalSince(since)
            let local = engine.isHandedOff && minute < 10
            engine.transition(on: .idleObserved(seconds: local ? min(120, quiet) : quiet))
        }
    }

    private static func handOffHolds() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        let off = SelfTest.makeEngine(clock)
        off.start(workType: .deepWork, intent: "Off")
        off.handOff(app: editor)
        expect(!off.isHandedOff, "Hand off does nothing while Labs has it off", &problems)

        let engine = handedOffEngine(clock)
        let since = clock.value
        expect(engine.isHandedOff, "the session is handed off", &problems)
        quiet(engine, clock, minutes: 20, since: since)
        expect(engine.state == .running, "twenty quiet minutes handed off keep the session running, got \(engine.state)", &problems)
        let lane = engine.runningAgentSpans ?? []
        expect(lane.count == 1 && lane.first?.isDeclared == true, "one declared span, got \(lane)", &problems)
        SelfTest.expectClose(AgentLane.seconds(lane), 20 * 60, "the Agent lane holds the twenty minutes", &problems)
        // Input at 20m30s: the hand-off ends there and the You lane resumes.
        clock.advance(40)
        engine.observeHandOff(lastInput: clock.value.addingTimeInterval(-10))
        engine.transition(on: .idleObserved(seconds: 10))
        expect(!engine.isHandedOff && engine.state == .running, "input ends the hand-off and the session runs on as yours", &problems)
        let end = engine.runningAgentSpans?.last?.end
        SelfTest.expectClose(end?.timeIntervalSince(since) ?? -1, 20 * 60 + 30, "the span ends at the input", &problems)
        engine.transition(on: .manualPause)
        return problems
    }

    private static func handOffLimit() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        let engine = handedOffEngine(clock)
        let since = clock.value
        quiet(engine, clock, minutes: 40, since: since)
        expect(!engine.isHandedOff, "the hand-off ended at the limit", &problems)
        expect(engine.state == .paused(reason: .idle), "past the limit the session pauses, got \(engine.state)", &problems)
        SelfTest.expectClose(engine.snapshot().pauseStart?.timeIntervalSince(since) ?? -1, 30 * 60,
                             "the pause is back-dated to the limit", &problems)
        SelfTest.expectClose(AgentLane.seconds(engine.runningAgentSpans ?? []), 30 * 60, "the lane stops at the limit", &problems)
        return problems
    }

    private static func handOffRestore() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        let engine = handedOffEngine(clock)
        let since = clock.value
        quiet(engine, clock, minutes: 10, since: since)
        let snapshot = engine.snapshot()

        clock.advance(60)
        let relaunched = SelfTest.makeEngine(clock)
        relaunched.store.offersHandOff = true
        relaunched.store.agentUnattendedLimit = 30 * 60
        relaunched.restore(from: snapshot)
        expect(relaunched.isHandedOff, "a relaunch a minute later keeps the hand-off", &problems)

        clock.advance(20 * 60)
        let crashed = SelfTest.makeEngine(clock)
        crashed.store.offersHandOff = true
        crashed.store.agentUnattendedLimit = 30 * 60
        crashed.restore(from: snapshot)
        expect(!crashed.isHandedOff, "a restore long after the checkpoint ends the hand-off", &problems)
        let end = crashed.runningAgentSpans?.last(where: \.isDeclared)?.end
        expect(end == snapshot.savedAt, "the declared span closes at the checkpoint, got \(String(describing: end))", &problems)
        return problems
    }

    private static func lanesOverlap() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        let engine = SelfTest.makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Together")
        let began = clock.value
        for _ in 0..<30 {
            clock.advance(60)
            engine.noteAgentAlongside(signal: clock.value, lastInput: clock.value, app: editor)
        }
        let lane = engine.runningAgentSpans ?? []
        expect(lane.count == 1 && lane.first?.isAlongside == true, "one span alongside you, got \(lane)", &problems)
        SelfTest.expectClose(AgentLane.together(lane), 29 * 60, "both lanes hold the time", &problems)
        expect(AgentLane.replacing(lane) == [], "time alongside you never comes off your lane", &problems)
        // Goals: the focus ring counts yours and the agent's as one set.
        let usage = [AppUsageSession(bundleID: "com.google.Chrome", appName: "Chrome", start: began, end: clock.value, endReason: .appSwitch)]
        let total = FocusedActiveTime.seconds(in: DateInterval(start: began, end: clock.value), records: [], usage: usage,
                                              running: (began, clock.value), runningWork: 30 * 60, runningPaused: [],
                                              runningAgent: lane, agent: AgentGoalRule(policy: .countAsWork, limit: 3_600))
        SelfTest.expectClose(total, 30 * 60, "the overlap is counted once, never summed", &problems)
        // Your own time is untouched by an agent working beside you.
        let yours = FocusedActiveTime.seconds(in: DateInterval(start: began, end: clock.value), records: [], usage: usage,
                                              running: (began, clock.value), runningWork: 30 * 60, runningPaused: [],
                                              runningAgent: lane, agent: .youOnly)
        SelfTest.expectClose(yours, 30 * 60, "your goal keeps all thirty minutes you worked", &problems)
        let line = Tokens.laneSplit(worked: 30 * 60, agent: 29 * 60, together: 29 * 60)
        expect(line == "You 30m · Agent 29m · 29m at once", "the lanes are shown apart, got \(String(describing: line))", &problems)
        return problems
    }
}

extension AgentHandOffChecks {
    fileprivate static func handOffEnds() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        let locked = handedOffEngine(clock)
        clock.advance(5 * 60)
        locked.transition(on: .awayBegan(trigger: .screenLock))
        expect(!locked.isHandedOff, "a screen lock ends the hand-off", &problems)
        SelfTest.expectClose(AgentLane.seconds(locked.runningAgentSpans ?? []), 5 * 60,
                             "the declared span closes at the lock", &problems)

        let reset = handedOffEngine(clock)
        clock.advance(5 * 60)
        reset.transition(on: .resetSession)
        expect(!reset.isHandedOff, "a new session does not start handed off", &problems)

        let labsOff = handedOffEngine(clock)
        let since = clock.value
        clock.advance(2 * 60)
        labsOff.store.offersHandOff = false
        labsOff.observeHandOff(lastInput: since)
        expect(!labsOff.isHandedOff, "turning Labs off ends the hand-off", &problems)
        return problems
    }
}

extension AgentHandOffChecks {
    fileprivate static func unattendedFollowsShared() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        let engine = SelfTest.makeEngine(clock)
        engine.store.idlePauseThreshold = 5 * 60
        engine.start(workType: .deepWork, intent: "Shared then alone")
        let began = clock.value
        for _ in 0..<5 {
            clock.advance(30)
            engine.noteAgentAlongside(signal: clock.value, lastInput: clock.value, app: editor)
        }
        let lastInput = clock.value
        // You stop typing; the agent keeps going for 20 minutes.
        for _ in 0..<20 {
            clock.advance(60)
            engine.noteAgentAtWork(first: lastInput.addingTimeInterval(60), signal: clock.value, lastInput: lastInput, app: editor)
        }
        let lane = engine.runningAgentSpans ?? []
        SelfTest.expectClose(AgentLane.together(lane), lastInput.timeIntervalSince(began) - 30, "only the shared minutes are shared", &problems)
        let alone = AgentLane.seconds(AgentLane.replacing(lane) ?? [])
        expect(alone > 14 * 60, "the unattended time is the agent's alone, got \(alone) s", &problems)
        return problems
    }

    fileprivate static func lockKeepsDeclared() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        let engine = handedOffEngine(clock)
        let since = clock.value
        quiet(engine, clock, minutes: 20, since: since)
        engine.transition(on: .awayBegan(trigger: .screenLock))
        // The ticker's next samples carry the quiet since your last input, from before the hand-off.
        clock.advance(60)
        engine.transition(on: .idleObserved(seconds: clock.value.timeIntervalSince(since) + 60))
        SelfTest.expectClose(AgentLane.seconds(engine.runningAgentSpans ?? []), 20 * 60,
                             "the twenty declared minutes survive the lock and the idle pause after it", &problems)
        expect(AgentPresence.worksAlongside(front: "com.apple.dt.Xcode", agentApp: "com.openai.codex") ||
               !AgentPresence.isWorkApp("com.openai.codex"), "another work app in front is alongside", &problems)
        expect(!AgentPresence.worksAlongside(front: editor, agentApp: editor), "the agent's own app in front is yours", &problems)
        expect(!AgentPresence.worksAlongside(front: nil, agentApp: nil), "no agent app is nothing alongside", &problems)
        return problems
    }

    fileprivate static func unionByShare() -> [String] {
        var problems: [String] = []
        let start = SelfTest.base
        let piece = DateInterval(start: start, end: start.addingTimeInterval(3_600))
        // An hour-long phase that credited one minute to the activity leaves the agent 59 of its 60.
        let mixed = AgentLane.unclaimed(piece, by: [(span: piece, credit: 60)])
        SelfTest.expectClose(mixed, 3_540, "a minute of credit in an hour takes a minute off the agent", &problems)
        let whole = AgentLane.unclaimed(piece, by: [(span: piece, credit: 3_600)])
        SelfTest.expectClose(whole, 0, "a fully credited hour leaves the agent nothing", &problems)
        SelfTest.expectClose(AgentLane.unclaimed(piece, by: []), 3_600, "with no credit the agent keeps it all", &problems)
        return problems
    }
}
