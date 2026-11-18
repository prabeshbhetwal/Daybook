import Foundation

/// How a day's goals came out, and the awards that follow from a run of such
/// days. Pure: values in, values out, so a test hands it a history directly.
enum GoalDayResults {
    /// Judges the active goals against what the day came to. A target is met at
    /// its amount; an app limit is kept at or under it. Both compare the
    /// minutes as they are printed, so the card and the record agree.
    /// - Parameters:
    ///   - credit: focus with app use recorded, by category id.
    ///   - appUse: all recorded foreground time, by bundle id.
    static func judge(_ items: [DailyGoalItem], credit: [String: TimeInterval],
                      appUse: [String: TimeInterval]) -> [DailyGoalResult] {
        let minutes = { (DurationText.wholeSeconds($0) ?? 0) / 60 }
        return DailyGoalList.usable(items).compactMap { item in
            // A paused goal is recorded as paused, so the day is known to have skipped it.
            if item.isPaused {
                return DailyGoalResult(goalID: item.id, target: item.target, kind: item.kind,
                                       amount: item.seconds, counted: 0, met: false, paused: true)
            }
            switch item.target {
            case .category(let id) where item.kind == .target:
                let counted = credit[id] ?? 0
                return DailyGoalResult(goalID: item.id, target: item.target, kind: item.kind,
                                       amount: item.seconds, counted: counted,
                                       met: minutes(counted) >= minutes(item.seconds))
            case .app(let id) where item.kind == .limit:
                let counted = appUse[id] ?? 0
                return DailyGoalResult(goalID: item.id, target: item.target, kind: item.kind,
                                       amount: item.seconds, counted: counted,
                                       met: minutes(counted) <= minutes(item.seconds))
            default: return nil
            }
        }
    }

    /// The results to record for a closed day, from the goals that stood on it.
    /// Nil when nothing about the day was recorded: with no app use at all the
    /// recording may have been off, and a limit would read as kept and a target
    /// as missed on no evidence.
    static func close(goals: [DailyGoalItem], credit: [String: TimeInterval],
                      appUse: [String: TimeInterval]) -> [DailyGoalResult]? {
        guard appUse.values.contains(where: { $0 > 0 }) || credit.values.contains(where: { $0 > 0 }) else { return nil }
        let results = judge(goals, credit: credit, appUse: appUse)
        return results.isEmpty ? nil : results
    }

    /// Every target met and every limit kept, with at least one goal in use. A
    /// paused goal is left out, and a day with no goals in use is not perfect.
    static func isPerfect(_ results: [DailyGoalResult]) -> Bool {
        let counted = results.filter { $0.paused != true }
        return !counted.isEmpty && counted.allSatisfy(\.met)
    }

    /// The longest run of consecutive calendar days among `days`.
    static func longestRun(_ days: [Date], calendar: Calendar) -> Int {
        let sorted = Set(days.map { calendar.startOfDay(for: $0) }).sorted()
        var best = 0, run = 0
        var previous: Date?
        for day in sorted {
            if let previous, let next = calendar.date(byAdding: .day, value: 1, to: previous),
               calendar.isDate(next, inSameDayAs: day) {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        return best
    }

    static let goalRunTarget = 5
    static let perfectWeekTarget = 7

    /// A perfect week, and a run award for each goal that is in use. Computed
    /// from the recorded days, never stored: a day with no record is a gap.
    static func awards(results: [String: [DailyGoalResult]], items: [DailyGoalItem],
                       name: (DailyGoalItem) -> String, calendar: Calendar) -> [Award] {
        func days(_ keep: ([DailyGoalResult]) -> Bool) -> [Date] {
            results.compactMap { key, value in keep(value) ? DailyGoalList.date(forKey: key, calendar: calendar) : nil }
        }
        let perfect = longestRun(days(isPerfect), calendar: calendar)
        var awards = [Award(id: "perfect-week", title: "Perfect week",
                            detail: perfect >= perfectWeekTarget ? "\(perfect) perfect days in a row"
                                                                 : "\(perfect) of \(perfectWeekTarget) days",
                            method: "Seven days in a row on which every goal was met or kept, from the days "
                                  + "Daybook has recorded goals for.",
                            symbolName: "checkmark.seal", paletteRank: 0, isEarned: perfect >= perfectWeekTarget)]
        for item in DailyGoalList.active(items) {
            let run = goalRun(item.id, in: results, calendar: calendar)
            let isLimit = item.kind == .limit
            awards.append(Award(
                id: "goal-\(item.id.uuidString)",
                title: isLimit ? "Kept to \(name(item)) limit, \(goalRunTarget) days" : "\(name(item)) goal, \(goalRunTarget) days",
                detail: run >= goalRunTarget ? "\(run) days in a row" : "\(run) of \(goalRunTarget) days",
                method: isLimit ? "Days in a row on which the app stayed within its limit."
                                : "Days in a row on which the goal was met, counted with focus that has app use recorded.",
                symbolName: isLimit ? "hourglass" : "target", paletteRank: 1, isEarned: run >= goalRunTarget))
        }
        return awards
    }

    /// The longest run of days a goal was met, in calendar order. A paused day
    /// neither breaks the run nor adds to it; a missed day, or a day with no
    /// record, breaks it.
    static func goalRun(_ id: UUID, in results: [String: [DailyGoalResult]], calendar: Calendar) -> Int {
        let days = results.compactMap { key, value -> (Date, DailyGoalResult)? in
            guard let date = DailyGoalList.date(forKey: key, calendar: calendar),
                  let result = value.first(where: { $0.goalID == id }) else { return nil }
            return (date, result)
        }.sorted { $0.0 < $1.0 }
        var best = 0, run = 0
        var previous: Date?
        for (date, result) in days {
            if let previous, let next = calendar.date(byAdding: .day, value: 1, to: previous),
               !calendar.isDate(next, inSameDayAs: date) { run = 0 }
            if result.paused == true { /* neither */ } else if result.met { run += 1; best = max(best, run) } else { run = 0 }
            previous = date
        }
        return best
    }
}
