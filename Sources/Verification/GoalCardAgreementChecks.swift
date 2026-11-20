import Foundation

/// Today's goal card and the day's record judge an activity limit by one rule;
/// a limit this version cannot use is never judged; and the 1 Hz ticker looks
/// at the goal list once a minute, not every second.
enum GoalCardAgreementChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("An activity limit the day's record would leave unjudged is not shown as kept on Today",
         cardMatchesRecord),
        ("An activity limit on a focused or unknown purpose is never judged as kept",
         unusableLimitNeverJudged),
        ("The ticker records today's goal list once a minute, not on every tick",
         goalListReadOncePerMinute),
    ]

    private static func cardMatchesRecord() -> [String] {
        var problems: [String] = []
        let media = DailyGoalItem(target: .activity("media"), kind: .limit, seconds: 3_600)
        // 10 minutes of music, three hours in a browser with no purpose set.
        let apps: [(bundleID: String, total: TimeInterval)] = [("com.apple.Music", 600), ("com.apple.Safari", 3 * 3_600)]
        let card = DailyGoalList.activityLimitStatus([media], apps: apps, overrides: [:])
        let record = GoalDayResults.close(goals: [media], credit: [:],
                                          appUse: Dictionary(apps.map { ($0.bundleID, $0.total) }, uniquingKeysWith: +),
                                          purposeUse: DailyGoalList.purposeUse(apps: apps, overrides: [:]),
                                          unreadUse: DailyGoalList.unreadUse(apps: apps, overrides: [:]))
        if record?.first?.unjudged != true { problems.append("the record did not leave the day unjudged: \(String(describing: record))") }
        if card.first?.unjudged != true || card.first?.used != 600 {
            problems.append("the card read \(card), not 10 minutes and unjudged")
        }
        // With the browser set to research, the media limit is plainly kept on both.
        let set = ["com.apple.Safari": "research"]
        let kept = DailyGoalList.activityLimitStatus([media], apps: apps, overrides: set)
        if kept.first?.unjudged != false { problems.append("a browser with a purpose set still left the card unjudged") }
        return problems
    }

    private static func unusableLimitNeverJudged() -> [String] {
        var problems: [String] = []
        let coding = DailyGoalItem(target: .activity("coding"), kind: .limit, seconds: 3_600)
        let unknown = DailyGoalItem(target: .activity("gaming"), kind: .limit, seconds: 3_600)
        let results = GoalDayResults.judge([coding, unknown], credit: [:], appUse: ["com.apple.Music": 600],
                                           purposeUse: ["coding": 0, "gaming": 0])
        if !results.isEmpty { problems.append("an unusable activity limit was judged: \(results)") }
        if GoalDayResults.close(goals: [coding, unknown], credit: [:], appUse: ["com.apple.Music": 600]) != nil {
            problems.append("a day with only unusable limits was recorded")
        }
        return problems
    }

    private static func goalListReadOncePerMinute() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            // Five seconds into a minute, so +60, +1 and +60 each land where the check expects.
            let anchor = SelfTest.anchoredNow()
            let clock = TestClock((Calendar.current.dateInterval(of: .minute, for: anchor)?.start ?? anchor).addingTimeInterval(5))
            let suite = "fc-selftest-goal-tick-\(UUID().uuidString)"
            guard let defaults = MemoryDefaults.suite(named: suite) else { return ["could not create isolated defaults"] }
            defer { MemoryDefaults.remove(named: suite) }
            let persistence = PersistenceStore(defaults: defaults)
            let directory = SelfTest.scratchDirectory()
            let engine = SessionEngine(store: persistence,
                                       archive: SessionArchive(directory: directory, now: { clock.value }),
                                       ownBundleID: "com.example.self", schedulesDwell: false, now: { clock.value })
            let store = SessionStore(engine: engine, schedulesTicker: false, now: { clock.value })
            let first = DailyGoalItem(target: .app("com.example.video"), kind: .limit, seconds: 3_600)
            let second = DailyGoalItem(target: .app("com.example.chat"), kind: .limit, seconds: 1_800)
            let key = DailyGoalList.dayKey(clock.value, calendar: Calendar.current)
            persistence.dailyGoalItems = [first]
            clock.advance(60)
            store.updateTimeDrivenFigures()
            if persistence.goalSnapshotsByDay[key] != [first] { problems.append("the minute's first tick did not record the goal list") }
            // Written behind the store's back, so only the ticker can notice it.
            persistence.dailyGoalItems = [first, second]
            clock.advance(1)
            store.updateTimeDrivenFigures()
            if persistence.goalSnapshotsByDay[key] != [first] { problems.append("a second tick in the same minute read the goal list again") }
            clock.advance(60)
            store.updateTimeDrivenFigures()
            if persistence.goalSnapshotsByDay[key] != [first, second] { problems.append("the next minute's tick did not record the new goal list") }
            return problems
        }
    }
}
