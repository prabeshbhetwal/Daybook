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

    /// Writes the results of the last few closed days that have none, once a
    /// day. Today is not written: the card shows it live. A day is written
    /// with the goals as they stand then and is never recomputed, so a later
    /// edit or a deleted goal cannot change what that day showed. Only when
    /// goals are in use and the app-use record is loaded, so a day is never
    /// judged on missing evidence.
    func recordGoalResultsIfNewDay() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now())
        let key = DailyGoalList.dayKey(today, calendar: calendar)
        guard key != goalResultsDayKey, usage != nil else { return }
        goalResultsDayKey = key
        let items = goalItems
        guard !DailyGoalList.active(items).isEmpty else { return }
        var recorded = engine.store.goalResultsByDay
        var changed = false
        for offset in 1...3 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let dayKey = DailyGoalList.dayKey(day, calendar: calendar)
            guard recorded[dayKey] == nil else { continue }
            let reading = storyRailDay(on: day)
            let results = GoalDayResults.judge(items, credit: reading.creditByCategory,
                                               appUse: Dictionary(reading.apps.map { ($0.bundleID, $0.total) },
                                                                  uniquingKeysWith: +))
            if !results.isEmpty { recorded[dayKey] = results; changed = true }
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
                              name: { item in
                                  switch item.target {
                                  case .category(let id): return WorkType(rawValue: id).displayName
                                  case .app(let id): return self.historyAppName(for: id)
                                  default: return "Goal"
                                  }
                              }, calendar: Calendar.current)
    }
}
