import Foundation

/// A day or a period as plain-text facts: what a review note is written from
/// and what the audit measures it against. Code works every figure out; the
/// model only words what it is handed.
struct NoteFacts: Equatable {
    enum Kind: Equatable { case day, period }

    let kind: Kind
    let lines: [String]
    /// Up to four candidate observations, in the order their rules are
    /// listed. A day always has "Focus began at …"; a period may have none.
    let observations: [String]

    /// The lines, then "Observations:" and a bullet for each (the heading
    /// is left out when there are none), joined by newlines.
    var text: String {
        guard !observations.isEmpty else { return lines.joined(separator: "\n") }
        return (lines + ["Observations:"] + observations.map { "- " + $0 }).joined(separator: "\n")
    }
}

/// A note as the model returns it: a story, a pattern and, on days, a tip.
struct WrittenNote: Equatable {
    let story: String
    let pattern: String
    let tip: String?
}

/// What one day is described from. `sessionCount` is the sessions as History
/// counts them: a session resumed after another is one, so the count can be
/// below `sessions`. `previousFocused` is the day before's focus, 0 when there
/// is none.
struct NoteDayInput {
    let date: Date
    let isCurrent: Bool
    let sessions: [DaySession]
    let sessionCount: Int
    let apps: [AppRank]
    let focused: TimeInterval
    let goal: TimeInterval
    let goalCredit: TimeInterval
    let previousFocused: TimeInterval
}

/// What one week or month is described from. `sessionTotals` is busiest
/// first; `previousFocused` is the period before's focus, 0 when there is none.
struct NotePeriodInput {
    let span: DateInterval
    let level: HistoryLevel
    let isCurrent: Bool
    let summary: HistorySummary
    let sessionTotals: [(name: String, worked: TimeInterval)]
    let goal: TimeInterval
    let goalMetDays: Int
    let previousFocused: TimeInterval
}
