import Foundation

/// The menu-bar panel's goals card reads `SessionStore.categoryGoals(on:)`:
/// nothing when no goal is set, and each goal judged met from the same
/// category credit the Story rail shows.
enum PopoverGoalsChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The panel's goals card has no rows without goals, and marks a goal met once its credit reaches it",
         goalsCardReadModel),
    ]

    private static func goalsCardReadModel() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let clock = TestClock(SelfTest.anchoredNow())
            let start = clock.value
            let suite = "fc-selftest-popover-goals-\(UUID().uuidString)"
            guard let defaults = MemoryDefaults.suite(named: suite) else { return ["could not create isolated defaults"] }
            defer { MemoryDefaults.remove(named: suite) }
            let persistence = PersistenceStore(defaults: defaults)
            persistence.removeAll()
            defer { WorkTypeCatalog.shared.apply(customisations: []) }
            let directory = SelfTest.scratchDirectory()
            let engine = SessionEngine(store: persistence,
                                       archive: SessionArchive(directory: directory, now: { clock.value }),
                                       ownBundleID: "com.example.self", schedulesDwell: false, now: { clock.value })
            let usage = AppUsageArchive(directory: directory, now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            let store = SessionStore(engine: engine, schedulesTicker: false, now: { clock.value })
            store.attach(tracker: tracker, usage: usage)
            engine.start(workType: .deepWork, intent: "An hour with an app in use")
            clock.advance(3_600)
            usage.record(AppUsageSession(bundleID: "com.apple.dt.Xcode", appName: "Xcode",
                                         start: start, end: start.addingTimeInterval(3_600), endReason: .appSwitch))

            WorkTypeCatalog.shared.apply(customisations: [], goals: [:])
            let none = store.categoryGoals(on: clock.value)
            expect(none.isEmpty, "no goal set should give no rows, got \(none.map(\.type.rawValue))", &problems)

            WorkTypeCatalog.shared.apply(customisations: [], goals: [WorkType.deepWork.rawValue: 2 * 3_600])
            let half = store.categoryGoals(on: clock.value)
            expect(half.count == 1 && half.first?.type == .deepWork,
                   "one Deep work row expected, got \(half.map(\.type.rawValue))", &problems)
            if let row = half.first {
                SelfTest.expectClose(row.achieved, 3_600, "the row should show the hour credited", &problems)
                expect(!row.isMet && abs(row.share - 0.5) < 0.01,
                       "an hour of two should be half and unmet, got share \(row.share) met \(row.isMet)", &problems)
            }

            WorkTypeCatalog.shared.apply(customisations: [], goals: [WorkType.deepWork.rawValue: 3_600])
            let met = store.categoryGoals(on: clock.value).first
            expect(met?.isMet == true && met?.share == 1,
                   "an hour against an hour should be met and full, got \(String(describing: met))", &problems)
            return problems
        }
    }
}
