import Foundation

/// A day on which every goal was paused is still closed, with paused results,
/// so a run across it is kept rather than broken by a missing day.
enum PausedGoalDayChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A day with every goal paused is recorded as paused, so a run across it is kept",
         allPausedDayRecorded),
    ]

    private static func allPausedDayRecorded() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let calendar = Calendar.current
            let clock = TestClock(SelfTest.anchoredNow())
            let suite = "fc-selftest-paused-day-\(UUID().uuidString)"
            guard let defaults = MemoryDefaults.suite(named: suite) else { return ["could not create isolated defaults"] }
            defer { MemoryDefaults.remove(named: suite); WorkTypeCatalog.shared.apply(customisations: []) }
            let persistence = PersistenceStore(defaults: defaults)
            let directory = SelfTest.scratchDirectory()
            let engine = SessionEngine(store: persistence,
                                       archive: SessionArchive(directory: directory, now: { clock.value }),
                                       ownBundleID: "com.example.self", schedulesDwell: false, now: { clock.value })
            let usage = AppUsageArchive(directory: directory, now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            let store = SessionStore(engine: engine, schedulesTicker: false, now: { clock.value })
            store.attach(tracker: tracker, usage: usage)
            let goal = DailyGoalItem(target: .app("com.example.video"), kind: .limit, seconds: 3_600, isPaused: true)
            persistence.dailyGoalItems = [goal]
            let day = calendar.startOfDay(for: clock.value)
            usage.record(AppUsageSession(bundleID: "com.example.video", appName: "Video",
                                         start: day.addingTimeInterval(8 * 3_600 + 30 * 60),
                                         end: day.addingTimeInterval(9 * 3_600), endReason: .appSwitch))
            store.recordGoalResultsIfNewDay()
            clock.advance(24 * 3_600 - clock.value.timeIntervalSince(day) + 6 * 60)
            store.updateTimeDrivenFigures()
            let dayKey = DailyGoalList.dayKey(day, calendar: calendar)
            let written = persistence.goalResultsByDay[dayKey] ?? []
            if written.map(\.goalID) != [goal.id] || written.first?.paused != true {
                problems.append("the all-paused day held \(written), not one paused result")
            }
            if store.wasPerfectDay(on: day) { problems.append("a day with every goal paused was called perfect") }
            // Met, paused, met reads as a run of two, as the paused day is neutral.
            let met = DailyGoalResult(goalID: goal.id, target: goal.target, kind: .limit,
                                      amount: 3_600, counted: 600, met: true)
            guard let before = calendar.date(byAdding: .day, value: -1, to: day),
                  let after = calendar.date(byAdding: .day, value: 1, to: day) else { return ["no neighbouring days"] }
            var runs = persistence.goalResultsByDay
            runs[DailyGoalList.dayKey(before, calendar: calendar)] = [met]
            runs[DailyGoalList.dayKey(after, calendar: calendar)] = [met]
            let run = GoalDayResults.goalRun(goal.id, in: runs, calendar: calendar)
            if run != 2 { problems.append("met, all paused, met read as a run of \(run), expected 2") }
            return problems
        }
    }
}
