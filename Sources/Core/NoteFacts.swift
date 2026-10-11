import Foundation

/// A day or a period as plain-text facts: what a review note is written from
/// and what the audit measures it against. Code works every figure out; the
/// model only words what it is handed.
struct NoteFacts: Equatable {
    enum Kind: Equatable { case day, period }

    let kind: Kind
    let lines: [String]
    /// Up to four candidate observations of a day, five of a week or month, in
    /// the order their rules are listed. A day always has "Focus began at …";
    /// a period may have none.
    let observations: [String]
    /// The observations kept for the pattern only, such as a drop in focus from
    /// the day before. The text lists them under "Context:", apart from the
    /// observations a tip may build on: the probe found the tip scolding
    /// whenever it was handed a drop, and parroting a mark put beside the
    /// observations it could use ("Use the call to Mum for a tip"). Empty on a
    /// period, which has no tip.
    var patternOnly: Set<String> = []
    /// How many sessions a week's or month's "Most time went to" line names, up
    /// to three; 0 on a day. The model is asked for a different form by it.
    var namedSessions = 0

    /// The lines, then "Observations:" and a bullet for each, then "Context:"
    /// and a bullet for each pattern-only one (a heading is left out when it
    /// has none), joined by newlines.
    var text: String {
        let usable = observations.filter { !patternOnly.contains($0) }
        let context = observations.filter(patternOnly.contains)
        var out = lines
        if !usable.isEmpty { out += ["Observations:"] + usable.map { "- " + $0 } }
        if !context.isEmpty { out += ["Context:"] + context.map { "- " + $0 } }
        return out.joined(separator: "\n")
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
