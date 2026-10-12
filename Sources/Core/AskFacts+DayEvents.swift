import Foundation

/// One thing that happened between sessions, with the clock times already
/// worded by the store (`askTime`). `to` is nil for an instant.
struct AskEventItem: Equatable {
    enum Kind: Equatable {
        /// A break; nil when it has no name of its own. `running` is one still
        /// going: it has no end, and its length is so far.
        case breakTaken(name: String?, running: Bool)
        /// An absence the user answered: what the answer did, the name of the
        /// break it recorded (the user's own words survive only there), and the
        /// time it counted as focus. The session running then is not kept, so
        /// the line cannot read as what the user said.
        case away(outcome: String, label: String?, credited: TimeInterval?)
        /// An absence not answered yet.
        case pending
        /// A stretch or event the Mac's log tells. An uncertain one (a crash)
        /// happened some time in its window, and `found` is when Daybook
        /// opened and found it.
        case mac(title: String, uncertain: Bool, found: String?)
    }

    let kind: Kind
    let from: String
    let to: String?
    let length: TimeInterval?
}

/// One day's events in time order, with the figures a longer period's line says.
struct AskEventDay: Equatable {
    let label: String
    let items: [AskEventItem]
    let breaks: Int
    let breakTime: TimeInterval
    let answers: Int
    let pending: Int
    /// What the folded "What the Mac did" card says; nil when it says nothing.
    let macSummary: String?
}

extension AskFacts {
    /// The word for a clock time at a day's own start or end, in place of 12:00am.
    static let midnight = "midnight"
    /// “to” before a clock time, “until” before midnight: `from 11:48pm until midnight`.
    static func connector(to time: String) -> String { time == midnight ? "until" : "to" }
    /// What the Mac's log did not record in a period it covers. The model read
    /// a list with no restart in it as a yes, so the silence is said. A period
    /// that begins before the log (`logFrom`, as `dayEvents` takes it) is
    /// covered only from the log's first day, and the sentence says so: the
    /// model read a bare one as covering the days before.
    static func noRestart(from logFrom: String? = nil) -> String {
        "No restart or shut down was recorded" + (logFrom.map { " from \($0) on" } ?? "") + "."
    }
    static func noCrash(from logFrom: String? = nil) -> String {
        "No crash was recorded" + (logFrom.map { " from \($0) on" } ?? "") + "."
    }

    /// `days` are newest first and are the days with something to tell;
    /// `total` is how many such days the range holds. `logFrom` is set only
    /// when the range begins before the Mac's event log does: the first day
    /// the log holds, said as `askDay` says it. `beforeLog` is whether the
    /// range ends before that day. `absences` are what the log did not record
    /// in the period (`noRestart`, `noCrash`), none when it does not cover it.
    /// One day lists its items in order; a longer range is a line a day, as
    /// many whole days as the cap holds, and says "Newest N of M days." when
    /// it cannot hold them all.
    static func dayEvents(_ range: AskRange, days: [AskEventDay], total: Int,
                          logFrom: String?, beforeLog: Bool, absences: [String]) -> String {
        let notes = [logNote(logFrom, beforeLog)].compactMap { $0 } + absences
        guard !days.isEmpty else {
            return capped("No breaks, time away or Mac events recorded \(range.inPhrase)."
                          + notes.map { " " + $0 }.joined())
        }
        if range.isOneDay {
            let day = days[0]
            let lines = day.items.map(itemLine).joined(separator: "\n")
            return capped("\(day.label):\n" + lines, keeping: notes.map { "\n" + $0 }.joined())
        }
        let shown = dayEventsShown(days, total: total, logFrom: logFrom, beforeLog: beforeLog, absences: absences)
        let parts = listTail(shown, total: total, notes: notes)
        return capped(days.prefix(shown).map(dayLine).joined(separator: "\n"), keeping: parts)
    }

    /// How many of a longer range's days the cap holds, whole, beside its notes.
    static func dayEventsShown(_ days: [AskEventDay], total: Int, logFrom: String?, beforeLog: Bool,
                               absences: [String]) -> Int {
        let notes = [logNote(logFrom, beforeLog)].compactMap { $0 } + absences
        let lines = days.map(dayLine)
        var shown = lines.count
        while shown > 1 {
            let size = lines.prefix(shown).reduce(0) { $0 + $1.utf8.count + 1 } - 1
                + listTail(shown, total: total, notes: notes).utf8.count
            if size <= maximumBytes { break }
            shown -= 1
        }
        return shown
    }

    /// `Fri 9 Oct · 2 breaks, 1h · 2 answers about time away · Locked 45m`.
    static func dayLine(_ day: AskEventDay) -> String {
        var parts = [day.label]
        if day.breaks > 0 { parts.append("\(count(day.breaks, "break")), \(DurationText.compact(day.breakTime))") }
        if day.answers > 0 { parts.append("\(count(day.answers, "answer")) about time away") }
        if day.pending > 0 { parts.append("\(count(day.pending, "absence")) not answered yet") }
        if let summary = day.macSummary { parts.append(summary) }
        if parts.count == 1 {
            // Mac stretches too short for the card's summary.
            parts.append(count(day.items.count - day.breaks - day.answers - day.pending, "Mac event"))
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// `from 12:25pm to 1:10pm · break “Lunch” · 45m`: a clock time is a
    /// start (“from”), an end (“to”, or “until” midnight) or an instant
    /// (“at”), never bare. A Mac row that is certain leads with its title,
    /// `Mac asleep from 11:48pm until midnight`: after the times, the model
    /// read “12:00am · Mac asleep” as the Mac going to sleep then.
    private static func itemLine(_ item: AskEventItem) -> String {
        var when = item.to.map { "from \(item.from) \(connector(to: $0)) \($0)" } ?? "at \(item.from)"
        if case .breakTaken(_, true) = item.kind, let length = item.length {
            when = "from \(item.from), \(DurationText.compact(length)) so far"
        }
        let what: String
        if case let .mac(title, false, _) = item.kind { return "\(title) \(when)" }
        switch item.kind {
        case let .breakTaken(name, running):
            what = "break" + (name.map { " “\($0)”" } ?? "")
                + (running ? "" : item.length.map { " \u{00B7} " + DurationText.compact($0) } ?? "")
        case let .away(outcome, label, credited):
            // Said when absent: the model invents a reason from silence.
            what = "away \u{00B7} answered: \(outcome)"
                + (credited.map { ", " + DurationText.compact($0) } ?? "")
                + (label.map { " \u{00B7} named “\($0)”" } ?? " \u{00B7} no reason recorded")
        case .pending:
            what = "away, not answered yet"
        case let .mac(title, uncertain, found):
            // As the "What the Mac did" card words it, so the span is not read as how long it lasted.
            what = title + (uncertain ? " \u{00B7} some time in this window"
                            + (found.map { "; found when Daybook opened at \($0)" } ?? "") : "")
        }
        return "\(when) \u{00B7} \(what)"
    }

    private static func logNote(_ logFrom: String?, _ beforeLog: Bool) -> String? {
        logFrom.map { beforeLog ? "No Mac events were recorded before \($0)." : "The Mac's events are recorded from \($0)." }
    }

    /// The lines kept whole after a list: the notes (the log's, what it did not record), then how many days it holds.
    private static func listTail(_ shown: Int, total: Int, notes: [String]) -> String {
        (notes + (shown < total ? ["Newest \(shown) of \(total) days."] : [])).map { "\n" + $0 }.joined()
    }
}
