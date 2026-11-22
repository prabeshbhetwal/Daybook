import Foundation

/// An activity goal counts that activity in any focus session, whatever the
/// session is filed under: coding inside Deep work fills a Coding activity goal
/// while a Coding category goal stays empty, and the row never reads more than
/// the day's focus.
enum ActivityGoalTargetChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("An activity goal is judged against the day's focus in that activity, in any session",
         activityTargetJudged),
        ("An activity goal's count is the sum of the day's sessions, never above the day's focus",
         focusByPurposeCapped),
        ("Only coding, writing and AI, and design can be an activity goal",
         onlyFocusedPurposesAreTargets),
        ("Coding inside a Deep work session fills a Coding activity goal, not a Coding category goal",
         codingInsideDeepWorkCounts),
        ("A session still running past midnight splits its coding between the two days, never above each day's focus",
         codingAcrossMidnight),
    ]

    private static func codingAcrossMidnight() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let calendar = Calendar.current
            let midnight = calendar.startOfDay(for: SelfTest.anchoredNow())
            let start = midnight.addingTimeInterval(-3_600)
            let clock = TestClock(start)
            let suite = "fc-selftest-activity-goal-midnight-\(UUID().uuidString)"
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
            persistence.dailyGoalItems = [DailyGoalItem(target: .activity("coding"), kind: .target, seconds: 600)]

            // Deep work from 23:00 in Xcode throughout, still running at 00:30.
            engine.start(workType: .deepWork, intent: "Late night")
            usage.record(AppUsageSession(bundleID: "com.apple.dt.Xcode", appName: "Xcode", start: start,
                                         end: midnight.addingTimeInterval(30 * 60), endReason: .appSwitch))
            clock.advance(90 * 60)
            guard engine.state != .idle, !calendar.isDate(start, inSameDayAs: clock.value) else {
                return ["the fixture did not leave a session running into the next day"]
            }
            for day in [start, clock.value] {
                let ring = store.focusedActiveSeconds(on: day)
                let coding = store.focusByPurpose(on: day)["coding"] ?? 0
                if coding > ring + 0.01 { problems.append("coding \(coding)s above the day's focus \(ring)s") }
            }
            if abs((store.focusByPurpose(on: start)["coding"] ?? 0) - 3_600) > 60 {
                problems.append("the day it began did not count its hour of coding")
            }
            if abs((store.focusByPurpose(on: clock.value)["coding"] ?? 0) - 1_800) > 60 {
                problems.append("the next day did not count its half hour of coding")
            }
            return problems
        }
    }

    private static func activityTargetJudged() -> [String] {
        var problems: [String] = []
        let coding = DailyGoalItem(target: .activity("coding"), kind: .target, seconds: 30 * 60)
        let category = DailyGoalItem(target: .category("coding"), kind: .target, seconds: 30 * 60)
        let results = GoalDayResults.judge([coding, category], credit: ["deepWork": 3_600], appUse: [:],
                                           focusByPurpose: ["coding": 40 * 60])
        let activity = results.first { $0.goalID == coding.id }
        if activity?.met != true || activity?.counted != 40 * 60 {
            problems.append("the activity goal read \(String(describing: activity)), not 40 minutes and met")
        }
        if results.first(where: { $0.goalID == category.id })?.met != false {
            problems.append("the category goal was met with nothing filed under it")
        }
        let short = GoalDayResults.judge([coding], credit: [:], appUse: [:], focusByPurpose: ["coding": 29 * 60])
        if short.first?.met != false { problems.append("29 minutes met a 30-minute activity goal") }
        return problems
    }

    private static func focusByPurposeCapped() -> [String] {
        var problems: [String] = []
        let summed = DailyGoalList.focusByPurpose(rows: [["coding": 600, "design": 60], ["coding": 900]], ring: 3_600)
        if summed != ["coding": 1_500, "design": 60] { problems.append("two rows summed to \(summed)") }
        let capped = DailyGoalList.focusByPurpose(rows: [["coding": 4_000]], ring: 3_600)
        if capped["coding"] != 3_600 { problems.append("a count above the ring was not capped: \(capped)") }
        return problems
    }

    private static func onlyFocusedPurposesAreTargets() -> [String] {
        var problems: [String] = []
        if DailyGoalList.targetablePurposes != [.coding, .writingAI, .design] {
            problems.append("targetable purposes were \(DailyGoalList.targetablePurposes)")
        }
        let items = [DailyGoalItem(target: .activity("coding"), kind: .target, seconds: 3_600),
                     DailyGoalItem(target: .activity("design"), kind: .target, seconds: 3_600, isPaused: true),
                     DailyGoalItem(target: .activity("media"), kind: .limit, seconds: 3_600)]
        let targets = DailyGoalList.activityTargets(items).map(\.purpose)
        if targets != [.coding] { problems.append("activity targets in use were \(targets), not coding alone") }
        return problems
    }

    private static func codingInsideDeepWorkCounts() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let start = SelfTest.anchoredNow()
            let clock = TestClock(start)
            let suite = "fc-selftest-activity-goal-\(UUID().uuidString)"
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
            let goal = DailyGoalItem(target: .activity("coding"), kind: .target, seconds: 30 * 60)
            persistence.dailyGoalItems = [goal]

            // Deep work for an hour: 40 minutes in Xcode, then 20 in Notes.
            engine.start(workType: .deepWork, intent: "Refactor")
            usage.record(AppUsageSession(bundleID: "com.apple.dt.Xcode", appName: "Xcode",
                                         start: start, end: start.addingTimeInterval(40 * 60), endReason: .appSwitch))
            usage.record(AppUsageSession(bundleID: "com.apple.Notes", appName: "Notes",
                                         start: start.addingTimeInterval(40 * 60), end: start.addingTimeInterval(60 * 60),
                                         endReason: .appSwitch))
            clock.advance(60 * 60)
            _ = engine.stop()
            clock.advance(60)

            let ring = store.focusedActiveSeconds(on: start)
            let coding = store.focusByPurpose(on: start)["coding"] ?? 0
            if abs(coding - 40 * 60) > 60 {
                let rows = store.storyDayProjection(on: start).sessions.compactMap { entry -> String? in
                    guard case .session(let session) = entry else { return nil }
                    return "\(session.workType.rawValue) \(session.start)-\(session.end) "
                        + "\(String(describing: store.sessionActivity(for: session)?.credited))"
                }
                problems.append("coding inside Deep work counted \(coding)s, not 40 minutes (ring \(ring)s, rows \(rows))")
            }
            if coding > ring { problems.append("the activity count \(coding)s exceeded the ring's \(ring)s") }
            if store.storyRailDay(on: start).creditByCategory["coding"] != nil {
                problems.append("Deep work time was credited to a Coding category")
            }
            let row = store.activityTargets(on: start)
            if row.map(\.id) != [goal.id] || abs((row.first?.achieved ?? 0) - coding) > 0.01 {
                problems.append("the rail's activity rows were \(row)")
            }
            return problems
        }
    }
}
