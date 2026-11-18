import Foundation

/// How a day's goals are judged, when a day is perfect, and the awards that
/// follow from a run of such days.
enum GoalDayResultsChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A target is met at its printed minutes, a limit is kept at or under them, and a day with no goals is not perfect",
         judging),
        ("Runs need consecutive days, and the perfect week and each goal's run award follow from the recorded days",
         runsAndAwards),
        ("The Yesterday card knows a perfect day from the recorded results, and a day with none is not one",
         yesterdayKnowsPerfect),
    ]

    private static let coding = DailyGoalItem(target: .category("deepWork"), kind: .target, seconds: 2 * 3_600)
    private static let video = DailyGoalItem(target: .app("com.example.video"), kind: .limit, seconds: 3_600)

    private static func judging() -> [String] {
        var problems: [String] = []
        let items = [coding, video]
        let good = GoalDayResults.judge(items, credit: ["deepWork": 2 * 3_600 + 5],
                                        appUse: ["com.example.video": 3_600 + 20])
        // 20 seconds past the limit prints as the same hour: kept.
        if !GoalDayResults.isPerfect(good) || good.count != 2 { problems.append("a day on target and within the limit was not perfect") }
        let short = GoalDayResults.judge(items, credit: ["deepWork": 119 * 60 + 59], appUse: [:])
        if short.first?.met != false || GoalDayResults.isPerfect(short) { problems.append("one second under 2h counted as met") }
        let over = GoalDayResults.judge(items, credit: ["deepWork": 2 * 3_600], appUse: ["com.example.video": 61 * 60])
        if over.last?.met != false || GoalDayResults.isPerfect(over) { problems.append("a limit past its minutes was kept") }
        var paused = video
        paused.isPaused = true
        let rest = GoalDayResults.judge([coding, paused], credit: ["deepWork": 2 * 3_600], appUse: ["com.example.video": 9_999])
        if rest.count != 1 || !GoalDayResults.isPerfect(rest) { problems.append("a paused limit still counted") }
        if GoalDayResults.isPerfect(GoalDayResults.judge([], credit: [:], appUse: [:])) { problems.append("no goals made a perfect day") }
        return problems
    }

    private static func result(_ item: DailyGoalItem, met: Bool) -> DailyGoalResult {
        DailyGoalResult(goalID: item.id, target: item.target, kind: item.kind, amount: item.seconds,
                        counted: 0, met: met)
    }

    private static func runsAndAwards() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: SelfTest.anchoredNow())
        func key(_ offset: Int) -> String {
            DailyGoalList.dayKey(calendar.date(byAdding: .day, value: -offset, to: start) ?? start, calendar: calendar)
        }
        if GoalDayResults.longestRun([start, calendar.date(byAdding: .day, value: -2, to: start) ?? start], calendar: calendar) != 1 {
            problems.append("a missing day did not break a run")
        }
        // Seven perfect days, then the coding goal met on five of them and a limit broken on one.
        var results: [String: [DailyGoalResult]] = [:]
        for offset in 1...7 { results[key(offset)] = [result(coding, met: true), result(video, met: true)] }
        let awards = GoalDayResults.awards(results: results, items: [coding, video],
                                           name: { $0.kind == .limit ? "Video" : "Coding" }, calendar: calendar)
        let week = awards.first { $0.id == "perfect-week" }
        if week?.isEarned != true || week?.detail != "7 perfect days in a row" { problems.append("a perfect week read \(week?.detail ?? "missing")") }
        let run = awards.first { $0.id == "goal-\(coding.id.uuidString)" }
        if run?.isEarned != true || run?.title != "Coding goal, 5 days" { problems.append("the coding run read \(run?.title ?? "missing")") }
        let kept = awards.first { $0.id == "goal-\(video.id.uuidString)" }
        if kept?.title != "Kept to Video limit, 5 days" { problems.append("the limit award read \(kept?.title ?? "missing")") }
        // A break on day four stops the perfect week and shortens the coding run's partner.
        results[key(4)] = [result(coding, met: true), result(video, met: false)]
        let broken = GoalDayResults.awards(results: results, items: [coding, video],
                                           name: { _ in "x" }, calendar: calendar)
        if broken.first(where: { $0.id == "perfect-week" })?.isEarned != false { problems.append("a broken day still gave a perfect week") }
        if broken.first(where: { $0.id == "goal-\(video.id.uuidString)" })?.isEarned != false { problems.append("a broken limit still gave a run") }
        if broken.first(where: { $0.id == "goal-\(coding.id.uuidString)" })?.isEarned != true { problems.append("the coding run was lost to a limit") }
        return problems
    }

    private static func yesterdayKnowsPerfect() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let calendar = Calendar.current
            let clock = TestClock(SelfTest.anchoredNow())
            let suite = "fc-selftest-perfect-\(UUID().uuidString)"
            guard let defaults = MemoryDefaults.suite(named: suite) else { return ["could not create isolated defaults"] }
            defer { MemoryDefaults.remove(named: suite); WorkTypeCatalog.shared.apply(customisations: []) }
            let persistence = PersistenceStore(defaults: defaults)
            let directory = SelfTest.scratchDirectory()
            let engine = SessionEngine(store: persistence,
                                       archive: SessionArchive(directory: directory, now: { clock.value }),
                                       ownBundleID: "com.example.self", schedulesDwell: false, now: { clock.value })
            let store = SessionStore(engine: engine, schedulesTicker: false, now: { clock.value })
            let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: clock.value)) ?? clock.value
            let place = HistoryPlace(level: .day, span: DateInterval(start: yesterday, duration: 86_400))
            if store.wasPerfectDay(place) { problems.append("a day with no record was perfect") }
            persistence.goalResultsByDay = [DailyGoalList.dayKey(yesterday, calendar: calendar):
                                                [result(coding, met: true), result(video, met: true)]]
            if !store.wasPerfectDay(place) { problems.append("a day with every goal met was not perfect") }
            persistence.goalResultsByDay = [DailyGoalList.dayKey(yesterday, calendar: calendar):
                                                [result(coding, met: true), result(video, met: false)]]
            if store.wasPerfectDay(place) { problems.append("a broken limit left the day perfect") }
            return problems
        }
    }
}
