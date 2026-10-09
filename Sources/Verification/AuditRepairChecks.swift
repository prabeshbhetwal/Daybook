import Foundation

/// The five defects the 2026-10-06 audit found and a second pass confirmed on
/// main 51ebed7: an interrupted Stop that wedged the session, a relaunch that
/// threw away a session's exact pauses, goal credit for app use inside a known
/// pause, a session strip that dropped its last stretches, and retired
/// categories that rules and fallbacks still started.
enum AuditRepairChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A Stop cut off between its record and its idle state ends cleanly on relaunch",
         interruptedStopEnds),
        ("A relaunch mid-session keeps the offline gap and every earlier pause exact",
         relaunchKeepsExactPauses),
        ("Goal credit skips app use inside a known pause, saved or running",
         goalCreditSkipsPauses),
        ("The session strip draws every stretch, the last one included",
         stripDrawsEveryStretch),
        ("A retired category starts nothing new: rules, defaults and saved activities move on",
         retiredCategoryStartsNothing),
        ("The live goal gives no credit for app use while the running session is paused",
         liveGoalSkipsPause),
        ("Every start from idle, and the picker, move off a retired category",
         startsMoveOffRetired),
        ("An automatic action for a retired category is refused before it starts",
         retiredRuleActionRefused),
    ]

    /// An engine whose defaults and archive survive a relaunch, as the app's do.
    private final class Machine {
        let clock = TestClock(SelfTest.base)
        let suite = "fc-selftest-audit-\(UUID().uuidString)"
        let directory = SelfTest.scratchDirectory()
        lazy var defaults = MemoryDefaults.suite(named: suite)!
        var engine: SessionEngine!

        init() {
            engine = make()
            engine.store.longAwayCap = 4 * 3_600
        }

        func make() -> SessionEngine {
            let clock = self.clock
            return SessionEngine(store: PersistenceStore(defaults: defaults),
                                 archive: SessionArchive(directory: directory, now: { clock.value }),
                                 ownBundleID: "fc.audit.fixture", schedulesDwell: false,
                                 now: { clock.value })
        }

        /// Quit, wait, and launch again through the coordinator's one call.
        func relaunch(after offline: TimeInterval) {
            clock.advance(offline)
            engine = make()
            if let saved = engine.store.loadState() { engine.restore(from: saved) }
        }

        func close() { defaults.removePersistentDomain(forName: suite) }
    }

    private static func interruptedStopEnds() -> [String] {
        var problems: [String] = []
        let machine = Machine(); defer { machine.close() }
        machine.engine.start(workType: .deepWork, intent: "Writing")
        machine.clock.advance(1_200)
        machine.engine.persist()
        guard let running = machine.engine.store.loadState() else {
            return ["The running session left no snapshot to restore"]
        }
        expect(machine.engine.stop(), "the first Stop should save", &problems)
        // Killed after the record was written, before the idle state was.
        machine.engine.store.saveState(running)
        machine.relaunch(after: 30)
        expect(machine.engine.state == .idle,
               "a session whose record is already saved should restore as ended, got \(machine.engine.state)",
               &problems)
        expect(machine.engine.archive.records.count == 1,
               "the saved record should stand alone, got \(machine.engine.archive.records.count)", &problems)
        machine.engine.start(workType: .deepWork, intent: "Reading")
        machine.clock.advance(600)
        expect(machine.engine.stop(), "the next session should start and stop, got \(machine.engine.awayDecisionError ?? "no error")",
               &problems)
        expect(machine.engine.archive.records.count == 2,
               "both sessions should be saved, got \(machine.engine.archive.records.count)", &problems)
        return problems
    }

    private static func relaunchKeepsExactPauses() -> [String] {
        var problems: [String] = []
        let machine = Machine(); defer { machine.close() }
        let start = machine.clock.value
        machine.engine.start(workType: .deepWork, intent: "Writing")
        machine.clock.advance(600)
        machine.engine.transition(on: .manualPause)
        let pause = (start: machine.clock.value, end: machine.clock.value.addingTimeInterval(1_800))
        machine.clock.advance(1_800)
        machine.engine.transition(on: .manualResume)
        machine.clock.advance(600)
        machine.engine.persist()
        let offline = (start: machine.clock.value, end: machine.clock.value.addingTimeInterval(60))
        machine.relaunch(after: 60)
        machine.clock.advance(60)
        machine.engine.stop()
        guard let record = machine.engine.archive.records.first(where: { $0.start == start }) else {
            return ["The session was not saved"]
        }
        expect(record.exactPausedSpans != nil, "the record's pauses should still add up after a relaunch", &problems)
        SelfTest.expectClose(record.workSeconds, 1_260, "work around the pause and the relaunch", &problems)
        SelfTest.expectClose(record.workSeconds(in: pause), 0, "work inside the pressed pause", &problems)
        SelfTest.expectClose(record.workSeconds(in: offline), 0, "work while the app was closed", &problems)
        return problems
    }

    private static func goalCreditSkipsPauses() -> [String] {
        var problems: [String] = []
        let start = SelfTest.base
        let hour: TimeInterval = 3_600
        let window = DateInterval(start: start.addingTimeInterval(-hour), duration: 4 * hour)
        let paused = DateInterval(start: start, duration: hour)
        let record = SessionRecord(name: "Writing", workType: .deepWork,
                                   start: start, end: start.addingTimeInterval(2 * hour),
                                   workSeconds: hour, pausedSpans: [paused])
        func use(_ from: TimeInterval, _ to: TimeInterval) -> [AppUsageSession] {
            [AppUsageSession(bundleID: "com.example.video", appName: "Video",
                             start: start.addingTimeInterval(from), end: start.addingTimeInterval(to))]
        }
        let inPause = FocusedActiveTime.seconds(in: window, records: [record], usage: use(0, hour), running: nil)
        SelfTest.expectClose(inPause, 0, "credit for a saved session's app use inside its pause", &problems)
        let inWork = FocusedActiveTime.seconds(in: window, records: [record], usage: use(hour, 2 * hour), running: nil)
        SelfTest.expectClose(inWork, hour, "credit for a saved session's app use while working", &problems)
        let live = FocusedActiveTime.seconds(in: window, records: [], usage: use(0, hour),
                                             running: (start: start, end: start.addingTimeInterval(2 * hour)),
                                             runningWork: hour, runningPaused: [paused])
        SelfTest.expectClose(live, 0, "credit for a running session's app use inside its pause", &problems)
        return problems
    }

    private static func stripDrawsEveryStretch() -> [String] {
        var problems: [String] = []
        let start = SelfTest.base
        /// Stretches of the given lengths, a minute apart, each fully used.
        func activity(_ lengths: [TimeInterval]) -> (RecordedActivity, DateInterval) {
            var spans: [DateInterval] = []
            var cursor = start
            for length in lengths {
                spans.append(DateInterval(start: cursor, duration: length))
                cursor = cursor.addingTimeInterval(length + 60)
            }
            let segments = spans.map {
                TimelineSegment(id: UUID(), bundleID: "com.example.editor", appName: "Editor",
                                start: $0.start, end: $0.end, colorIndex: 0, endReason: .appSwitch)
            }
            return (RecordedActivity(segments: segments, spans: spans), spans[spans.count - 1])
        }
        let cases: [(String, [TimeInterval], Int)] = [
            ("eight minutes then an hour in 8 cells", Array(repeating: 60, count: 8) + [3_600], 8),
            ("eight quarter-hours in the Day Story's 21 cells", Array(repeating: 900, count: 8), 21),
            ("five ten-minute stretches in 8 cells", Array(repeating: 600, count: 5), 8),
            ("twenty-five two-minute stretches and an hour in 21 cells",
             Array(repeating: 120, count: 25) + [3_600], 21),
        ]
        for (name, lengths, cells) in cases {
            let (shape, last) = activity(lengths)
            let runs = SessionShape.runs(activity: shape, cellCount: cells)
            let used = runs.reduce(0) { $0 + $1.cells }
            expect(used == cells, "\(name): every cell should be drawn, got \(used)", &problems)
            expect(runs.last?.end == last.end,
                   "\(name): the strip should reach the last stretch's end \(last.end), got \(String(describing: runs.last?.end))",
                   &problems)
        }
        return problems
    }

    private static func retiredCategoryStartsNothing() -> [String] {
        var problems: [String] = []
        let suite = "fc-selftest-audit-categories-\(UUID().uuidString)"
        let defaults = MemoryDefaults.suite(named: suite) ?? .standard
        defer {
            defaults.removePersistentDomain(forName: suite)
            WorkTypeCatalog.shared.apply(customisations: [])
        }
        let calls = WorkType(rawValue: "custom.audit-calls")
        WorkTypeCatalog.shared.apply(customisations: [
            WorkTypeDefinition(id: calls.rawValue, name: "Calls", symbolName: "phone.fill",
                               hue: .green, isRetired: true)
        ])
        let app = "com.example.calls"
        let rule = [ActivityRule(id: UUID(), name: "Calls", workType: calls,
                                 bundleIDs: [app], isEnabled: true, startAfter: 60)]
        var detector = ActivityRuleDetector()
        _ = detector.evaluate(ActivityRuleChecks.input(at: 0, app: app, customRules: rule))
        let due = detector.evaluate(ActivityRuleChecks.input(at: 60, app: app, customRules: rule))
        if case .start = due { problems.append("A rule for a retired category still started a session") }

        // Made first: a new store installs its own catalogue, which would
        // put Deep work back before the fallbacks are read.
        let store = PersistenceStore(defaults: defaults)
        store.removeAll()
        var deep = WorkTypeCatalog.shared.definition(for: .deepWork)
        deep.isRetired = true
        WorkTypeCatalog.shared.apply(customisations: [deep])
        let offered = WorkType.startable
        expect(!offered.contains(.deepWork), "Deep work should be retired for this check", &problems)
        expect(offered.contains(store.defaultWorkType),
               "with Deep work retired, the default should be a category still offered, got \(store.defaultWorkType.rawValue)",
               &problems)
        let saved = SavedActivity(name: "Writing", workType: .deepWork).startableWorkType
        expect(offered.contains(saved),
               "with Deep work retired, a saved activity should start under one still offered, got \(saved.rawValue)",
               &problems)
        let suggested = CategoryManager(store: store).suggestedWorkType(for: "com.apple.dt.Xcode")
        expect(offered.contains(suggested),
               "with Deep work retired, Xcode's suggestion should be a category still offered, got \(suggested.rawValue)",
               &problems)
        return problems
    }

    private static func liveGoalSkipsPause() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let dayStart = Calendar.current.startOfDay(for: SelfTest.anchoredNow())
            let clock = TestClock(dayStart.addingTimeInterval(10 * 3_600))
            let directory = SelfTest.scratchDirectory()
            let suite = "fc-selftest-audit-goal-\(UUID().uuidString)"
            let defaults = MemoryDefaults.suite(named: suite) ?? .standard
            defer { defaults.removePersistentDomain(forName: suite) }
            let persistence = PersistenceStore(defaults: defaults)
            persistence.removeAll()
            let engine = SessionEngine(store: persistence,
                                       archive: SessionArchive(directory: directory, now: { clock.value }),
                                       ownBundleID: "com.example.self", schedulesDwell: false,
                                       now: { clock.value })
            engine.start(workType: .deepWork, intent: "Reading")
            let usage = AppUsageArchive(directory: directory, now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            let store = SessionStore(engine: engine, now: { clock.value })
            store.attach(tracker: tracker, usage: usage)
            // Ten minutes reading on paper, then a pause spent in an app.
            clock.advance(600)
            engine.transition(on: .manualPause)
            tracker.appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode")
            clock.advance(600)
            store.updateTimeDrivenFigures()
            SelfTest.expectClose(store.goal.achieved, 0, "the goal bar for app use inside the open pause", &problems)
            SelfTest.expectClose(store.focusedActiveSeconds(on: clock.value), 0,
                                 "today's credit for app use inside the open pause", &problems)
            return problems
        }
    }

    private static func startsMoveOffRetired() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let machine = Machine()
            defer { machine.close(); WorkTypeCatalog.shared.apply(customisations: []) }
            let store = SessionStore(engine: machine.engine, schedulesTicker: false, now: { machine.clock.value })
            let calls = WorkType(rawValue: "custom.audit-calls")
            WorkTypeCatalog.shared.apply(customisations: [
                WorkTypeDefinition(id: calls.rawValue, name: "Calls", symbolName: "phone.fill", hue: .green)
            ])
            store.workType = calls
            // The last session ran as Deep work, the kind the legacy start reuses.
            machine.engine.start(workType: .deepWork, intent: "Writing")
            machine.clock.advance(600)
            machine.engine.stop()
            // Calls alone first, so the default stays put and only the
            // picker's own check can move it.
            let retiredCalls = WorkTypeDefinition(id: calls.rawValue, name: "Calls", symbolName: "phone.fill",
                                                  hue: .green, isRetired: true)
            WorkTypeCatalog.shared.apply(customisations: [retiredCalls])
            store.refresh()
            expect(WorkType.startable.contains(store.workType),
                   "the picker should leave a retired category, got \(store.workType.rawValue)", &problems)
            var deep = WorkTypeCatalog.shared.definition(for: .deepWork)
            deep.isRetired = true
            WorkTypeCatalog.shared.apply(customisations: [retiredCalls, deep])
            let offered = WorkType.startable
            // The legacy heuristic starts from a work app under the last kind.
            machine.engine.transition(on: .appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode"))
            expect(machine.engine.state != .idle, "the legacy work-app start should still start", &problems)
            expect(offered.contains(machine.engine.activeWorkType),
                   "a work-app start should begin under a category still offered, got \(machine.engine.activeWorkType.rawValue)",
                   &problems)
            machine.clock.advance(600)
            machine.engine.stop()
            machine.engine.start(workType: calls, intent: "Standup")
            expect(offered.contains(machine.engine.activeWorkType),
                   "a start in a retired category should begin under one still offered, got \(machine.engine.activeWorkType.rawValue)",
                   &problems)
            return problems
        }
    }

    private static func retiredRuleActionRefused() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let context = ActivityRuleChecks.makeConsumer(now: ActivityRuleChecks.t0.addingTimeInterval(60))
            defer { ActivityRuleChecks.clean(context); WorkTypeCatalog.shared.apply(customisations: []) }
            let calls = WorkType(rawValue: "custom.audit-calls")
            let ruleID = UUID()
            WorkTypeCatalog.shared.apply(customisations: [
                WorkTypeDefinition(id: calls.rawValue, name: "Calls", symbolName: "phone.fill", hue: .green)
            ])
            context.persistence.activityRules = [ActivityRule(id: ruleID, name: "Calls", workType: calls,
                                                              bundleIDs: ["com.example.calls"], isEnabled: true,
                                                              startAfter: 60)]
            // Retired after the rule was made, before its action lands.
            WorkTypeCatalog.shared.apply(customisations: [
                WorkTypeDefinition(id: calls.rawValue, name: "Calls", symbolName: "phone.fill",
                                   hue: .green, isRetired: true)
            ])
            let action = ActivityRuleChecks.action(rule: ruleID, name: "Calls", type: calls,
                                                   start: ActivityRuleChecks.t0, end: context.clock.value,
                                                   version: context.persistence.activityRuleVersion, generation: 1)
            expect(context.store.applyAutomaticActivity(action) == nil,
                   "an action for a retired category should be refused", &problems)
            expect(context.engine.state == .idle,
                   "nothing should start for a retired category, got \(context.engine.state)", &problems)
            return problems
        }
    }
}
