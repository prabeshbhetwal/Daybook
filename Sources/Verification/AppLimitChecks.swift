import Foundation

/// An app limit: what it prints, how it is added, paused and removed, and that
/// it counts the app's whole day, in a session or out of one.
enum AppLimitChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A limit prints minutes that add up, says over only past the limit, and is never met",
         limitFigures),
        ("An app limit is added once, changed, paused out of use and removed from the settings",
         settingsActions),
        ("An app limit counts all of the app's recorded day, in a session or not",
         limitCountsTheWholeDay),
    ]

    private static func limitFigures() -> [String] {
        var problems: [String] = []
        let under = DailyGoalList.limitStatus(used: 45 * 60 + 40, limit: 2 * 3_600)
        if under.figure != "45m of 2h limit" || under.detail != "1h 15m left" || under.isOver {
            problems.append("under read \(under.figure) / \(under.detail)")
        }
        if under.used + under.remaining != under.limit { problems.append("the printed minutes did not add up") }
        let over = DailyGoalList.limitStatus(used: 2 * 3_600 + 15 * 60 + 30, limit: 2 * 3_600)
        if !over.isOver || over.detail != "15m over" { problems.append("over read \(over.detail)") }
        // Seconds past the limit that print as the same minute are not "over".
        let edge = DailyGoalList.limitStatus(used: 2 * 3_600 + 30, limit: 2 * 3_600)
        if edge.isOver { problems.append("30 seconds past the limit read as over") }
        return problems
    }

    private static func settingsActions() -> [String] {
        var problems: [String] = []
        let name = "fc-selftest-app-limit"
        guard let defaults = MemoryDefaults.suite(named: name) else { return ["could not create isolated defaults"] }
        defer {
            MemoryDefaults.remove(named: name)
            WorkTypeCatalog.shared.apply(customisations: [])
        }
        let settings = SettingsModel(store: PersistenceStore(defaults: defaults), isTrackingEnabled: true,
                                     onChange: {}, onTrackingChanged: { _ in })
        let video = DailyGoalItem(target: .app("com.example.video"), kind: .limit, seconds: 7_200)
        if !settings.addGoal(video) { problems.append("a valid app limit was refused") }
        if settings.addGoal(video) { problems.append("the same goal was added twice") }
        if settings.addGoal(DailyGoalItem(target: .app("com.example.other"), kind: .target, seconds: 600)) {
            problems.append("an app goal of the wrong kind was added")
        }
        settings.setGoalSeconds(video.id, 3_600)
        if settings.dailyGoalItems.first?.seconds != 3_600 { problems.append("a changed amount was not kept") }
        settings.setGoalPaused(video.id, true)
        if !DailyGoalList.active(settings.dailyGoalItems).isEmpty { problems.append("a paused limit still counted") }
        settings.removeGoal(video.id)
        if !settings.dailyGoalItems.isEmpty { problems.append("a removed limit stayed") }
        return problems
    }

    private static func limitCountsTheWholeDay() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let clock = TestClock(SelfTest.anchoredNow())
            let suite = "fc-selftest-limit-day-\(UUID().uuidString)"
            guard let defaults = MemoryDefaults.suite(named: suite) else { return ["could not create isolated defaults"] }
            defer { MemoryDefaults.remove(named: suite); WorkTypeCatalog.shared.apply(customisations: []) }
            let persistence = PersistenceStore(defaults: defaults)
            persistence.dailyGoalItems = [DailyGoalItem(target: .app("com.example.video"), kind: .limit, seconds: 7_200),
                                          DailyGoalItem(target: .app("com.example.paused"), kind: .limit, seconds: 600,
                                                        isPaused: true)]
            let directory = SelfTest.scratchDirectory()
            let engine = SessionEngine(store: persistence,
                                       archive: SessionArchive(directory: directory, now: { clock.value }),
                                       ownBundleID: "com.example.self", schedulesDwell: false, now: { clock.value })
            let store = SessionStore(engine: engine, schedulesTicker: false, now: { clock.value })
            // No session is running: the app's time is outside any session and still counts.
            let ranked = [AppRank(bundleID: "com.example.video", appName: "Video", total: 45 * 60, share: 0.5, longest: 45 * 60),
                          AppRank(bundleID: "com.example.paused", appName: "Paused", total: 60, share: 0.1, longest: 60)]
            let limits = store.appLimits(on: clock.value, ranked: ranked)
            if limits.count != 1 || limits[0].bundleID != "com.example.video" || limits[0].used != 45 * 60
                || limits[0].limit != 7_200 {
                problems.append("limits read \(limits.map { ($0.bundleID, $0.used) })")
            }
            if !store.appLimits(on: clock.value, ranked: []).allSatisfy({ $0.used == 0 }) {
                problems.append("an app with no recorded use was not at zero")
            }
            return problems
        }
    }
}
