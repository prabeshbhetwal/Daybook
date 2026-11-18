import Foundation

/// The list of daily goals and where it is kept: the rules for what a goal
/// may be, a file from a newer version surviving a round trip, the cap, the
/// per-day record, and the backup carrying both.
enum DailyGoalListChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A goal of the wrong kind, a repeat or a nonsense amount is refused, and no more than eight are kept",
         listRules),
        ("The goal list and each day's results are kept, read back as written, and join a backup",
         storageRoundTrip),
        ("A goal this version cannot read is kept as it was, and an unreadable stored list reads as empty",
         unknownAndUnreadable),
    ]

    private static func listRules() -> [String] {
        var problems: [String] = []
        let coding = DailyGoalItem(target: .category("deepWork"), kind: .target, seconds: 3 * 3_600)
        let video = DailyGoalItem(target: .app("com.example.video"), kind: .limit, seconds: 2 * 3_600)
        let wrongApp = DailyGoalItem(target: .app("com.example.video"), kind: .target, seconds: 3_600)
        let wrongCategory = DailyGoalItem(target: .category("deepWork"), kind: .limit, seconds: 3_600)
        let zero = DailyGoalItem(target: .category("admin"), kind: .target, seconds: 0)
        let infinite = DailyGoalItem(target: .category("admin"), kind: .target, seconds: .infinity)
        let repeated = DailyGoalItem(id: coding.id, target: .category("admin"), kind: .target, seconds: 600)
        let kept = DailyGoalList.usable([coding, wrongApp, video, wrongCategory, zero, infinite, repeated])
        if kept != [coding, video] { problems.append("kept \(kept.map(\.target)) instead of the category and the app") }
        let many = (0..<12).map { DailyGoalItem(target: .category("c\($0)"), kind: .target, seconds: 600) }
        if DailyGoalList.usable(many) != Array(many.prefix(DailyGoalList.maximum)) {
            problems.append("a list of 12 was not cut to the first \(DailyGoalList.maximum)")
        }
        var paused = coding
        paused.isPaused = true
        if DailyGoalList.active([paused, video]) != [video] { problems.append("a paused goal was still active") }
        // The cap applies to what may be added, counting goals this version cannot read.
        let fullWithUnknown = many.prefix(7) + [DailyGoalItem(target: .unknown(kind: "x", value: "y"), kind: .target, seconds: 60)]
        if DailyGoalList.canAdd(coding, to: Array(fullWithUnknown)) { problems.append("a ninth goal was allowed past an unreadable one") }
        if !DailyGoalList.canAdd(coding, to: Array(many.prefix(2))) { problems.append("a valid goal was refused with room to spare") }
        if DailyGoalList.canAdd(wrongApp, to: []) { problems.append("a goal of the wrong kind was allowed") }
        // The key is the calendar's day, so it does not move with the time zone the Mac is in.
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        let lateEvening = berlin.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 23, minute: 30)) ?? Date()
        if DailyGoalList.dayKey(lateEvening, calendar: berlin) != "2026-11-18" {
            problems.append("a late evening keyed as \(DailyGoalList.dayKey(lateEvening, calendar: berlin))")
        }
        return problems
    }

    private static func storageRoundTrip() -> [String] {
        var problems: [String] = []
        let name = "fc-selftest-goal-list"
        guard let defaults = MemoryDefaults.suite(named: name) else { return ["could not create isolated defaults"] }
        defer { MemoryDefaults.remove(named: name) }
        let store = PersistenceStore(defaults: defaults)
        let dayGoalBefore = store.dailyGoal
        if !store.dailyGoalItems.isEmpty || !store.goalResultsByDay.isEmpty {
            problems.append("a fresh store already held goals")
        }
        let coding = DailyGoalItem(target: .category("deepWork"), kind: .target, seconds: 3 * 3_600)
        let video = DailyGoalItem(target: .app("com.example.video"), kind: .limit, seconds: 2 * 3_600, isPaused: true)
        store.dailyGoalItems = [coding, video]
        let result = DailyGoalResult(goalID: coding.id, target: coding.target, kind: .target,
                                     amount: 3 * 3_600, counted: 2_700, met: false)
        store.goalResultsByDay = ["2026-11-18": [result]]
        let reread = PersistenceStore(defaults: defaults)
        if reread.dailyGoalItems != [coding, video] { problems.append("the list did not read back as written") }
        if reread.goalResultsByDay["2026-11-18"] != [result] { problems.append("the day's results did not read back") }
        let backed = reread.backupSnapshot.keys
        if !backed.contains("fc.dailyGoalItems") || !backed.contains("fc.goalResultsByDay") {
            problems.append("the goal list or the results were left out of a backup")
        }
        // Nothing migrates here: the category goal field is untouched by storing a list.
        if reread.dailyGoal != dayGoalBefore {
            problems.append("storing goals changed the day goal")
        }
        return problems
    }

    private static func unknownAndUnreadable() -> [String] {
        var problems: [String] = []
        let name = "fc-selftest-goal-unknown"
        guard let defaults = MemoryDefaults.suite(named: name) else { return ["could not create isolated defaults"] }
        defer { MemoryDefaults.remove(named: name) }
        // What a later version might write: an unknown target, an unknown kind, a zero amount,
        // and twelve goals in all. Reading then writing must give every one of them back.
        func goal(_ target: String, _ kind: String, _ seconds: Int) -> String {
            #"{"id":"\#(UUID().uuidString)","target":{"kind":"\#(target)","value":"v"},"kind":"\#(kind)","seconds":\#(seconds),"isPaused":false}"#
        }
        let stored = [goal("place", "target", 1800), goal("category", "habit", 600), goal("app", "limit", 0)]
            + (0..<9).map { goal("category", "target", 600 + $0) }
        defaults.set(Data("[\(stored.joined(separator: ","))]".utf8), forKey: "fc.dailyGoalItems")
        let store = PersistenceStore(defaults: defaults)
        let items = store.dailyGoalItems
        if items.count != 12 { problems.append("read \(items.count) goals of 12 stored") }
        if items.first?.target != .unknown(kind: "place", value: "v") || items[1].kind != .unknown("habit") {
            problems.append("a newer target or kind was not kept: \(items.prefix(2).map(\.kind))")
        }
        if DailyGoalList.usable(items).count != DailyGoalList.maximum { problems.append("use was not capped at eight") }
        store.dailyGoalItems = items
        let again = PersistenceStore(defaults: defaults).dailyGoalItems
        if again != items { problems.append("a read then a write changed the stored goals (\(again.count) of \(items.count))") }
        // An unknown kind inside a day's results leaves the rest of the history readable.
        let result = #"{"goalID":"\#(UUID().uuidString)","target":{"kind":"category","value":"v"},"kind":"habit","amount":60,"counted":0,"met":false}"#
        defaults.set(Data(#"{"2026-11-18":[\#(result)]}"#.utf8), forKey: "fc.goalResultsByDay")
        if PersistenceStore(defaults: defaults).goalResultsByDay["2026-11-18"]?.count != 1 {
            problems.append("a result of a newer kind made the history unreadable")
        }
        defaults.set(Data("not json".utf8), forKey: "fc.dailyGoalItems")
        if !PersistenceStore(defaults: defaults).dailyGoalItems.isEmpty { problems.append("an unreadable list was not read as empty") }
        return problems
    }
}
