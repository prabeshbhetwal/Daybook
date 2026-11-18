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
}
