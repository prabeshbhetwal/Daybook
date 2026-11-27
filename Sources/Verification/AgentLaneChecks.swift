import Foundation

/// The Agent lane (docs/specs/2026-11-27-agent-lane-design.md): an agent's run
/// with nobody at the keyboard is recorded apart from the person's time, kept
/// across relaunches and splits, and counted toward goals only as the person
/// chose and only up to the unattended limit.
enum AgentLaneChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A new Mac tracks agent time separately; one that counted it before keeps counting it",
         settingsAndMigration),
        ("An agent's run is recorded from its first signal past your short quiet to its last signal",
         spanEdges),
        ("A relaunch keeps the Agent lane, and never past the checkpoint", restoreKeepsLane),
        ("A split gives each half its part of an agent's run, and merging back restores it",
         splitAndMerge),
        ("Goals count only your time, or yours and the agent's up to the unattended limit",
         goalsFollowTheSetting),
        ("Time in the Agent lane is the agent app's, never the person's credit", creditKeepsLaneApart),
        ("A session shows You and Agent only when the Agent lane holds time", laneSplitText),
        ("The menu panel clock shows You and Agent beneath it once an agent has held the session",
         panelLaneLine),
    ]

    private static let editor = "com.microsoft.VSCode"
    private static func at(_ minutes: Double) -> Date { SelfTest.base.addingTimeInterval(minutes * 60) }

    private static func settingsAndMigration() -> [String] {
        var problems: [String] = []
        func store(_ prepare: (UserDefaults) -> Void) -> (PersistenceStore, String) {
            let suite = "fc-selftest-agentlane-\(UUID().uuidString)"
            let defaults = MemoryDefaults.suite(named: suite) ?? .standard
            prepare(defaults)
            return (PersistenceStore(defaults: defaults), suite)
        }
        let (fresh, a) = store { _ in }
        expect(fresh.agentQuietPolicy == .trackSeparately, "a new Mac tracks agent time separately, got \(fresh.agentQuietPolicy)", &problems)
        expect(fresh.agentUnattendedLimit == 3_600, "the unattended limit is an hour, got \(fresh.agentUnattendedLimit)", &problems)
        fresh.settleAgentQuietPolicy(isExistingInstall: false)
        fresh.settleAgentQuietPolicy(isExistingInstall: true)
        expect(fresh.agentQuietPolicy == .trackSeparately,
               "a Mac settled as new is never taken for an old install later, got \(fresh.agentQuietPolicy)", &problems)
        fresh.agentUnattendedLimit = FocusConstants.never
        expect(FocusConstants.isNever(fresh.agentUnattendedLimit), "No limit is kept", &problems)
        // An install from before the welcome has history but no welcome flag: the caller's rule says existing.
        let (old, b) = store { _ in }
        old.settleAgentQuietPolicy(isExistingInstall: true)
        expect(old.agentQuietPolicy == .countAsWork,
               "a Mac that ran the app before keeps agent time with its own, got \(old.agentQuietPolicy)", &problems)
        let (chose, c) = store { $0.set("pauseQuietly", forKey: "fc.agentQuietPolicy") }
        chose.settleAgentQuietPolicy(isExistingInstall: true)
        expect(chose.agentQuietPolicy == .pauseQuietly, "a choice already made is kept, got \(chose.agentQuietPolicy)", &problems)
        [a, b, c].forEach { MemoryDefaults.remove(named: $0) }
        return problems
    }

    private static func spanEdges() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        let engine = SelfTest.makeEngine(clock)
        engine.store.idlePauseThreshold = 5 * 60
        engine.start(workType: .deepWork, intent: "Agent run")
        // Typing to 10m; the agent's first signal at 10m30s, its last at 40m.
        for minute in stride(from: 11.0, through: 41, by: 1) {
            clock.advance(minute == 11 ? 11 * 60 : 60)
            engine.noteAgentAtWork(first: at(10.5), signal: at(min(minute, 40)), lastInput: at(10), app: editor)
        }
        // Six quiet minutes after the agent's last step: the idle pause goes back to it.
        clock.advance(5 * 60)
        engine.transition(on: .idleObserved(seconds: 6 * 60))
        let lane = engine.runningAgentSpans ?? []
        // The first five quiet minutes (the idle threshold) are still yours.
        let expected = [AgentSpan(start: at(15), end: at(40), since: at(10), app: editor)]
        expect(lane == expected, "one span from the end of your short quiet to the last signal, got \(lane)", &problems)
        engine.transition(on: .resetSession)
        let record = engine.archive.records.last
        expect(record?.agentSpans == expected, "the record keeps the span, got \(String(describing: record?.agentSpans))", &problems)
        expect(engine.runningAgentSpans == [], "a fresh session starts with an empty lane", &problems)

        // An agent that stops inside your short quiet leaves no lane; one silent past the
        // presence window starts a new span rather than bridge the gap.
        let gaps = SelfTest.makeEngine(clock)
        gaps.store.idlePauseThreshold = 5 * 60
        gaps.start(workType: .deepWork, intent: "Gaps")
        let began = clock.value
        func signal(_ minute: Double) {
            clock.advance(began.addingTimeInterval(minute * 60).timeIntervalSince(clock.value))
            gaps.noteAgentAtWork(first: began.addingTimeInterval(60), signal: clock.value, lastInput: began, app: editor)
        }
        for minute in [1.0, 2, 3, 4] { signal(minute) }
        expect(gaps.runningAgentSpans == [], "agent signals inside your short quiet leave no lane, got \(String(describing: gaps.runningAgentSpans))", &problems)
        for minute in [6.0, 8, 10, 20, 21] { signal(minute) }
        let pieces = (gaps.runningAgentSpans ?? []).map { ($0.start.timeIntervalSince(began) / 60, $0.end.timeIntervalSince(began) / 60) }
        expect(pieces.count == 2 && pieces[0] == (5, 10) && pieces[1] == (20, 21),
               "two spans, 5 to 10 and 20 to 21 minutes, got \(pieces)", &problems)

        let paused = SelfTest.makeEngine(clock)
        paused.store.agentQuietPolicy = .pauseQuietly
        paused.start(workType: .deepWork, intent: "Paused")
        clock.advance(60)
        paused.noteAgentAtWork(first: clock.value, signal: clock.value, lastInput: at(0), app: editor)
        expect(paused.runningAgentSpans == [], "Pause the session records no lane, got \(String(describing: paused.runningAgentSpans))", &problems)
        return problems
    }

    private static func restoreKeepsLane() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        let engine = SelfTest.makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Agent run")
        clock.advance(30 * 60)
        engine.noteAgentAtWork(first: at(10), signal: at(30), lastInput: at(9), app: editor)
        var snapshot = engine.snapshot()
        expect(snapshot.agentSpans?.count == 1, "the checkpoint carries the lane, got \(String(describing: snapshot.agentSpans))", &problems)
        // A span reaching past the checkpoint (a clock stepped back) closes there.
        snapshot.agentSpans = [AgentSpan(start: at(10), end: at(45), since: at(9), app: editor)]
        let restored = SelfTest.makeEngine(clock)
        restored.restore(from: snapshot)
        let lane = restored.runningAgentSpans ?? []
        expect(lane.count == 1 && lane.first?.end == snapshot.savedAt,
               "the lane is kept and ends at the checkpoint, got \(lane)", &problems)
        var legacy = snapshot
        legacy.agentSpans = nil
        let old = SelfTest.makeEngine(clock)
        old.restore(from: legacy)
        expect(old.runningAgentSpans == nil, "a session from before the lane has none, got \(String(describing: old.runningAgentSpans))", &problems)
        return problems
    }

    private static func splitAndMerge() -> [String] {
        var problems: [String] = []
        let span = AgentSpan(start: at(60), end: at(120), since: at(55), app: editor)
        let record = SessionRecord(name: "Run", workType: .deepWork, start: at(0), end: at(180), workSeconds: 180 * 60,
                                   pausedSpans: [], agentSpans: [span])
        guard let cut = record.split(at: at(90), tail: SplitTail(name: "Tail", workType: .deepWork, source: .user,
                                                                  nameByApp: false)) else {
            return ["the record splits at 90m"]
        }
        expect(cut.head.agentSpans == [AgentSpan(start: at(60), end: at(90), since: at(55), app: editor)],
               "the head keeps the run up to the cut, got \(String(describing: cut.head.agentSpans))", &problems)
        expect(cut.tail.agentSpans == [AgentSpan(start: at(90), end: at(120), since: at(55), app: editor)],
               "the tail keeps the rest, measured from the same input, got \(String(describing: cut.tail.agentSpans))", &problems)
        let joined = SessionRecord.merged(head: cut.head, tail: cut.tail)
        expect(joined == record, "merging back restores the record exactly, got \(String(describing: joined?.agentSpans))", &problems)
        return problems
    }

    /// Five hours filed as Deep work; hands on for the first two; an agent from 1h to 5h.
    private static func goalsFollowTheSetting() -> [String] {
        var problems: [String] = []
        let lane = [AgentSpan(start: at(60), end: at(300), since: at(60), app: editor)]
        let record = SessionRecord(name: "Run", workType: .deepWork, start: at(0), end: at(300), workSeconds: 300 * 60,
                                   pausedSpans: [], agentSpans: lane)
        let usage = [AppUsageSession(bundleID: editor, appName: "Code", start: at(0), end: at(120), endReason: .idle)]
        func goal(_ rule: AgentGoalRule, records: [SessionRecord] = [record]) -> TimeInterval {
            FocusedActiveTime.seconds(in: DateInterval(start: at(0), end: at(300)), records: records, usage: usage,
                                      running: nil, agent: rule)
        }
        let hour: TimeInterval = 3_600
        SelfTest.expectClose(goal(.youOnly), hour, "Track separately counts only your hour", &problems)
        SelfTest.expectClose(goal(AgentGoalRule(policy: .countAsWork, limit: hour)), 2 * hour,
                             "Count with my time adds the agent's first hour, never twice where you overlap", &problems)
        SelfTest.expectClose(goal(AgentGoalRule(policy: .countAsWork, limit: 2 * hour)), 3 * hour,
                             "a two-hour limit adds two hours", &problems)
        SelfTest.expectClose(goal(AgentGoalRule(policy: .countAsWork, limit: FocusConstants.never)), 5 * hour,
                             "No limit adds the whole run", &problems)
        SelfTest.expectClose(goal(AgentGoalRule(policy: .pauseQuietly, limit: hour)), hour,
                             "Pause the session counts no recorded lane", &problems)
        var legacy = record
        legacy.agentSpans = nil
        SelfTest.expectClose(goal(.youOnly, records: [legacy]), 2 * hour,
                             "a record from before the lane counts as it always did", &problems)
        // Another record already counts 1h to 2h as yours: the agent's hour there is not added again.
        let other = SessionRecord(name: "Other", workType: .deepWork, start: at(60), end: at(120), workSeconds: hour)
        SelfTest.expectClose(goal(AgentGoalRule(policy: .countAsWork, limit: hour), records: [record, other]), 2 * hour,
                             "a minute counted by two records counts once", &problems)
        return problems
    }

    private static func creditKeepsLaneApart() -> [String] {
        var problems: [String] = []
        let beats = BeatTrace.beats([BeatTrace.Step(app: editor, minutes: 1, input: .keys),
                                     BeatTrace.Step(app: "com.apple.Safari", minutes: 4, input: .none, presence: .agent)],
                                    from: at(0))
        let counted = [DateInterval(start: at(0), end: at(5))]
        func credit(_ agent: [AgentSpan]?) -> [CreditedSlice] {
            ActivityCredit.credit(CreditInput(beats: beats, counted: counted, signals: [], purposeOverrides: [:], agent: agent))
        }
        let lane = credit([AgentSpan(start: at(1), end: at(5), since: at(1), app: editor)])
        let inLane = lane.filter { $0.start >= at(1) }
        expect(!inLane.isEmpty && inLane.allSatisfy { $0.state == .agent && $0.purpose == .coding },
               "the run is the agent's, in its app's category, got \(inLane.map { "\($0.state) \(String(describing: $0.purpose))" })", &problems)
        let mine = ActivityDerivation.purposeSeconds(lane)[.coding] ?? 0
        SelfTest.expectClose(mine, 60, "only the typed minute is the person's credit", &problems)
        let legacy = ActivityDerivation.purposeSeconds(credit(nil))[.coding] ?? 0
        SelfTest.expectClose(legacy, 300, "a session from before the lane credits the run as it always did", &problems)
        return problems
    }

    private static func laneSplitText() -> [String] {
        var problems: [String] = []
        let line = Tokens.laneSplit(worked: (11 * 60 + 49) * 60, agent: (3 * 60 + 28) * 60)
        expect(line == "You 8h 21m · Agent 3h 28m", "the hero line reads both lanes, got \(String(describing: line))", &problems)
        expect(Tokens.laneSplit(worked: 3_600, agent: 0) == nil, "no agent time shows no split", &problems)
        expect(Tokens.laneSplit(worked: 3_600, agent: 30) == nil, "under a minute never reads Agent 0m", &problems)
        // History rows: a record from before the lane carries nothing; one with a lane carries its time.
        let old = SessionRecord(name: "Old", workType: .deepWork, start: at(0), end: at(60), workSeconds: 3_600)
        var new = SessionRecord(name: "New", workType: .deepWork, start: at(70), end: at(130), workSeconds: 3_600,
                                pausedSpans: [], agentSpans: [AgentSpan(start: at(90), end: at(120), since: at(85))])
        new.threadID = UUID()
        let rows = SessionDigest.entries(records: [old, new], running: nil, now: at(200), day: at(0))
            .compactMap { entry -> DaySession? in if case .session(let s) = entry { return s } else { return nil } }
        expect(rows.map(\.agent) == [0, 1_800], "rows carry 0 and 30 minutes of agent time, got \(rows.map(\.agent))", &problems)
        return problems
    }

    /// The panel hero draws `Tokens.laneSplit(worked: store.elapsed, agent: store.agentElapsed)`.
    private static func panelLaneLine() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let store = FixtureFactory.store(for: .running)
            expect(store.agentElapsed == 0 && Tokens.laneSplit(worked: store.elapsed, agent: store.agentElapsed) == nil,
                   "a session no agent touched shows no line, got agent \(store.agentElapsed)", &problems)
            let start = store.engine.sessionStartDate
            store.engine.noteAgentAtWork(first: start.addingTimeInterval(660), signal: start.addingTimeInterval(2_712),
                                         lastInput: start, app: "com.apple.Terminal")
            store.refresh()
            SelfTest.expectClose(store.agentElapsed, 2_052, "the store publishes the running lane", &problems)
            let line = Tokens.laneSplit(worked: store.elapsed, agent: store.agentElapsed)
            expect(line == "You 11m · Agent 34m", "the panel reads both lanes, got \(String(describing: line))", &problems)
            return problems
        }
    }
}
