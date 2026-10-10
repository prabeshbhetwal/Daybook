import Foundation

/// Quiet while an AI agent works: what counts as the agent working, and what
/// each of the user's three choices does to the session.
enum AgentPresenceChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("An agent counts as working from its own pings, or its window in front when allowed",
         agentEvidence),
        ("Quiet while an agent works is counted as work unless the user chose otherwise",
         policiesShapeTheSession),
        ("After an agent stops, time away is measured from its last step", awayStartsWhenAgentStops),
        ("An agent's pings during an idle pause never read as the user coming back",
         pingsDuringIdlePauseAreNobodys),
        ("A film still on after the agent stops keeps the agent's work", filmAfterAgentKeepsWork),
        ("A clock stepped back never makes quiet negative", clockStepBackKeepsQuiet),
    ]

    /// The sampler and the engine together, one sample a minute, as the store
    /// runs them. Pings and a film are given per minute; input resets quiet.
    private final class Run {
        let clock = TestClock(SelfTest.base)
        let engine: SessionEngine
        var sampler = QuietSampler()
        var lastInput: Date
        var lastPing: Date?

        init() {
            engine = SelfTest.makeEngine(clock)
            engine.start(workType: .deepWork, intent: "Agent run")
            lastInput = clock.value
        }

        func minute(ping: Bool = false, film: Bool = false, input: Bool = false) {
            clock.advance(60)
            let now = clock.value
            if ping { lastPing = now }
            if input {
                lastInput = now
                sampler.noteInput()
                engine.transition(on: .idleObserved(seconds: 0))
                return
            }
            let quiet = now.timeIntervalSince(lastInput)
            let seen = AgentPresence.lastSeen(now: now, quiet: quiet, lastActivity: lastPing, frontmostBundleID: nil,
                                              keptAwake: false, policy: engine.store.agentQuietPolicy,
                                              countsAppInFront: false, countsKeepAwake: false,
                                              cap: engine.store.longAwayCap)
            let reading = sampler.read(now: now, quiet: quiet, film: film, agentSeen: seen,
                                       idlePaused: engine.state == .paused(reason: .idle))
            engine.transition(on: reading.event)
        }
    }

    private static func pingsDuringIdlePauseAreNobodys() -> [String] {
        var problems: [String] = []
        let run = Run()
        for _ in 1...10 { run.minute(ping: true) }               // the agent works ten minutes
        for _ in 11...24 { run.minute() }                        // a fifteen-minute command, no pings
        for _ in 25...30 { run.minute(ping: true) }              // pings again; the user is out
        for _ in 31...89 {
            run.minute()
            if case .awaitingUserDecision = run.engine.state {
                problems.append("asked about an absence at \(Int(run.clock.value.timeIntervalSince(SelfTest.base) / 60))m with nobody back")
                break
            }
        }
        run.minute(input: true)                                  // back at 90m
        if case .awaitingUserDecision(let away, _) = run.engine.state {
            SelfTest.expectClose(away, 80 * 60, "asked about the 80m since the agent's step at 10m", &problems)
        } else {
            problems.append("the absence is asked about on return, got \(run.engine.state)")
        }
        return problems
    }

    private static func filmAfterAgentKeepsWork() -> [String] {
        var problems: [String] = []
        let run = Run()
        for _ in 1...5 { run.minute(input: true) }               // five minutes of typing
        for _ in 6...25 { run.minute(ping: true, film: true) }   // the agent works beside a film
        for _ in 26...64 { run.minute(film: true) }              // the film goes on alone
        run.minute(input: true)
        expect(run.engine.state == .running, "input carries on, got \(run.engine.state)", &problems)
        SelfTest.expectClose(run.engine.elapsed, 25 * 60, "typing and the agent's run are kept, the film is not",
                             &problems)
        return problems
    }

    private static func clockStepBackKeepsQuiet() -> [String] {
        var problems: [String] = []
        var sampler = QuietSampler()
        let now = SelfTest.base
        _ = sampler.read(now: now, quiet: 600, film: false, agentSeen: now, idlePaused: false)
        _ = sampler.read(now: now.addingTimeInterval(300), quiet: 900, film: false, agentSeen: nil, idlePaused: false)
        let stepped = sampler.read(now: now.addingTimeInterval(-1_800), quiet: 960, film: false, agentSeen: nil,
                                   idlePaused: false)
        if case .idleObserved(let seconds) = stepped.event {
            SelfTest.expectClose(seconds, 960, "a future anchor is dropped for the input's own quiet", &problems)
        } else {
            problems.append("quiet with nothing watched is idle, got \(stepped.event)")
        }
        // Once the clock passes where the anchor was, it must not come due.
        let caughtUp = sampler.read(now: now.addingTimeInterval(60), quiet: 2_820, film: false, agentSeen: nil,
                                    idlePaused: true)
        if case .idleObserved(let seconds) = caughtUp.event {
            SelfTest.expectClose(seconds, 2_820, "the dropped anchor stays dropped as the clock catches up",
                                 &problems)
        } else {
            problems.append("quiet with nothing watched is idle, got \(caughtUp.event)")
        }
        return problems
    }

    private static func agentEvidence() -> [String] {
        var problems: [String] = []
        let now = SelfTest.base
        func seen(quiet: TimeInterval = 20 * 60, ping: TimeInterval? = 60, front: String? = nil,
                  keptAwake: Bool = false, policy: AgentQuietPolicy = .countAsWork, appInFront: Bool = false,
                  keepAwakeCounts: Bool = false, cap: TimeInterval = 4 * 3_600) -> Date? {
            AgentPresence.lastSeen(now: now, quiet: quiet, lastActivity: ping.map { now.addingTimeInterval(-$0) },
                                   frontmostBundleID: front, keptAwake: keptAwake, policy: policy,
                                   countsAppInFront: appInFront, countsKeepAwake: keepAwakeCounts, cap: cap)
        }
        expect(seen() == now.addingTimeInterval(-60), "a ping a minute ago is the agent's last step, got \(String(describing: seen()))", &problems)
        expect(seen(ping: AgentPresence.window + 1) == nil, "a ping older than the window is over", &problems)
        expect(seen(ping: nil) == nil, "no ping, no agent", &problems)
        expect(seen(quiet: 2 * 60, ping: 3 * 60) == nil,
               "a ping from before the last keypress says nothing about the quiet since", &problems)
        expect(seen(policy: .ignore) == nil, "agents ignored by choice are not seen", &problems)
        expect(seen(quiet: 4 * 3_600) == nil, "past the cap nobody is here, whatever the agent does", &problems)
        expect(seen(ping: nil, front: "com.anthropic.claudefordesktop") == nil,
               "an agent's window in front needs the user's say-so", &problems)
        expect(seen(ping: nil, front: "com.anthropic.claudefordesktop", appInFront: true) == now,
               "an agent's window in front counts when allowed", &problems)
        expect(seen(ping: nil, front: "com.apple.Safari", appInFront: true) == nil,
               "another app in front is not an agent", &problems)
        expect(seen(ping: nil, front: "com.todesktop.230313mzl4w4u92", appInFront: true) == now,
               "any coding app in front counts when allowed, Cursor among them", &problems)
        expect(seen(ping: nil, keptAwake: true) == nil, "a keep-awake app alone is not you being here", &problems)
        expect(seen(ping: nil, keptAwake: true, keepAwakeCounts: true) == now,
               "a keep-awake app counts when the user says so", &problems)
        expect(seen(ping: nil, keptAwake: true, policy: .ignore, keepAwakeCounts: true) == nil,
               "nothing counts while agents are ignored", &problems)

        let suite = "fc-selftest-agents-\(UUID().uuidString)"
        let prefs = PersistenceStore(defaults: MemoryDefaults.suite(named: suite) ?? .standard)
        expect(prefs.agentQuietPolicy == .countAsWork, "agent time counts as work by default, got \(prefs.agentQuietPolicy)", &problems)
        expect(!prefs.countsAgentAppInFront, "an agent's window in front is off by default", &problems)
        expect(prefs.noticesAppsAtWork, "noticing AI tools at work is on by default", &problems)
        expect(!prefs.countsKeepAwake, "a keep-awake app is off by default", &problems)
        prefs.noticesAppsAtWork = false
        expect(!prefs.noticesAppsAtWork, "turning noticing off is kept", &problems)
        prefs.agentQuietPolicy = .pauseQuietly
        expect(prefs.agentQuietPolicy == .pauseQuietly, "the choice is kept, got \(prefs.agentQuietPolicy)", &problems)
        MemoryDefaults.remove(named: suite)
        return problems
    }

    private static func policiesShapeTheSession() -> [String] {
        var problems: [String] = []
        func run(_ policy: AgentQuietPolicy) -> SessionEngine {
            let clock = TestClock(SelfTest.base)
            let engine = SelfTest.makeEngine(clock)
            engine.store.agentQuietPolicy = policy
            engine.start(workType: .deepWork, intent: "Agent run")
            clock.advance(40 * 60)                              // 10m typing, then 30m watching the agent
            engine.transition(on: .watchingObserved(seconds: 30 * 60, byAgent: true))
            clock.advance(60)
            engine.transition(on: .idleObserved(seconds: 1))    // a keypress
            return engine
        }
        let counted = run(.countAsWork)
        expect(counted.state == .running, "the session keeps running, got \(counted.state)", &problems)
        SelfTest.expectClose(counted.elapsed, 41 * 60, "the agent's half hour is work", &problems)

        let quiet = run(.pauseQuietly)
        expect(quiet.state == .running, "a quiet pause ends on input without a question, got \(quiet.state)",
               &problems)
        SelfTest.expectClose(quiet.elapsed, 10 * 60, "the watched half hour is left out", &problems)

        // The engine's own rule still holds for a film: not work in Deep work.
        let clock = TestClock(SelfTest.base)
        let film = SelfTest.makeEngine(clock)
        film.start(workType: .deepWork, intent: "Film")
        clock.advance(30 * 60)
        film.transition(on: .watchingObserved(seconds: 20 * 60))
        expect(film.state == .paused(reason: .watching),
               "a film still pauses Deep work when agents count, got \(film.state)", &problems)
        return problems
    }

    private static func awayStartsWhenAgentStops() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        let engine = SelfTest.makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Agent run")
        clock.advance(30 * 60)                                  // 10m typing, 20m of agent work
        engine.transition(on: .watchingObserved(seconds: 20 * 60, byAgent: true))
        clock.advance(11 * 60)                                  // the agent stopped 11m ago
        engine.transition(on: .idleObserved(seconds: 11 * 60))
        expect(engine.state == .paused(reason: .idle), "quiet after the agent is idle, got \(engine.state)",
               &problems)
        clock.advance(9 * 60)
        engine.transition(on: .idleObserved(seconds: 1))        // back after 20m away
        if case .awaitingUserDecision(let away, _) = engine.state {
            SelfTest.expectClose(away, 20 * 60, "asked about the 20m after the agent stopped", &problems)
        } else {
            problems.append("a 20m absence after the agent is asked about, got \(engine.state)")
        }
        SelfTest.expectClose(engine.elapsed, 30 * 60, "the agent's 20m stay work", &problems)
        return problems
    }
}
