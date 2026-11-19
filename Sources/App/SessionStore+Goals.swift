import Foundation

extension SessionStore {
    /// The goal list as stored, for the card and the settings. Eight at most,
    /// so reading it each redraw is a few microseconds.
    var goalItems: [DailyGoalItem] { engine.store.dailyGoalItems }

    /// The app limits that count today, with the day's recorded use of each,
    /// in the person's order. Use is all foreground time on the day, in a
    /// session or out of one: leisure is never focus.
    func appLimits(ranked apps: [AppRank]) -> [(bundleID: String, name: String,
                                                           limit: TimeInterval, used: TimeInterval)] {
        let totals = Dictionary(apps.map { ($0.bundleID, $0.total) }, uniquingKeysWith: +)
        let names = Dictionary(apps.map { ($0.bundleID, $0.appName) }, uniquingKeysWith: { first, _ in first })
        return DailyGoalList.active(goalItems).compactMap { item in
            guard case .app(let bundleID) = item.target, item.kind == .limit else { return nil }
            let known = names[bundleID] ?? historyAppName(for: bundleID)
            let name = known == bundleID ? DailyGoalList.fallbackAppName(bundleID) : known
            return (bundleID, name, item.seconds, totals[bundleID] ?? 0)
        }
    }

    /// Keeps today's goals in the day's snapshot (as they stood at the day's last
    /// edit), and once a day writes the results of the closed days of the last
    /// fortnight that have none, so a Mac off for a long weekend loses none. Today is not judged:
    /// the card shows it live. A day is judged by the goals that stood on it, so
    /// goals added later never reach back, and is never recomputed afterwards. A
    /// day with no snapshot, or with nothing recorded on it, is left out rather
    /// than judged on no evidence. Called on every refresh and on the day's
    /// rollover, since an app left running across midnight refreshes neither way alone.
    func recordGoalResultsIfNewDay() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now())
        let key = DailyGoalList.dayKey(today, calendar: calendar)
        let items = goalItems
        if goalSnapshotToday?.key != key || goalSnapshotToday?.items != items {
            var snapshots = engine.store.goalSnapshotsByDay
            snapshots[key] = items
            // A fortnight is more than any closing pass reaches back.
            let keep = Set((0..<14).compactMap { offset in
                calendar.date(byAdding: .day, value: -offset, to: today)
                    .map { DailyGoalList.dayKey($0, calendar: calendar) }
            })
            engine.store.goalSnapshotsByDay = snapshots.filter { keep.contains($0.key) }
            goalSnapshotToday = (key, items)
        }
        // Not until the new day is five minutes old: quiet time before midnight is
        // counted until the idle cutoff rolls it back, and a closed day is never revisited.
        guard key != goalResultsDayKey, usage != nil,
              now().timeIntervalSince(today) >= Self.idleSettleSeconds else { return }
        goalResultsDayKey = key
        let snapshots = engine.store.goalSnapshotsByDay
        var recorded = engine.store.goalResultsByDay
        var changed = false
        for offset in 1...13 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let dayKey = DailyGoalList.dayKey(day, calendar: calendar)
            guard recorded[dayKey] == nil, let goals = snapshots[dayKey],
                  !DailyGoalList.active(goals).isEmpty else { continue }
            let reading = storyRailDay(on: day)
            let appUse = Dictionary(reading.apps.map { ($0.bundleID, $0.total) }, uniquingKeysWith: +)
            if let results = GoalDayResults.close(goals: goals, credit: reading.creditByCategory, appUse: appUse) {
                recorded[dayKey] = results
                changed = true
            }
        }
        if changed {
            engine.store.goalResultsByDay = recorded
            yesterdayPerfectCache = nil
        }
    }

    /// How long after midnight before a closed day is judged: past the idle cutoff
    /// that rolls usage back to the last input.
    static let idleSettleSeconds: TimeInterval = 5 * 60

    /// Whether every goal was met or kept on `day`.
    func wasPerfectDay(on day: Date) -> Bool {
        let key = DailyGoalList.dayKey(day, calendar: Calendar.current)
        return GoalDayResults.isPerfect(engine.store.goalResultsByDay[key] ?? [])
    }

    /// Whether yesterday was a perfect day, for Today's goals when no Yesterday
    /// notice carries it (no focus session, or the on-device model unavailable).
    var yesterdayWasPerfect: Bool {
        let calendar = Calendar.current
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now())) else { return false }
        let key = DailyGoalList.dayKey(yesterday, calendar: calendar)
        if let cached = yesterdayPerfectCache, cached.day == key { return cached.perfect }
        let perfect = wasPerfectDay(on: yesterday)
        yesterdayPerfectCache = (key, perfect)
        return perfect
    }

    /// Whether every goal was met or kept on the day `place` covers.
    func wasPerfectDay(_ place: HistoryPlace) -> Bool { wasPerfectDay(on: place.start) }

    /// Awards for the goals, from the recorded days.
    var goalAwards: [Award] {
        GoalDayResults.awards(results: engine.store.goalResultsByDay, items: goalItems,
                              name: { target in
                                  switch target {
                                  case .category(let id): return WorkType(rawValue: id).displayName
                                  case .app(let id): return self.historyAppName(for: id)
                                  default: return "Goal"
                                  }
                              }, calendar: Calendar.current)
    }
}
