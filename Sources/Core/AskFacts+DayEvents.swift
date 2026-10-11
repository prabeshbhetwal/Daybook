import Foundation

/// One thing that happened between sessions, with the clock times already
/// worded by the store (`askTime`). `to` is nil for an instant.
struct AskEventItem: Equatable {
    enum Kind: Equatable {
        /// A break; nil when it has no name of its own.
        case breakTaken(name: String?)
        /// An absence the user answered: the session it was asked about,
        /// what the answer did, and the time it counted as focus, if any.
        case away(answer: String?, outcome: String?, credited: TimeInterval?)
        /// An absence not answered yet.
        case pending
        /// A stretch or event the Mac's log tells, and when Daybook found it.
        case mac(title: String, found: String?)
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
    /// `days` are newest first and are the days with something to tell;
    /// `total` is how many such days the range holds. `logFrom` is set only
    /// when the range begins before the Mac's event log does: the first day
    /// the log holds, said as `askDay` says it. `beforeLog` is whether the
    /// range ends before that day. One day lists its items in order; a longer
    /// range is a line a day, as many whole days as the cap holds, and says
    /// "Newest N of M days." when it cannot hold them all.
    static func dayEvents(_ range: AskRange, days: [AskEventDay], total: Int,
                          logFrom: String?, beforeLog: Bool) -> String {
        let note = logNote(logFrom, beforeLog)
        guard !days.isEmpty else {
            return capped("No breaks, time away or Mac events recorded \(range.inPhrase)."
                          + (note.map { " " + $0 } ?? ""))
        }
        if range.isOneDay {
            let day = days[0]
            let lines = day.items.map(itemLine).joined(separator: "\n")
            return capped("\(day.label):\n" + lines, keeping: note.map { "\n" + $0 } ?? "")
        }
        let shown = dayEventsShown(days, total: total, logFrom: logFrom, beforeLog: beforeLog)
        let parts = listTail(shown, total: total, note: note)
        return capped(days.prefix(shown).map(dayLine).joined(separator: "\n"), keeping: parts)
    }

    /// How many of a longer range's days the cap holds, whole, beside its notes.
    static func dayEventsShown(_ days: [AskEventDay], total: Int, logFrom: String?, beforeLog: Bool) -> Int {
        let note = logNote(logFrom, beforeLog)
        let lines = days.map(dayLine)
        var shown = lines.count
        while shown > 1 {
            let size = lines.prefix(shown).reduce(0) { $0 + $1.utf8.count + 1 } - 1
                + listTail(shown, total: total, note: note).utf8.count
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
    /// start (“from”), an end (“to”) or an instant (“at”), never bare.
    private static func itemLine(_ item: AskEventItem) -> String {
        let when = item.to.map { "from \(item.from) to \($0)" } ?? "at \(item.from)"
        let what: String
        switch item.kind {
        case let .breakTaken(name):
            what = "break" + (name.map { " “\($0)”" } ?? "") + (item.length.map { " \u{00B7} " + DurationText.compact($0) } ?? "")
        case let .away(answer, outcome, credited):
            what = "away \u{00B7} answered" + (answer.map { " “\($0)”" } ?? "") + (outcome.map { ": \($0)" } ?? "")
                + (credited.map { ", " + DurationText.compact($0) } ?? "")
        case .pending:
            what = "away, not answered yet"
        case let .mac(title, found):
            what = title + (found.map { " \u{00B7} found at \($0)" } ?? "")
        }
        return "\(when) \u{00B7} \(what)"
    }

    private static func logNote(_ logFrom: String?, _ beforeLog: Bool) -> String? {
        logFrom.map { beforeLog ? "No Mac events were recorded before \($0)." : "The Mac's events are recorded from \($0)." }
    }

    /// The lines kept whole after a list: the log note, then how many days it holds.
    private static func listTail(_ shown: Int, total: Int, note: String?) -> String {
        [note, shown < total ? "Newest \(shown) of \(total) days." : nil].compactMap { $0 }
            .map { "\n" + $0 }.joined()
    }
}
