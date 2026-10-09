import Foundation

/// The periods Ask Daybook can look up: a closed set, so the model names one
/// of eight rather than inventing dates, and each one is the period History
/// draws under the same name.
enum AskRange: String, CaseIterable, Sendable {
    case today
    case yesterday
    case thisWeek = "this week"
    case lastWeek = "last week"
    case thisMonth = "this month"
    case lastMonth = "last month"
    case last30Days = "last 30 days"
    case allTime = "all time"

    /// Half-open `[start, end)`. Pass `Calendar.forPeriods`, so a week starts
    /// on Monday and a month is the Gregorian month wherever the Mac is set.
    func interval(now: Date, firstDay: Date, calendar: Calendar) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        func period(_ component: Calendar.Component, offset: Int) -> DateInterval {
            let anchor = calendar.date(byAdding: component, value: offset, to: today) ?? today
            return calendar.dateInterval(of: component, for: anchor) ?? DateInterval(start: today, end: tomorrow)
        }
        switch self {
        case .today: return period(.day, offset: 0)
        case .yesterday: return period(.day, offset: -1)
        case .thisWeek: return period(.weekOfYear, offset: 0)
        case .lastWeek: return period(.weekOfYear, offset: -1)
        case .thisMonth: return period(.month, offset: 0)
        case .lastMonth: return period(.month, offset: -1)
        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
            return DateInterval(start: start, end: tomorrow)
        case .allTime:
            return DateInterval(start: min(calendar.startOfDay(for: firstDay), today), end: tomorrow)
        }
    }

    /// The History level that holds this range's breakdown; `nil` when none does.
    var level: HistoryLevel? {
        switch self {
        case .today, .yesterday: return .day
        case .thisWeek, .lastWeek: return .week
        case .thisMonth, .lastMonth, .last30Days: return .month
        case .allTime: return nil
        }
    }

    /// How a sentence places something in this range.
    var inPhrase: String {
        switch self {
        case .last30Days: return "in the last 30 days"
        case .allTime: return "in all your history"
        default: return rawValue
        }
    }
}

/// One lookup the model can make. `provenance` is what the sheet shows under
/// the answer, so the reader can see which facts it rested on.
enum AskRequest: Equatable, Sendable {
    case focusTotals(AskRange, words: String?)
    case bestHours(AskRange)
    case findSessions(words: String, AskRange)
    case appTime(AskRange, app: String?)

    var provenance: String {
        switch self {
        case let .focusTotals(range, words):
            return "focus totals" + (words.map { " matching “\($0)”" } ?? "") + " (\(range.rawValue))"
        case let .bestHours(range): return "best hours (\(range.rawValue))"
        case let .findSessions(words, range): return "sessions matching “\(words)” (\(range.rawValue))"
        case let .appTime(range, app): return "app time" + (app.map { " for \($0)" } ?? "") + " (\(range.rawValue))"
        }
    }
}

/// The text every lookup hands the model. Fixed wording, so the model quotes
/// facts rather than composing them, and capped, so a long history cannot
/// crowd out the question in the model's small context window.
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

    static func focusTotals(_ range: AskRange, words: String?, focused: TimeInterval, sessions: Int,
                            focusedDays: Int,
                            best: (unit: String, label: String, focused: TimeInterval)?,
                            parts: (name: String, items: [(label: String, focused: TimeInterval)])?,
                            sessionRunning: Bool = false) -> String {
        // Only a search leaves the running session out; the plain total counts it.
        let tail = words != nil && sessionRunning ? runningNote : ""
        guard sessions > 0 else {
            return capped(words.map { "No sessions match “\($0)” \(range.inPhrase)." }
                          ?? "No focus recorded \(range.inPhrase).", keeping: tail)
        }
        let lead = words.map { "Sessions matching “\($0)” \(range.inPhrase)" } ?? sentenceStart(range.inPhrase)
        let verb = words == nil ? "focused over" : "over"
        var text = "\(lead): \(DurationText.compact(focused)) \(verb) \(count(sessions, "session")) on \(count(focusedDays, "day"))"
        if let best {
            text += "; best \(best.unit) \(best.label), \(DurationText.compact(best.focused))"
        }
        text += "."
        if let parts, !parts.items.isEmpty {
            let items = parts.items.map { "\($0.label) \(DurationText.compact($0.focused))" }
            text += " By \(parts.name): \(items.joined(separator: ", "))."
        }
        return capped(text, keeping: tail)
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

    static func sessions(_ range: AskRange, words: String,
                         hits: [(day: String, name: String, worked: TimeInterval, note: String?)],
                         sessionRunning: Bool = false) -> String {
        let tail = sessionRunning ? runningNote : ""
        guard !hits.isEmpty else { return capped("No sessions match “\(words)” \(range.inPhrase).", keeping: tail) }
        let lines = hits.map { hit in
            var line = "\(hit.day) · \(hit.name) · \(DurationText.compact(hit.worked))"
            if let note = hit.note, !note.isEmpty { line += " · note: \(note.prefix(80))" }
            return line
        }
        return capped(lines.joined(separator: "\n"), keeping: tail)
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

    private static func count(_ n: Int, _ noun: String) -> String { n == 1 ? "1 \(noun)" : "\(n) \(noun)s" }

    private static func sentenceStart(_ text: String) -> String { text.prefix(1).uppercased() + text.dropFirst() }

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
