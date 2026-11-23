import Foundation

/// Findings from the 1.3.9 release review: activity-goal credit counted by the time it was
/// actually credited and by each stretch's own category, closed days read as recorded, and
/// app-category changes dated so old summaries are rebuilt only for apps changed since.
enum ReleaseReviewChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A paused stretch does not take coding from a session that overlaps it", pausedStretchCoversNothing),
        ("Coding in a focus stretch continued from an Unsorted one still counts", unsortedStretchIsLeftOut),
        ("A closed day's activity goal reads its saved result", closedDayReadsSavedResult),
        ("Saving app categories dates only the apps whose category changed", changesAreDated),
    ]

    private static func at(_ minutes: Double) -> Date { SelfTest.base.addingTimeInterval(minutes * 60) }

    private static func phase(_ from: Double, _ to: Double, coding: Double) -> SessionPhase {
        SessionPhase(start: at(from), end: at(to), activity: coding > 0 ? .purpose(.coding) : .away,
                     counted: coding > 0, credited: coding > 0 ? ["coding": coding * 60] : [:])
    }

    private static func pausedStretchCoversNothing() -> [String] {
        var problems: [String] = []
        // 9:00–10:00, paused from 9:30; then 9:30–10:30 of coding.
        let first = DailyGoalList.focusSlices(credited: ["coding": 1_800], phases: [phase(0, 30, coding: 30), phase(30, 60, coding: 0)],
                                              span: DateInterval(start: at(0), end: at(60)), focus: [DateInterval(start: at(0), end: at(60))])
        let second = DailyGoalList.focusSlices(credited: ["coding": 3_600], phases: [phase(30, 90, coding: 60)],
                                               span: DateInterval(start: at(30), end: at(90)), focus: [DateInterval(start: at(30), end: at(90))])
        let total = DailyGoalList.focusByPurpose(rows: first + second, ring: 10_000)["coding"] ?? 0
        expect(abs(total - 5_400) < 1, "both half hour and hour count, 90 minutes, got \(total / 60)", &problems)
        return problems
    }

    private static func unsortedStretchIsLeftOut() -> [String] {
        var problems: [String] = []
        // One row: an Unsorted stretch 0–30, continued into a focus stretch 30–90; coding throughout.
        let slices = DailyGoalList.focusSlices(credited: ["coding": 5_400], phases: [phase(0, 90, coding: 90)],
                                               span: DateInterval(start: at(0), end: at(90)),
                                               focus: [DateInterval(start: at(30), end: at(90))])
        let total = DailyGoalList.focusByPurpose(rows: slices, ring: 10_000)["coding"] ?? 0
        expect(abs(total - 3_600) < 1, "the focus stretch's hour counts, got \(total / 60) minutes", &problems)
        return problems
    }

    private static func closedDayReadsSavedResult() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let calendar = Calendar.current
            let clock = TestClock(SelfTest.anchoredNow())
            let suite = "fc-selftest-release-review-\(UUID().uuidString)"
            guard let defaults = MemoryDefaults.suite(named: suite) else { return ["could not create isolated defaults"] }
            defer { MemoryDefaults.remove(named: suite) }
            let persistence = PersistenceStore(defaults: defaults)
            persistence.removeAll()
            let engine = SessionEngine(store: persistence,
                                       archive: SessionArchive(directory: SelfTest.scratchDirectory(), now: { clock.value }),
                                       ownBundleID: "com.example.self", schedulesDwell: false, now: { clock.value })
            let store = SessionStore(engine: engine, schedulesTicker: false, now: { clock.value })
            let goal = DailyGoalItem(target: .activity("coding"), kind: .target, seconds: 3_600)
            persistence.dailyGoalItems = [goal]
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: clock.value) else { return ["no yesterday"] }
            persistence.goalResultsByDay[DailyGoalList.dayKey(yesterday, calendar: calendar)] = [
                DailyGoalResult(goalID: goal.id, target: goal.target, kind: goal.kind, amount: 3_600, counted: 4_000, met: true)
            ]
            let row = store.activityTargets(on: yesterday).first
            expect(row?.achieved == 4_000 && row?.goal == 3_600,
                   "yesterday reads its saved 4000s of 3600s, got \(String(describing: row))", &problems)
            return problems
        }
    }

    private static func changesAreDated() -> [String] {
        var problems: [String] = []
        let suite = "fc-selftest-release-review-dates-\(UUID().uuidString)"
        guard let defaults = MemoryDefaults.suite(named: suite) else { return ["could not create isolated defaults"] }
        defer { MemoryDefaults.remove(named: suite) }
        let persistence = PersistenceStore(defaults: defaults)
        persistence.savePurposeOverrides(["com.apple.dt.xcode": "design"], at: at(0))
        persistence.savePurposeOverrides(["com.apple.dt.xcode": "design", "com.apple.terminal": "design"], at: at(60))
        let changes = persistence.purposeOverrideChanges
        expect(changes["com.apple.dt.xcode"] == at(0).timeIntervalSinceReferenceDate,
               "Xcode keeps the time it changed, got \(String(describing: changes["com.apple.dt.xcode"]))", &problems)
        expect(changes["com.apple.terminal"] == at(60).timeIntervalSinceReferenceDate,
               "Terminal is dated when it changed, got \(String(describing: changes["com.apple.terminal"]))", &problems)
        return problems
    }
}
