import Foundation

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
        // What the words found beyond the sessions: the app's hours, a note's line.
        let found = (totals.appHours.map { " Most in front \($0)." } ?? "")
            + (totals.noteLine.map { " A matching note: “\($0)”." } ?? "")
        let phrase = placed(range, totals.dates)
        guard totals.sessions > 0 else {
            return capped((words.map { "No sessions match “\($0)” \(phrase)." }
                           ?? "No focus recorded \(phrase).") + (app ?? "") + found, keeping: tail)
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
        if let longest = totals.longest, totals.namesLongest {
            text += "; the longest finished session was \(longest.name) on \(longest.day), "
                + DurationText.compact(longest.worked)
        }
        text += "." + (app ?? "") + found
        if !totals.workTypes.isEmpty {
            text += " By work type: " + totals.workTypes.map { "\($0.name) \(DurationText.compact($0.seconds))" }
                .joined(separator: ", ") + "."
        }
        if let streak = totals.streak {
            text += " The current streak is \(count(streak.days, "day")), since \(streak.since)."
        }
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
            // “from” marks the time as a start: the model read `2:00pm · Parser · 4h` as 2h 00m.
            var text = "\(line.day) · \(line.name) · " + (line.time.isEmpty ? "" : "from \(line.time) · ")
                + DurationText.compact(line.worked)
            if let note = line.note, !note.isEmpty { text += " · note: \(note.prefix(80))" }
            return text
        }
        return capped(lead + text.joined(separator: "\n"), keeping: tail)
    }

    static func appTime(_ range: AskRange,
                        app: (query: String, name: String?, total: TimeInterval, sessions: Int)?,
                        top: [(name: String, total: TimeInterval)], sessionRunning: Bool = false,
                        hours: [TimeInterval]? = nil) -> String {
        let phrase = hours.flatMap(hoursPhrase)
        if let app {
            let tail = sessionRunning ? runningNote : ""
            guard let name = app.name else {
                return capped("No app called “\(app.query)” was used \(range.inPhrase).", keeping: tail)
            }
            return capped("\(name) \(range.inPhrase): \(DurationText.compact(app.total)) in front; "
                          + "used in \(count(app.sessions, "session"))"
                          + (phrase.map { "; most in front \($0)" } ?? "") + ".", keeping: tail)
        }
        guard !top.isEmpty else { return capped("No app use recorded \(range.inPhrase).") }
        let apps = top.prefix(5).map { "\($0.name) \(DurationText.compact($0.total))" }
        return capped("Most-used apps \(range.inPhrase): \(apps.joined(separator: ", "))."
                      + (phrase.map { " Busiest hours: \($0)." } ?? ""))
    }

    /// The up to three clock hours with the most time, each at least a
    /// minute, most first and the earlier hour on a tie; nil with none. Each
    /// hour is a span with its duration, so a clock time never stands bare
    /// beside one. `hours` has an entry for each hour of the day, from 0.
    static func hoursPhrase(_ hours: [TimeInterval]) -> String? {
        let top = hours.enumerated().filter { $0.element >= 60 }
            .sorted { $0.element == $1.element ? $0.offset < $1.offset : $0.element > $1.element }
            .prefix(3)
        // Any ordinary day carries the hour; the label reads only its clock hour.
        let day = Date(timeIntervalSinceReferenceDate: 43_200)
        func label(_ hour: Int) -> String {
            DateFormats.hourLabel(Calendar.current.date(bySettingHour: hour % 24, minute: 0, second: 0, of: day) ?? day)
        }
        let spans = top.map { "from \(label($0.offset)) to \(label($0.offset + 1)) (\(DurationText.compact($0.element)))" }
        switch spans.count {
        case 0: return nil
        case 1: return spans[0]
        case 2: return "\(spans[0]), then \(spans[1])"
        default: return "\(spans[0]), then \(spans[1]) and \(spans[2])"
        }
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

    /// What a lookup says once an answer has made all the lookups it may.
    static let lookupLimitReached = "Lookup limit reached for this question. Answer from what the earlier lookups returned."

    /// What the gate says when a model names a lookup there is none of.
    static func unknownLookup(_ name: String) -> String { "No lookup called “\(name)”." }

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
