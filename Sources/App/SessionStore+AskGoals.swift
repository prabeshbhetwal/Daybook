import Foundation

/// Ask's account of the daily goal, the streak and the awards. Each figure is
/// read from the place its screen reads it: the goal setting; a day's goal
/// credit from the Story's day projection (focus during recorded app use, the
/// goal tile's figure) and the days met counted as the notes count them; the
/// streak on the store's clock; the awards the Awards sheet shows. `AskFacts` only words them.
extension SessionStore {
    func askGoals(_ range: AskRange?) -> AskLookupResult {
        let calendar = periodCalendar
        let goal = engine.store.dailyGoal
        let today = storyDayProjection(on: calendar.startOfDay(for: now()), calendar: calendar).goalCredit
        let awards = self.awards
        // One reading of the running session's seconds for the streak and the
        // best, so the streak cannot pass the best between two reads.
        let inFlight = engine.elapsedToday()
        let streak = askStreak(includingToday: inFlight)
        let goals = AskGoals(
            goal: goal, today: today,
            todayPercent: DurationText.percent(GoalProgress(goal: goal, achieved: today, typical: nil).share),
            period: range.map { askGoalPeriod($0, goal: goal) },
            streakDays: streak?.days ?? 0, streakSince: streak.map { askDay($0.since) },
            streakMinimum: engine.store.streakMinimum, bestStreak: engine.bestStreak(includingToday: inFlight),
            earned: awards.filter(\.isEarned).map { AskAwardLine(title: $0.title, detail: $0.detail) },
            toEarn: awards.filter { !$0.isEarned }.map { AskAwardLine(title: $0.title, detail: $0.detail) })
        // An award is named by the words that name Awards, and by its title.
        let names = ["streak", "streaks", "award", "awards"] + awards.map(\.title)
        return AskLookupResult(
            text: AskFacts.goals(goals),
            links: [askPeriodLink(range ?? .today, role: .dailyGoal),
                    AskLink(target: .awards, label: "Awards", role: .streakAndAwards, names: names)])
    }

    /// The days of the range, from the first day on record to today, whose
    /// goal credit reached today's goal: counted as the notes count them.
    private func askGoalPeriod(_ range: AskRange, goal: TimeInterval) -> AskGoalPeriod {
        let calendar = periodCalendar
        let interval = askInterval(range)
        let today = calendar.startOfDay(for: now())
        var cursor = calendar.startOfDay(for: max(interval.start, historyTop().firstDay))
        var met = 0, days = 0
        while cursor < interval.end, cursor <= today {
            days += 1
            if storyDayProjection(on: cursor, calendar: calendar).goalCredit >= goal { met += 1 }
            cursor = HistoryTreeBuilder.dayAfter(cursor, calendar: calendar)
        }
        return AskGoalPeriod(label: askTitled(range), met: met, days: days)
    }
}
