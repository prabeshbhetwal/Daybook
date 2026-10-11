import Foundation

/// An award as the Awards sheet shows it: its title and the line under it.
struct AskAwardLine: Equatable {
    let title: String
    let detail: String
}

/// How many days of a period met the goal, out of the days it has had so far.
/// `label` names the period with its dates: `This week (13 Nov – 19 Nov)`.
struct AskGoalPeriod: Equatable {
    let label: String
    let met: Int
    let days: Int
}

/// What `goals` says, all read by the store: the goal and today's goal credit
/// (`todayPercent` as the Story's goal tile words it), the days the period
/// met the goal, the streak on the store's clock (`streakSince` is the day it
/// began, as `askDay` says it, and nil when there is none) and the awards.
struct AskGoals: Equatable {
    let goal: TimeInterval
    let today: TimeInterval
    let todayPercent: String
    let period: AskGoalPeriod?
    let streakDays: Int
    let streakSince: String?
    let streakMinimum: TimeInterval
    let bestStreak: Int
    let earned: [AskAwardLine]
    let toEarn: [AskAwardLine]
}

extension AskFacts {
    /// One line each for the goal with today's progress, the period when one
    /// was asked about, the streak and the awards. The awards come last, so a
    /// cap cuts them before the figures.
    static func goals(_ goals: AskGoals) -> String {
        let progress = goals.today >= goals.goal
            ? "Today: \(DurationText.compact(goals.today)), met."
            : "Today so far: \(DurationText.compact(goals.today)), \(goals.todayPercent), not met yet."
        var lines = ["Daily goal: \(DurationText.compact(goals.goal)) of focus during recorded app use. \(progress)"]
        if let period = goals.period {
            lines.append("\(period.label): met on \(period.met) of \(period.days) days, against today's goal.")
        }
        let minimum = DurationText.compact(goals.streakMinimum)
        let longest = "Longest: \(count(goals.bestStreak, "day"))."
        if let since = goals.streakSince, goals.streakDays > 0 {
            lines.append("Current streak: \(count(goals.streakDays, "day")) with at least \(minimum) of focus, "
                         + "since \(since). \(longest)")
        } else {
            lines.append("No current streak: a day counts at \(minimum) of focus. \(longest)")
        }
        var awards = [goals.earned.isEmpty ? "No awards earned yet." : "Awards earned: \(awardList(goals.earned))."]
        if !goals.toEarn.isEmpty { awards.append("Still to earn: \(awardList(goals.toEarn)).") }
        lines.append(awards.joined(separator: " "))
        return capped(lines.joined(separator: "\n"))
    }

    private static func awardList(_ awards: [AskAwardLine]) -> String {
        awards.map { $0.detail.isEmpty ? $0.title : "\($0.title) (\($0.detail))" }.joined(separator: "; ")
    }
}
