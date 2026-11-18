import Foundation

/// The goal list takes over from the category's own goal field: once, without
/// doubling, with edits reaching the one truth, and a category's goal counted
/// as the ring counts it.
enum DailyGoalMigrationChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Category goals move into the goal list once, in order, and never twice",
         migratesOnceWithoutDoubling),
        ("An edit to a category's goal reaches the list and every reader, and removing it removes it",
         editsReachTheOneTruth),
        ("A category goal counts only focus with app use recorded, as the ring does",
         categoryCreditMatchesTheRing),
    ]

    /// A store as it stood before the list: category goals in the definitions,
    /// no list, no flag.
    private static func legacyDefaults(_ name: String, goals: [(WorkType, TimeInterval)]) -> UserDefaults? {
        guard let defaults = MemoryDefaults.suite(named: name) else { return nil }
        let definitions = goals.map { type, seconds in
            WorkTypeDefinition(id: type.rawValue, name: type.displayName, symbolName: type.symbolName,
                               hue: type.hue, dailyGoal: seconds)
        }
        if let data = try? JSONEncoder().encode(definitions) { defaults.set(data, forKey: "fc.workTypes") }
        return defaults
    }

    private static func migratesOnceWithoutDoubling() -> [String] {
        var problems: [String] = []
        let name = "fc-selftest-goal-migrate"
        guard let defaults = legacyDefaults(name, goals: [(.deepWork, 7_200), (.admin, 3_600)]) else {
            return ["could not create isolated defaults"]
        }
        defer {
            MemoryDefaults.remove(named: name)
            WorkTypeCatalog.shared.apply(customisations: [])
        }
        let first = PersistenceStore(defaults: defaults)
        let items = first.dailyGoalItems
        if items.map(\.target) != [.category(WorkType.deepWork.rawValue), .category(WorkType.admin.rawValue)]
            || items.map(\.seconds) != [7_200, 3_600] || items.contains(where: { $0.kind != .target }) {
            problems.append("the goals moved as \(items.map(\.target)) \(items.map(\.seconds))")
        }
        if WorkType.deepWork.dailyGoal != 7_200 { problems.append("the category lost its goal in the move") }
        // A relaunch changes nothing.
        let second = PersistenceStore(defaults: defaults)
        if second.dailyGoalItems != items { problems.append("a relaunch changed the list") }
        // A launch cut short before the flag was set: the retry adds nothing twice.
        defaults.removeObject(forKey: "fc.goalsMigratedVersion")
        let retried = PersistenceStore(defaults: defaults)
        if retried.dailyGoalItems != items { problems.append("a retry doubled or lost goals: \(retried.dailyGoalItems.count)") }
        // A goal that does not fit stays on its category and the flag stays unset.
        let crowded = PersistenceStore(defaults: defaults)
        crowded.dailyGoalItems = (0..<DailyGoalList.maximum).map {
            DailyGoalItem(target: .category("c\($0)"), kind: .target, seconds: 600)
        }
        defaults.removeObject(forKey: "fc.goalsMigratedVersion")
        let blocked = PersistenceStore(defaults: defaults)
        if blocked.goalsMigrated { problems.append("the flag was set with goals left on their categories") }
        // A restore from before the list: the flag and list are absent, the definitions still hold the goals.
        defaults.removeObject(forKey: "fc.goalsMigratedVersion")
        defaults.removeObject(forKey: "fc.dailyGoalItems")
        let restored = PersistenceStore(defaults: defaults)
        if restored.dailyGoalItems.map(\.seconds) != [7_200, 3_600] { problems.append("a restore did not move the goals again") }
        return problems
    }

    private static func editsReachTheOneTruth() -> [String] {
        var problems: [String] = []
        let name = "fc-selftest-goal-edit"
        guard let defaults = legacyDefaults(name, goals: [(.deepWork, 7_200)]) else {
            return ["could not create isolated defaults"]
        }
        defer {
            MemoryDefaults.remove(named: name)
            WorkTypeCatalog.shared.apply(customisations: [])
        }
        let store = PersistenceStore(defaults: defaults)
        if !store.goalsMigrated { problems.append("a store with a category goal never migrated") }
        store.setCategoryGoal(WorkType.deepWork.rawValue, seconds: 3 * 3_600)
        if WorkType.deepWork.dailyGoal != 3 * 3_600 || store.dailyGoalItems.first?.seconds != 3 * 3_600 {
            problems.append("a changed goal did not reach the list and the category")
        }
        store.setCategoryGoal(WorkType.learning.rawValue, seconds: 1_800)
        if store.dailyGoalItems.count != 2 || WorkType.learning.dailyGoal != 1_800 { problems.append("a new category goal was not added") }
        store.setCategoryGoal(WorkType.deepWork.rawValue, seconds: nil)
        if WorkType.deepWork.dailyGoal != nil || store.dailyGoalItems.count != 1 { problems.append("a removed goal stayed") }
        // A paused goal is no goal for the card or the History rates.
        var items = store.dailyGoalItems
        items[0].isPaused = true
        store.dailyGoalItems = items
        if WorkType.learning.dailyGoal != nil { problems.append("a paused goal still counted") }
        return problems
    }

    private static func categoryCreditMatchesTheRing() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let clock = TestClock(SelfTest.anchoredNow())
            let start = clock.value
            let suite = "fc-selftest-goal-credit-\(UUID().uuidString)"
            guard let defaults = MemoryDefaults.suite(named: suite) else { return ["could not create isolated defaults"] }
            defer { MemoryDefaults.remove(named: suite) }
            let persistence = PersistenceStore(defaults: defaults)
            persistence.removeAll()
            let directory = SelfTest.scratchDirectory()
            let engine = SessionEngine(store: persistence,
                                       archive: SessionArchive(directory: directory, now: { clock.value }),
                                       ownBundleID: "com.example.self", schedulesDwell: false, now: { clock.value })
            let usage = AppUsageArchive(directory: directory, now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            let store = SessionStore(engine: engine, schedulesTicker: false, now: { clock.value })
            store.attach(tracker: tracker, usage: usage)
            engine.start(workType: .deepWork, intent: "Two hours, one with an app in use")
            clock.advance(2 * 3_600)
            usage.record(AppUsageSession(bundleID: "com.apple.dt.Xcode", appName: "Xcode",
                                         start: start, end: start.addingTimeInterval(3_600), endReason: .appSwitch))
            let credit = store.storyRailDay(on: clock.value).creditByCategory
            SelfTest.expectClose(credit[WorkType.deepWork.rawValue] ?? 0, 3_600,
                                 "the category counted \(credit) instead of the hour with an app in use", &problems)
            SelfTest.expectClose(store.focusedActiveSeconds(on: clock.value), credit[WorkType.deepWork.rawValue] ?? 0,
                                 "the category's figure and the ring's differ", &problems)
            return problems
        }
    }
}
