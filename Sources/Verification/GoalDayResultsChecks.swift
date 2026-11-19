import Foundation

/// How a day's goals are judged, when a day is perfect, and the awards that
/// follow from a run of such days.
enum GoalDayResultsChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A target is met at its printed minutes, a limit is kept at or under them, and a day with no goals is not perfect",
         judging),
        ("Runs need consecutive days, and the perfect week and each goal's run award follow from the recorded days",
         runsAndAwards),
        ("A closed day is judged once by the goals that stood on it, not by goals added after, across midnight",
         recorderAcrossMidnight),
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
        if rest.filter({ $0.paused != true }).count != 1 || rest.filter({ $0.paused == true }).count != 1
            || !GoalDayResults.isPerfect(rest) { problems.append("a paused limit still counted, or was not recorded as paused") }
        if GoalDayResults.isPerfect(GoalDayResults.judge([paused], credit: [:], appUse: [:])) {
            problems.append("a day with every goal paused was perfect")
        }
        // A closed day with nothing recorded is not judged, and one with evidence is.
        if GoalDayResults.close(goals: items, credit: [:], appUse: [:]) != nil {
            problems.append("a day with no recording was judged")
        }
        if GoalDayResults.close(goals: items, credit: [:], appUse: ["com.example.other": 600])?.count != 2 {
            problems.append("a day with evidence was not judged")
        }
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
                                           name: { target in if case .app = target { return "Video" } else { return "Coding" } }, calendar: calendar)
        let week = awards.first { $0.id == "perfect-week" }
        if week?.isEarned != true || week?.detail != "7 perfect days in a row" { problems.append("a perfect week read \(week?.detail ?? "missing")") }
        let run = awards.first { $0.id == "goal-\(coding.id.uuidString)" }
        if run?.isEarned != true || run?.title != "Coding goal, 5 days" { problems.append("the coding run read \(run?.title ?? "missing")") }
        let kept = awards.first { $0.id == "goal-\(video.id.uuidString)" }
        if kept?.title != "Kept to Video limit, 5 days" { problems.append("the limit award read \(kept?.title ?? "missing")") }
        // An earned award outlives the goal: removed from use, the run award is still there; a
        // goal never earned and no longer in use shows nothing.
        let afterRemoval = GoalDayResults.awards(results: results, items: [], name: { _ in "x" }, calendar: calendar)
        if afterRemoval.first(where: { $0.id == "goal-\(coding.id.uuidString)" })?.isEarned != true {
            problems.append("deleting a goal removed the award it had earned")
        }
        var partial = results
        for offset in 1...7 where offset != 4 && offset != 2 { _ = partial[key(offset)] }
        partial = [key(1): results[key(1)] ?? []]
        if GoalDayResults.awards(results: partial, items: [], name: { _ in "x" }, calendar: calendar)
            .contains(where: { $0.id.hasPrefix("goal-") }) {
            problems.append("an unearned goal no longer in use was listed")
        }
        // A paused day neither breaks a run nor adds to it: three met, one paused, two met is five.
        var bridged: [String: [DailyGoalResult]] = [:]
        for (offset, state) in [(7, "met"), (6, "met"), (5, "met"), (4, "paused"), (3, "met"), (2, "met")] {
            bridged[key(offset)] = [DailyGoalResult(goalID: coding.id, target: coding.target, kind: coding.kind,
                                                    amount: coding.seconds, counted: 0, met: state == "met",
                                                    paused: state == "paused" ? true : nil)]
        }
        if GoalDayResults.goalRun(coding.id, in: bridged, calendar: calendar) != 5 {
            problems.append("a paused day changed the run to \(GoalDayResults.goalRun(coding.id, in: bridged, calendar: calendar))")
        }
        // A day with no record between two met days breaks it.
        bridged[key(4)] = nil
        if GoalDayResults.goalRun(coding.id, in: bridged, calendar: calendar) != 3 { problems.append("a gap did not break the run") }
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
            if !store.wasPerfectDay(place) || !store.wasPerfectDay(on: yesterday) {
                problems.append("a day with every goal met was not perfect")
            }
            if !store.yesterdayWasPerfect { problems.append("the card did not know yesterday was perfect") }
            // The offers are rebuilt when yesterday's results land, not only on a session change.
            let before = TodayNoteOffers.cause(store: store, usable: true)
            persistence.goalResultsByDay = [:]
            store.yesterdayPerfectCache = nil
            if TodayNoteOffers.cause(store: store, usable: true) == before {
                problems.append("recording yesterday's results did not change the note offers' cause")
            }
            persistence.goalResultsByDay = [DailyGoalList.dayKey(yesterday, calendar: calendar):
                                                [result(coding, met: true), result(video, met: false)]]
            if store.wasPerfectDay(place) { problems.append("a broken limit left the day perfect") }
            return problems
        }
    }

    private static func recorderAcrossMidnight() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let calendar = Calendar.current
            let clock = TestClock(SelfTest.anchoredNow())
            let suite = "fc-selftest-recorder-\(UUID().uuidString)"
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
            let first = DailyGoalItem(target: .app("com.example.video"), kind: .limit, seconds: 3_600)
            persistence.dailyGoalItems = [first]
            let day = calendar.startOfDay(for: clock.value)
            usage.record(AppUsageSession(bundleID: "com.example.video", appName: "Video",
                                         start: day.addingTimeInterval(8 * 3_600 + 30 * 60),
                                         end: day.addingTimeInterval(9 * 3_600), endReason: .appSwitch))
            store.recordGoalResultsIfNewDay()
            let dayKey = DailyGoalList.dayKey(day, calendar: calendar)
            if persistence.goalSnapshotsByDay[dayKey]?.map(\.id) != [first.id] { problems.append("today's goals were not kept in its snapshot") }
            if persistence.goalResultsByDay[dayKey] != nil { problems.append("today was judged before it closed") }
            // A second goal is added late in the day; then midnight passes.
            let second = DailyGoalItem(target: .app("com.example.other"), kind: .limit, seconds: 600)
            persistence.dailyGoalItems = [first, second]
            store.recordGoalResultsIfNewDay()
            // Just after midnight the day is not judged: quiet time before it may still roll back.
            let sinceDayStart = clock.value.timeIntervalSince(day)
            clock.advance(24 * 3_600 - sinceDayStart + 2 * 60)
            store.updateTimeDrivenFigures()
            if persistence.goalResultsByDay[dayKey] != nil { problems.append("a day was judged two minutes after midnight") }
            clock.advance(4 * 60)
            store.updateTimeDrivenFigures()
            let written = persistence.goalResultsByDay[dayKey]
            if written?.map(\.goalID) != [first.id, second.id] {
                problems.append("the closed day held \(written?.count ?? 0) results, not the two goals standing at its last edit")
            }
            // A goal added after the day closed never reaches back, and nothing is written twice.
            let third = DailyGoalItem(target: .app("com.example.third"), kind: .limit, seconds: 600)
            persistence.dailyGoalItems = [first, second, third]
            store.updateTimeDrivenFigures()
            store.recordGoalResultsIfNewDay()
            if persistence.goalResultsByDay[dayKey] != written { problems.append("a closed day was rewritten or reached back") }
            if persistence.goalResultsByDay.count != 1 { problems.append("a day without goals or evidence was judged") }
            return problems
        }
    }
}
