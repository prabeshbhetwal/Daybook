import Foundation

/// The plain figures an award is judged from. Values only, so the composition
/// is pure and a test can hand it a history without an archive behind it.
struct AwardFacts: Equatable {
    /// The daily focus goal in seconds. Zero means no goal is set, and the
    /// goal-based award is withheld rather than judged against nothing.
    var goal: TimeInterval = 0
    /// Goal credit per local day, keyed by start of day. This must be the same
    /// measure the rest of the app calls "goal met" — a day that counts here
    /// and not on Today would be two truths on one screen.
    var goalCreditByDay: [Date: TimeInterval] = [:]
    /// The single longest focus stretch on record, and the day it happened.
    var longestStretch: (seconds: TimeInterval, day: Date)?
    /// Days with any tracked time.
    var activeDays: Int = 0
    /// Total focused time across the whole record.
    var totalFocused: TimeInterval = 0
    var currentStreak: Int = 0
    var bestStreak: Int = 0

    static func == (lhs: AwardFacts, rhs: AwardFacts) -> Bool {
        lhs.goal == rhs.goal
            && lhs.goalCreditByDay == rhs.goalCreditByDay
            && lhs.longestStretch?.seconds == rhs.longestStretch?.seconds
            && lhs.longestStretch?.day == rhs.longestStretch?.day
            && lhs.activeDays == rhs.activeDays
            && lhs.totalFocused == rhs.totalFocused
            && lhs.currentStreak == rhs.currentStreak
            && lhs.bestStreak == rhs.bestStreak
    }
}

/// One earned or unearned award. Nothing here is motivational copy: `detail`
/// is the evidence that earned it, and an unearned award states real progress
/// rather than an exhortation.
struct Award: Identifiable, Equatable {
    let id: String
    let title: String
    /// The short line under the title — a date, a duration, or progress.
    let detail: String
    /// Exactly what was measured, for a reader who wants the method.
    let method: String
    let symbolName: String
    /// Identity colour, taken from the shared app ramp.
    let paletteRank: Int
    let isEarned: Bool
}

/// Awards are computed from the record, never stored. Nothing is awarded that
/// the local history does not already prove, and an award is never announced
/// during a session — this surface is somewhere the user comes and finds.
enum Awards {

    /// A run of consecutive local days that met the goal.
    struct GoalRun: Equatable {
        let length: Int
        let start: Date?
        let end: Date?

        static let none = GoalRun(length: 0, start: nil, end: nil)
    }

    static let goalRunTarget = 7
    static let activeDayTarget = 30
    static let focusedHoursTarget: TimeInterval = 100 * 3_600

    /// The longest unbroken run of goal-meeting days, with the dates that
    /// bound it. Days are consecutive by the calendar, so a missing day breaks
    /// the run even when the archive simply holds no record for it.
    static func longestGoalRun(_ facts: AwardFacts,
                               calendar: Calendar = .current) -> GoalRun {
        guard facts.goal > 0 else { return .none }
        let met = facts.goalCreditByDay
            .filter { $0.value >= facts.goal }
            .keys
            .map { calendar.startOfDay(for: $0) }
            .sorted()
        guard !met.isEmpty else { return .none }

        var best = GoalRun(length: 1, start: met[0], end: met[0])
        var runStart = met[0]
        var runLength = 1
        for index in 1..<met.count {
            let previous = met[index - 1]
            let day = met[index]
            let followsOn = calendar.date(byAdding: .day, value: 1, to: previous)
                .map { calendar.isDate($0, inSameDayAs: day) } ?? false
            if followsOn {
                runLength += 1
            } else {
                runStart = day
                runLength = 1
            }
            if runLength > best.length {
                best = GoalRun(length: runLength, start: runStart, end: day)
            }
        }
        return best
    }

    static func all(from facts: AwardFacts, calendar: Calendar = .current) -> [Award] {
        [goalRunAward(facts, calendar: calendar),
         longestStretchAward(facts),
         activeDaysAward(facts),
         focusedHoursAward(facts)]
    }

    private static func goalRunAward(_ facts: AwardFacts, calendar: Calendar) -> Award {
        let run = longestGoalRun(facts, calendar: calendar)
        let earned = run.length >= goalRunTarget
        let detail: String
        if earned, let start = run.start, let end = run.end {
            detail = "\(dayMonth(start)) – \(dayMonth(end))"
        } else if facts.goal <= 0 {
            detail = "No daily goal set"
        } else {
            detail = "\(run.length) of \(goalRunTarget) days"
        }
        return Award(id: "goal-run",
                     title: "Goal, \(goalRunTarget) days",
                     detail: detail,
                     method: "The longest unbroken run of days that reached your daily goal, "
                           + "measured with the same goal credit as Today.",
                     symbolName: "target",
                     paletteRank: 0,
                     isEarned: earned)
    }

    private static func longestStretchAward(_ facts: AwardFacts) -> Award {
        guard let longest = facts.longestStretch, longest.seconds > 0 else {
            return Award(id: "longest-stretch",
                         title: "Longest stretch",
                         detail: "No focus session recorded yet",
                         method: "The longest single focus stretch in your local record.",
                         symbolName: "flame",
                         paletteRank: 4,
                         isEarned: false)
        }
        return Award(id: "longest-stretch",
                     title: "Longest stretch",
                     detail: "\(DurationText.compact(longest.seconds)) · \(dayMonth(longest.day))",
                     method: "The longest single focus stretch in your local record, "
                           + "counting only the work inside that one stretch.",
                     symbolName: "flame",
                     paletteRank: 4,
                     isEarned: true)
    }

    private static func activeDaysAward(_ facts: AwardFacts) -> Award {
        let earned = facts.activeDays >= activeDayTarget
        return Award(id: "active-days",
                     title: "\(activeDayTarget) active days",
                     detail: earned
                        ? "\(facts.activeDays) days recorded"
                        : "\(facts.activeDays) so far",
                     method: "Days with any tracked time at the Mac, for as long as the "
                           + "record goes back.",
                     symbolName: "calendar",
                     paletteRank: 1,
                     isEarned: earned)
    }

    private static func focusedHoursAward(_ facts: AwardFacts) -> Award {
        let earned = facts.totalFocused >= focusedHoursTarget
        let hours = Int(focusedHoursTarget / 3_600)
        return Award(id: "focused-hours",
                     title: "\(hours) hours focused",
                     detail: earned
                        ? "\(DurationText.compact(facts.totalFocused)) recorded"
                        : "\(DurationText.compact(facts.totalFocused)) so far",
                     method: "Every focus session you have recorded, added together.",
                     symbolName: "hourglass",
                     paletteRank: 3,
                     isEarned: earned)
    }

    // MARK: - Phrasing

    private static func dayMonth(_ date: Date) -> String {
        DateFormats.australian("d MMM").string(from: date)
    }
}
