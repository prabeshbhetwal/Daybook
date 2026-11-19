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
        guard key != goalResultsDayKey, usage != nil else { return }
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
        if changed { engine.store.goalResultsByDay = recorded }
    }

    /// Whether every goal was met or kept on the day `place` covers.
    func wasPerfectDay(_ place: HistoryPlace) -> Bool {
        let key = DailyGoalList.dayKey(place.start, calendar: Calendar.current)
        return GoalDayResults.isPerfect(engine.store.goalResultsByDay[key] ?? [])
    }

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
