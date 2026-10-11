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
    /// The observations a day's tip may build on. The rest, such as a drop
    /// from the day before, are for the pattern only: the probe found the tip
    /// scolding whenever it was handed one. Empty on a period, which has no tip.
    var tipObservations: Set<String> = []

    static let tipMark = " (usable for a tip)"

    /// The lines, then "Observations:" and a bullet for each (the heading
    /// is left out when there are none), joined by newlines. A bullet a tip
    /// may build on says so.
    var text: String {
        guard !observations.isEmpty else { return lines.joined(separator: "\n") }
        let bullets = observations.map { "- " + $0 + (tipObservations.contains($0) ? Self.tipMark : "") }
        return (lines + ["Observations:"] + bullets).joined(separator: "\n")
    }
}

/// A note as the model returns it: a story, a pattern and, on days, a tip.
struct WrittenNote: Equatable {
    let story: String
    let pattern: String
    let tip: String?
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
/// below `sessions`. `previousFocused` is the day before's focus, 0 when there
/// is none. `longestStretch` comes from the Story's own computation, so the
/// facts cannot count a pause as focus.
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
    let longestStretch: NoteStretch?
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
