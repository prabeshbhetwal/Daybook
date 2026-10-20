import Foundation

/// The store runs a break from its ticker: the actions that begin, extend and
/// end one, what a session action does while one runs, and what the reminder
/// log hears. The engine's side is `BreakTakingChecks`'. The rest of this
/// suite is in `BreakStoreNoteChecks` and `BreakStoreLogChecks`.
enum BreakStoreChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Pressing Stop during a break records the break once", stopDuringBreakRecordsOnce),
        ("Automatic sessions wait for a break to end", automationWaitsForBreak),
        ("Work after the planned end closes the break where it began", sustainedEndsBreak),
        ("A taken break restarts the reminders", breakCreditsClock),
        ("Later and Skip are logged against the reminder", actionsAreLogged),
        ("No reminder is due during a break", quietDuringBreak),
        ("Undoing an automatic session during a break leaves no break behind", undoEndsBreak),
        ("A new due break starts its Laters at one, even after an uncredited rest", laterCountRestarts),
        ("Start, Pause and the shortcut end a break first", sessionActionsEndBreak),
        ("The app in front when a break ends is the one the session reads", frontmostFedBack),
        ("A break started after a long absence leaves no old card to show", noStaleLongAwayCard),
        ("The ticker runs through a break, and +5 min brings the over prompt back", tickerAndExtend),
        ("Only a reminder that reached the screen is logged; eyes are counted by day", loggingFollowsDelivery),
        ("A break begun after a reminder answers it, and takes the length it asks for", startAnswersReminder),
        ("Stepping away is ignored on a break, and back is End break", awayIsIgnoredOnBreak),
        ("Every way a break ends restarts the reminders once", everyEndIsSettledOnce),
        ("A break too short to be recorded restarts no reminder", shortBreakCreditsNothing),
        ("+5 min in deep overtime gives five minutes from now", extendFromOvertime),
        ("An end that cannot be saved is reported and tried again every five seconds", failedEndIsReportedAndRetried),
        ("A break nobody came back to ends at its cap, is recorded there, and counts as a rest", capEndIsSettled),
        ("A break that cannot be ended is not walked away from by Stop", refusedEndStopsStop),
        ("A Continue that is refused leaves the break alone", refusedContinueKeepsBreak),
        ("A break restored at launch has its time left before the first tick", restoredBreakIsSeeded),
        ("A break begun after a Later answers the reminder it put off", laterThenStartAnswers),
    ]

    /// A value a check changes after the store has been handed a closure over it.
    final class Box<Value> {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    /// The archive's door: shut for the next `refuseNext` writes, or for all
    /// of them while `refuses`. `attempts` counts the writes it turned away.
    final class Gate {
        var refuses = false
        var refuseNext = 0
        var attempts = 0

        func answer() -> String? {
            if refuseNext > 0 { refuseNext -= 1 } else if !refuses { return nil }
            attempts += 1
            return "You don't have permission to save."
        }
    }

    /// The app in front, as the store's seam reads it.
    typealias Front = (bundleID: String?, name: String)

    struct Fixture {
        let store: SessionStore
        let engine: SessionEngine
        let clock: TestClock
        let persistence: PersistenceStore
        let usage: AppUsageArchive
        /// Seconds since the last input; nobody is at the keys unless a check says so.
        let idle: Box<TimeInterval>
        let front: Box<Front?>
        let gate: Gate
        /// Whether any app is running, for the Continue that needs one.
        let appRunning: Box<Bool>
        let suite: String

        func close() { MemoryDefaults.remove(named: suite) }

        /// One unbroken stretch of use, as minutes after `SelfTest.base`.
        func work(_ from: Double, _ to: Double) {
            usage.record(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                         start: SelfTest.base.addingTimeInterval(from * 60),
                                         end: SelfTest.base.addingTimeInterval(to * 60)))
        }

        /// Moves the clock to `minutes` after `SelfTest.base`.
        func go(toMinute minutes: Double) {
            clock.value = SelfTest.base.addingTimeInterval(minutes * 60)
        }

        var breaks: [SessionRecord] { engine.archive.records.filter { $0.workType == .breakTime } }

        /// The rule-driven start of an automatic session, as the detector sends it.
        func autoAction(generation: UInt64 = 1) -> ActivityAutomaticAction {
            ActivityRuleChecks.action(rule: ActivityRuleChecks.codingID, name: "Coding", type: .deepWork,
                                      start: clock.value.addingTimeInterval(-120), end: clock.value,
                                      version: persistence.activityRuleVersion, generation: generation)
        }
    }

    /// `prepare` runs on the engine before the store is built, because the
    /// store reads the engine's state once when it starts and afterwards
    /// hears of engine changes on a later pass of the run loop. `calendar`
    /// is the one the store works its days out in, and the break log keys
    /// them by.
    @MainActor
    static func make(ticker: Bool = false, rules: Bool = false, calendar: Calendar? = nil,
                     prepare: (SessionEngine, TestClock) -> Void = { _, _ in }) -> Fixture? {
        let suite = "fc-selftest-break-store-\(UUID().uuidString)"
        guard let defaults = MemoryDefaults.suite(named: suite) else { return nil }
        let clock = TestClock(SelfTest.base)
        let gate = Gate()
        let archive = SessionArchive(directory: SelfTest.scratchDirectory(), now: { clock.value },
                                     writeOverride: { _ in gate.answer() })
        let persistence = PersistenceStore(defaults: defaults)
        if rules {
            persistence.activityRules = ActivityRuleChecks.rules
            persistence.activityRuleAutomationEnabled = true
        }
        let engine = SessionEngine(store: persistence, archive: archive, ownBundleID: "com.test",
                                   schedulesDwell: false, now: { clock.value })
        prepare(engine, clock)
        let idle = Box<TimeInterval>(600)
        let front = Box<Front?>(nil)
        let appRunning = Box<Bool>(false)
        let store = SessionStore(engine: engine, schedulesTicker: ticker,
                                 breakLog: calendar.map { BreakLog(directory: engine.archive.dataDirectoryURL, calendar: $0) },
                                 applicationIsRunning: { _ in appRunning.value },
                                 activateApplication: { _, _ in }, now: { clock.value },
                                 idle: IdleMonitor(idleSeconds: { idle.value }),
                                 frontmostApplication: { front.value })
        let usage = AppUsageArchive(directory: SelfTest.scratchDirectory(), now: { clock.value })
        store.usage = usage
        if let calendar { store.periodCalendarBase = calendar }
        return Fixture(store: store, engine: engine, clock: clock, persistence: persistence,
                       usage: usage, idle: idle, front: front, gate: gate, appRunning: appRunning,
                       suite: suite)
    }

    /// A session of 20 minutes, already running when the store starts.
    static let running: (SessionEngine, TestClock) -> Void = { engine, clock in
        engine.start(workType: .deepWork, intent: "Parser")
        clock.advance(1_200)
    }

    /// The same, but the app's own guess. Ownership lives in the saved state;
    /// starting never keeps it.
    static let autoRunning: (SessionEngine, TestClock) -> Void = { engine, clock in
        engine.start(workType: .deepWork, intent: "Detected")
        clock.advance(1_200)
        var snapshot = engine.snapshot()
        snapshot.isAuto = true
        engine.restore(from: snapshot)
    }

    // MARK: - Brief checks

    private static func stopDuringBreakRecordsOnce() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let f = make(prepare: running) else { return ["could not create isolated preferences"] }
            defer { f.close() }
            f.store.startBreak()
            expect(f.store.isOnBreak && f.engine.state == .paused(reason: .onBreak),
                   "the break begins, got \(f.engine.state)", &problems)
            f.clock.advance(400)
            f.store.stop()
            let records = f.engine.archive.records
            expect(f.breaks.count == 1 && f.breaks.first?.workSeconds == 400,
                   "one break of 400 s, got \(f.breaks.map(\.workSeconds))", &problems)
            expect(!records.contains { $0.workType != .breakTime && $0.workSeconds < 30 },
                   "no empty stretch is left behind", &problems)
            expect(records.filter { $0.workType != .breakTime }.count == 1,
                   "the stretch before the break is kept once", &problems)
            expect(f.engine.state == .idle && f.engine.activeBreak == nil && !f.store.isOnBreak,
                   "stopped with no break left running", &problems)
            return problems
        }
    }

    private static func automationWaitsForBreak() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let f = make(prepare: running) else { return ["could not create isolated preferences"] }
            defer { f.close() }
            expect(!f.store.automationWaits, "nothing waits before the break", &problems)
            f.store.startBreak()
            expect(f.store.automationWaits, "automation waits while on a break", &problems)
            expect(!f.store.hasUnresolvedAwayDecision,
                   "an away question is not what it waits for", &problems)
            f.store.startAutomatically(workType: .deepWork, name: "Detected", backdatedTo: f.clock.value,
                                       because: "check")
            expect(f.engine.state == .paused(reason: .onBreak) && f.engine.sessionName == "Parser",
                   "an automatic start leaves the break alone, got \(f.engine.state)", &problems)
            f.store.endBreak()
            expect(!f.store.automationWaits, "automation goes on once the break is over", &problems)

            // The rules' start waits too: on a break with no session behind it,
            // where nothing else would stop a session starting beside it.
            guard let g = make(rules: true) else { return problems + ["could not create isolated preferences"] }
            defer { g.close() }
            g.store.startBreak()
            expect(g.store.applyAutomaticActivity(g.autoAction()) == nil && g.engine.state == .idle,
                   "an activity rule starts nothing beside a break, got \(g.engine.state)", &problems)
            g.store.endBreak()
            expect(g.store.applyAutomaticActivity(g.autoAction(generation: 2)) != nil && g.engine.state == .running,
                   "and starts the session once the break is over", &problems)
            return problems
        }
    }

    private static func sustainedEndsBreak() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let f = make(prepare: running) else { return ["could not create isolated preferences"] }
            defer { f.close() }
            f.store.startBreak(length: 300)
            f.clock.advance(300)

            // Ninety seconds of nobody there: the planned time is up and nothing closes.
            for _ in 0..<90 { f.store.runTick(); f.clock.advance(1) }
            expect(f.store.isOnBreak, "a quiet Mac does not end the break", &problems)

            // Fifty-nine seconds of input is a glance, however it is followed.
            f.idle.value = 0
            for _ in 0..<59 { f.store.runTick(); f.clock.advance(1) }
            f.idle.value = 600
            for _ in 0..<91 { f.store.runTick(); f.clock.advance(1) }
            expect(f.store.isOnBreak, "59 seconds of input is still a break", &problems)

            // Sixty seconds is work, and the break ends where it began.
            f.idle.value = 0
            let began = f.clock.value
            for _ in 0..<60 { f.store.runTick(); f.clock.advance(1) }
            expect(!f.store.isOnBreak && f.engine.state == .running,
                   "work closes the break and the session goes on, got \(f.engine.state)", &problems)
            expect(f.breaks.count == 1 && f.breaks.first?.end == began,
                   "the break ends where the work began", &problems)
            expect(f.engine.sessionStartDate == began, "and the new stretch starts there", &problems)
            expect(f.persistence.breakClock.floors.count == BreakTier.allCases.count,
                   "and the rest counts", &problems)

            // Work from the planned end closes the break at the planned end.
            guard let g = make(prepare: running) else { return problems + ["could not create isolated preferences"] }
            defer { g.close() }
            g.store.startBreak(length: 300)
            let planned = g.store.activeBreak?.plannedEnd
            g.clock.advance(300)
            g.idle.value = 0
            for _ in 0..<60 { g.store.runTick(); g.clock.advance(1) }
            expect(!g.store.isOnBreak && g.breaks.first?.end == planned,
                   "work from the planned end closes the break at the planned end", &problems)
            return problems
        }
    }

    private static func breakCreditsClock() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let f = make(prepare: running) else { return ["could not create isolated preferences"] }
            defer { f.close() }
            expect(f.persistence.breakClock.floors.isEmpty, "no rest is credited yet", &problems)
            var began = 0, ended = 0
            f.store.onBreakBegan = { began += 1 }
            f.store.onBreakEnded = { ended += 1 }
            f.store.startBreak()
            expect(began == 1 && ended == 0, "starting announces the break once, got \(began)", &problems)
            f.clock.advance(120)
            f.store.endBreak()
            expect(began == 1 && ended == 1, "ending announces the end once, got \(ended)", &problems)
            let floors = f.persistence.breakClock.floors
            expect(floors.count == BreakTier.allCases.count, "every tier restarts, got \(floors.count)", &problems)
            expect(Set(floors.values) == [f.clock.value], "each restarts at the end of the break", &problems)
            expect(f.store.breakRemaining == 0, "nothing is left to count down", &problems)
            return problems
        }
    }
}
