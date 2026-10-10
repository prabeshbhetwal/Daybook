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

/// The text every lookup hands the model. Fixed wording, so the model quotes
/// facts rather than composing them, and capped, so a long history cannot
/// crowd out the question in the model's small context window. Every figure
/// a question may want is worked out here or in the store, never by the
/// model: averages, the longest session, the difference between two periods.
/// Past periods are spoken of in the past tense, so the model copies "was".
enum AskFacts {
    static let maximumBytes = 1_024

    /// Said last by an answer that came from a search, while a session runs
    /// in the range: a search reads saved sessions, and the running one is
    /// saved only when it ends.
    static let runningNote = " A session running now is not counted until it ends."

    /// Text over the cap is cut at the last line break or `; ` that leaves it
    /// within the cap with the ellipsis, or mid-text when there is none. The
    /// `tail` is kept whole after it, and the cap includes it.
    static func capped(_ text: String, keeping tail: String = "") -> String {
        let limit = maximumBytes - tail.utf8.count
        guard text.utf8.count > limit else { return text + tail }
        let ellipsis = "…"
        var kept = ""
        var bytes = 0
        for character in text {
            let size = character.utf8.count
            if bytes + size > limit - ellipsis.utf8.count { break }
            kept.append(character)
            bytes += size
        }
        // A separator that begins right where the kept text ends already
        // marks a boundary; only otherwise fall back to the last one inside.
        let rest = text.dropFirst(kept.count)
        if !(rest.hasPrefix("\n") || rest.hasPrefix("; ")) {
            let cuts = ["\n", "; "].compactMap { kept.range(of: $0, options: .backwards)?.lowerBound }
            if let cut = cuts.max() { kept = String(kept[..<cut]) }
        }
        return kept + ellipsis + tail
    }

    static func focusTotals(_ range: AskRange, words: String?, _ totals: AskTotals,
                            sessionRunning: Bool = false) -> String {
        // Only a search leaves the running session out; the plain total counts it.
        let tail = words != nil && sessionRunning ? runningNote : ""
        let app = totals.app.map { " \($0.name) itself was in front for \(DurationText.compact($0.total)) \(range.inPhrase)." }
        let phrase = placed(range, totals.dates)
        guard totals.sessions > 0 else {
            return capped((words.map { "No sessions match “\($0)” \(phrase)." }
                           ?? "No focus recorded \(phrase).") + (app ?? ""), keeping: tail)
        }
        let lead = words.map { "Sessions matching “\($0)” \(phrase)" } ?? sentenceStart(phrase)
        let verb = words == nil ? "focused over" : "over"
        var text = "\(lead): \(DurationText.compact(totals.focused)) \(verb) \(count(totals.sessions, "session"))"
            + " on \(count(totals.focusedDays, "day"))"
        if !range.isOneDay, totals.focusedDays > 1 {
            text += ", an average of \(DurationText.compact(totals.focused / Double(totals.focusedDays)))"
                + " on each day with focus"
        }
        for best in totals.best {
            text += "; the most focused \(best.unit) \(best.isCurrent ? "so far is" : "was") \(best.label), "
                + "with \(DurationText.compact(best.focused))"
        }
        if let first = totals.firstStart { text += "; the first session began at \(first)" }
        if let longest = totals.longest, totals.sessions > 1 {
            text += "; the longest finished session was \(longest.name) on \(longest.day), "
                + DurationText.compact(longest.worked)
        }
        text += "." + (app ?? "")
        if let parts = totals.parts, !parts.items.isEmpty {
            let items = parts.items.map { "\($0.label) \(DurationText.compact($0.focused))" }
            text += " By \(parts.name): \(items.joined(separator: ", "))."
        }
        return capped(text, keeping: tail)
    }

    /// Two ranges' focus and the difference between them, worked out from
    /// the minutes shown, so the figures given add up as the reader checks them.
    static func comparison(_ first: AskSide, _ second: AskSide, words: String?, sessionRunning: Bool = false) -> String {
        // The verdict names the dates too: told only "this month has less than last month", the
        // model said September had less than October when it was the other way round.
        func named(_ side: AskSide) -> String {
            side.range.title + (side.isCurrent ? " so far" : "") + (side.dates.map { " (\($0))" } ?? "")
        }
        func phrase(_ side: AskSide) -> String {
            side.range.inPhrase + (side.isCurrent ? " so far" : "") + (side.dates.map { " (\($0))" } ?? "")
        }
        let subject = words.map { "Sessions matching “\($0)”" } ?? "Focus"
        let a = shownMinutes(first.focused), b = shownMinutes(second.focused)
        var text = "\(subject) \(phrase(first)): \(DurationText.compact(a)); "
            + "\(phrase(second)): \(DurationText.compact(b)). "
        if a == b {
            text += "\(sentenceStart(named(first))) and \(named(second)) are level."
        } else {
            text += "\(sentenceStart(named(first))) has \(DurationText.compact(abs(a - b))) "
                + "\(a > b ? "more" : "less") than \(named(second))."
        }
        return capped(text, keeping: words != nil && sessionRunning ? runningNote : "")
    }

    static func bestHours(_ range: AskRange, span: String,
                          window: (startHour: Int, seconds: TimeInterval)?, strongest: String?) -> String {
        guard let window else {
            return capped("Not enough focus \(range.inPhrase) to tell; it needs at least 30m.")
        }
        var text = "\(span): most focus \(windowLabel(window.startHour)) (\(DurationText.compact(window.seconds)))"
        if let strongest { text += "; strongest \(strongest)" }
        return capped(text + ".")
    }

    /// `matched` is how many sessions matched, when `lines` holds only the
    /// newest of them. Empty words list every session in the range.
    static func sessions(_ range: AskRange, words: String, lines: [AskSessionLine],
                         matched: Int? = nil, sessionRunning: Bool = false, lead: String = "") -> String {
        var tail = ""
        if let matched, matched > lines.count { tail += " Newest \(lines.count) of \(matched)." }
        if sessionRunning { tail += runningNote }
        guard !lines.isEmpty else {
            let none = words.isEmpty ? "No sessions recorded" : "No sessions match “\(words)”"
            return capped("\(none) \(range.inPhrase).", keeping: tail)
        }
        let text = lines.map { line in
            var text = "\(line.day) · " + (line.time.isEmpty ? "" : "\(line.time) · ")
                + "\(line.name) · \(DurationText.compact(line.worked))"
            if let note = line.note, !note.isEmpty { text += " · note: \(note.prefix(80))" }
            return text
        }
        return capped(lead + text.joined(separator: "\n"), keeping: tail)
    }

    static func appTime(_ range: AskRange,
                        app: (query: String, name: String?, total: TimeInterval, sessions: Int)?,
                        top: [(name: String, total: TimeInterval)], sessionRunning: Bool = false) -> String {
        if let app {
            let tail = sessionRunning ? runningNote : ""
            guard let name = app.name else {
                return capped("No app called “\(app.query)” was used \(range.inPhrase).", keeping: tail)
            }
            return capped("\(name) \(range.inPhrase): \(DurationText.compact(app.total)) in front; "
                          + "used in \(count(app.sessions, "session")).", keeping: tail)
        }
        guard !top.isEmpty else { return capped("No app use recorded \(range.inPhrase).") }
        let apps = top.prefix(5).map { "\($0.name) \(DurationText.compact($0.total))" }
        return capped("Most-used apps \(range.inPhrase): \(apps.joined(separator: ", ")).")
    }

    /// A search that found nothing in its range, then the whole record's
    /// matches, cut as one list so "Newest 10 of N." and the running-session
    /// note are kept whole and said once.
    static func sessionsElsewhere(_ range: AskRange, words: String, lines: [AskSessionLine],
                                  matched: Int? = nil, sessionRunning: Bool = false) -> String {
        sessions(.allTime, words: words, lines: lines, matched: matched, sessionRunning: sessionRunning,
                 lead: "No sessions match “\(words)” \(range.inPhrase). In all your history:\n")
    }

    /// How a sentence places a range, with the dates a relative one covers:
    /// `last month (September 2026)`. Asked about September and August, the
    /// model compared this month with last month and called them September
    /// and August (probe, 2026-10-10); named, the months show the mix-up.
    static func placed(_ range: AskRange, _ dates: String?) -> String {
        range.inPhrase + (dates.map { " (\($0))" } ?? "")
    }

    /// What a lookup says when the model names a period there is no such
    /// thing as: an unknown name, or a date the calendar lacks, such as 31 February.
    static func noSuchPeriod(_ raw: String) -> String {
        "There is no such date as “\(raw)”."
    }

    /// What a lookup says about a period that starts after today.
    static func stillToCome(_ range: AskRange) -> String { "\(sentenceStart(range.title)) is still to come." }

    private static func count(_ n: Int, _ noun: String) -> String { n == 1 ? "1 \(noun)" : "\(n) \(noun)s" }

    private static func sentenceStart(_ text: String) -> String { text.prefix(1).uppercased() + text.dropFirst() }

    /// Seconds cut to the whole minutes `DurationText.compact` shows.
    private static func shownMinutes(_ seconds: TimeInterval) -> TimeInterval {
        TimeInterval((DurationText.wholeSeconds(seconds) ?? 0) / 60 * 60)
    }

    /// The two-hour window as `9–11am`, `11am–1pm` or `12–2am`.
    private static func windowLabel(_ startHour: Int) -> String {
        func clock(_ hour: Int) -> (number: Int, suffix: String) {
            (hour % 12 == 0 ? 12 : hour % 12, hour % 24 < 12 ? "am" : "pm")
        }
        let start = clock(startHour), end = clock(startHour + 2)
        return start.suffix == end.suffix
            ? "\(start.number)–\(end.number)\(end.suffix)"
            : "\(start.number)\(start.suffix)–\(end.number)\(end.suffix)"
    }
}
