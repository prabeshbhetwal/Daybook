import Foundation

/// One lookup the model can make. `provenance` is what the sheet shows under
/// the answer, so the reader can see which facts it rested on.
enum AskRequest: Equatable, Sendable {
    case focusTotals(AskRange, words: String?)
    case bestHours(AskRange)
    /// Empty words list every session in the range.
    case findSessions(words: String, AskRange)
    case appTime(AskRange, app: String?)
    case compare(AskRange, with: AskRange, words: String?)
    case dayEvents(AskRange)

    /// Periods by their titles, so a named month reads `August 2026`, not `2026-08`.
    var provenance: String {
        switch self {
        case let .focusTotals(range, words):
            return "focus totals" + Self.matching(words) + " (\(range.title))"
        case let .bestHours(range): return "best hours (\(range.title))"
        case let .findSessions(words, range):
            return "sessions" + Self.matching(words.isEmpty ? nil : words) + " (\(range.title))"
        case let .appTime(range, app): return "app time" + (app.map { " for \($0)" } ?? "") + " (\(range.title))"
        case let .compare(first, second, words):
            return "comparison" + Self.matching(words) + " (\(first.title) with \(second.title))"
        case let .dayEvents(range): return "what happened (\(range.title))"
        }
    }

    private static func matching(_ words: String?) -> String { words.map { " matching “\($0)”" } ?? "" }
}

/// A range's most focused day, week or month. `isCurrent` when it holds
/// today: it may yet be beaten, so it is said to be the best so far.
struct AskBest {
    let unit: String
    let label: String
    let focused: TimeInterval
    var isCurrent = false
}

/// One side of a comparison: its range, its focus, whether it holds today,
/// and the dates a relative range covers.
struct AskSide {
    let range: AskRange
    let focused: TimeInterval
    var isCurrent = false
    var dates: String?
}

/// A named part of a range's focus: a work type and its time.
struct AskShare: Equatable {
    let name: String
    let seconds: TimeInterval
}

/// One range's figures, gathered by the store for `AskFacts.focusTotals`.
struct AskTotals {
    /// The dates a relative range covers, as `September 2026`: see `AskFacts.placed`.
    var dates: String?
    var focused: TimeInterval = 0
    var sessions = 0
    var focusedDays = 0
    /// The most focused day, week and month inside the range, smallest first.
    var best: [AskBest] = []
    /// When the first session of a one-day range began, as `9:10am`.
    var firstStart: String?
    /// The longest session that has ended, with the day it is listed under.
    var longest: (name: String, day: String, worked: TimeInterval)?
    /// The app the words name and its own time in front, which is not the
    /// time of the sessions it was used in.
    var app: (name: String, total: TimeInterval)?
    var parts: (name: String, items: [(label: String, focused: TimeInterval)])?
    /// The range's focus by work type, as History's cards split it, largest first.
    var workTypes: [AskShare] = []
    /// The current streak, in days, and the day it began, as `Fri 10 Nov`; all time only.
    var streak: (days: Int, since: String)?
    /// When the app the words name was in front: an `AskFacts.hoursPhrase`.
    var appHours: String?
    /// The first note line that holds a word of the search.
    var noteLine: String?

    /// The text names the longest session only when there is more than one to choose from.
    var namesLongest: Bool { sessions > 1 }
}

/// One session in a list: the day and time it began in the range, its name,
/// the work inside the range and the note line that matched.
struct AskSessionLine {
    let day: String
    let time: String
    let name: String
    let worked: TimeInterval
    var note: String?
}
