import Foundation

/// A day or a period as plain-text facts: what a review note is written from
/// and what the audit measures it against. Code works every figure out; the
/// model only words what it is handed.
struct NoteFacts: Equatable {
    enum Kind: Equatable { case day, period }

    let kind: Kind
    let lines: [String]
    /// Up to four candidate observations of a day, five of a week or month, in
    /// the order their rules are listed. Either may have none.
    let observations: [String]
    /// How many sessions a week's or month's "Most time went to" line names, up
    /// to three; 0 on a day. The model is asked for a different form by it.
    var namedSessions = 0

    /// The lines, then "Observations:" and a bullet for each (the heading is
    /// left out when there are none), joined by newlines.
    var text: String {
        (observations.isEmpty ? lines : lines + ["Observations:"] + observations.map { "- " + $0 })
            .joined(separator: "\n")
    }
}

/// A note as the model returns it: a story and a pattern. There is no tip: a
/// live probe found every tip the model wrote useless or invented ("Keep Coding
/// sessions running past midnight", "Try using Xcode for 4 hours today"), even
/// when the facts held something worth acting on.
struct WrittenNote: Equatable {
    let story: String
    let pattern: String
}

/// The longest stretch of focus on a day, worked out as the Story works out
/// its own: the work of one recorded stretch with its pauses taken out, which
/// is shorter than the time between its start and end whenever it was paused.
struct NoteStretch: Equatable {
    let name: String
    let start: Date
    let worked: TimeInterval
}

/// What one day is described from. `sessionCount` is the sessions as History
/// counts them: a session resumed after another is one, so the count can be
/// below `sessions`. `goalCredit` is the focus the goal counts, the part with
/// hands-on use, so it can be below `focused`. `typicalFocused` and
/// `typicalStretch` are the person's own baseline, the medians of the
/// `typicalDays` days with focus among the 14 before (`NoteBaseline`), 0 when
/// there is none.
/// `longestStretch` comes from the Story's own computation, so the facts cannot
/// count a pause as focus. `focusByPart` is the day's focus split by
/// `NoteDayPart`, from each stretch's own work.
struct NoteDayInput {
    let date: Date
    let isCurrent: Bool
    let sessions: [DaySession]
    let sessionCount: Int
    let apps: [AppRank]
    let focused: TimeInterval
    let goal: TimeInterval
    let goalCredit: TimeInterval
    let typicalFocused: TimeInterval
    let typicalStretch: TimeInterval
    let typicalDays: Int
    let longestStretch: NoteStretch?
    let focusByPart: [NoteDayPart: TimeInterval]
}

/// A part of the day, for when a day's focus came. Night runs from 10 pm to
/// 5 am, so it holds both ends of the day.
enum NoteDayPart: CaseIterable {
    case morning, afternoon, evening, night

    var phrase: String {
        switch self {
        case .morning: return "in the morning, between 5 am and noon"
        case .afternoon: return "in the afternoon, between noon and 5 pm"
        case .evening: return "in the evening, between 5 pm and 10 pm"
        case .night: return "at night, after 10 pm or before 5 am"
        }
    }

    /// The part's hours on the day's clock, each [start, end); 24 is the day's end.
    var hours: [(from: Int, to: Int)] {
        switch self {
        case .morning: return [(5, 12)]
        case .afternoon: return [(12, 17)]
        case .evening: return [(17, 22)]
        case .night: return [(0, 5), (22, 24)]
        }
    }
}

/// The person's typical day, from the days with focus in the window before the
/// one described: the median focus, the median of each day's focus per
/// stretch, and how many days they are drawn from. The window and the fewest
/// days are the daily goal's pace baseline's defaults; the window does not
/// follow the pace setting, so changing that does not rewrite notes. Too few
/// days is no baseline, and all three are 0.
enum NoteBaseline {
    static let days = FocusConstants.goalMedianWindowDays

    static func typical(_ earlier: [(focused: TimeInterval, stretches: Int)])
        -> (focused: TimeInterval, stretch: TimeInterval, days: Int) {
        let days = earlier.filter { $0.focused > 0 && $0.stretches > 0 }
        guard days.count >= FocusConstants.goalMedianMinimumDays else { return (0, 0, 0) }
        return (days.map(\.focused).median, days.map { $0.focused / Double($0.stretches) }.median, days.count)
    }
}

/// The weekday a month's focus went most to: `date` is any day on it, `days`
/// how many of its days had focus.
struct NoteWeekday: Equatable {
    let date: Date
    let focused: TimeInterval
    let days: Int
}

/// What one week or month is described from. `sessionTotals` is busiest
/// first; `previousFocused` is the period before's focus, 0 when there is none.
/// `longestStretch` is the Story's own, as a day's; `busiestWeekday` is a
/// month's, nil when the month's focus fell on one weekday only.
struct NotePeriodInput {
    let span: DateInterval
    let level: HistoryLevel
    let isCurrent: Bool
    let summary: HistorySummary
    let sessionTotals: [(name: String, worked: TimeInterval)]
    let goal: TimeInterval
    let goalMetDays: Int
    let previousFocused: TimeInterval
    var longestStretch: NoteStretch?
    var busiestWeekday: NoteWeekday?
}
