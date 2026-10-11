import Foundation

/// One working stretch of a session on the day listed, with its clock times
/// already worded by the store (`askTime`). `to` is nil for the stretch still
/// running. `power` is the session report's own power line, `note` the first
/// line of the stretch's note.
struct AskStretchLine: Equatable {
    let from: String
    let to: String?
    let worked: TimeInterval
    let power: String?
    let note: String?
}

/// A session on one day: its name, the day as `askDay` says it, and its stretches in time order.
struct AskSessionDetail: Equatable {
    let name: String
    let day: String
    let stretches: [AskStretchLine]
}

extension AskFacts {
    /// `sessions` are newest first, `matched` is how many sessions the range
    /// holds. One line a session, as many whole lines as the cap holds beside
    /// "Newest N of M." when they are not all listed. Empty `words` count as none.
    static func sessionDetail(_ range: AskRange, words: String?, sessions: [AskSessionDetail],
                              matched: Int) -> String {
        guard !sessions.isEmpty else {
            let none = words.map { "No sessions match “\($0)”" } ?? "No sessions recorded"
            return capped("\(none) \(range.inPhrase).")
        }
        let shown = sessionDetailShown(sessions, matched: matched)
        return capped(sessions.prefix(shown).map(sessionLine).joined(separator: "\n"),
                      keeping: detailTail(shown, matched))
    }

    /// How many of the sessions the cap holds, whole, beside the count that follows them.
    static func sessionDetailShown(_ sessions: [AskSessionDetail], matched: Int) -> Int {
        let lines = sessions.map(sessionLine)
        var shown = lines.count
        while shown > 1 {
            let size = lines.prefix(shown).reduce(0) { $0 + $1.utf8.count + 1 } - 1
                + detailTail(shown, matched).utf8.count
            if size <= maximumBytes { break }
            shown -= 1
        }
        return shown
    }

    /// `Thesis · Fri 9 Oct · 2 stretches: from 9:00am to 10:40am, 1h 40m, …; from 11:05am to …`.
    private static func sessionLine(_ session: AskSessionDetail) -> String {
        let n = session.stretches.count
        let stretches = session.stretches.map(stretchText).joined(separator: "; ")
        return "\(session.name) \u{00B7} \(session.day) \u{00B7} \(n == 1 ? "1 stretch" : "\(n) stretches"): \(stretches)"
    }

    /// A clock time is a start (“from”), an end (“to”), never bare beside a duration.
    private static func stretchText(_ stretch: AskStretchLine) -> String {
        var parts = [stretch.to.map { "from \(stretch.from) to \($0), \(DurationText.compact(stretch.worked))" }
                     ?? "running from \(stretch.from), \(DurationText.compact(stretch.worked)) so far"]
        if let power = stretch.power { parts.append(power) }
        if let note = stretch.note, !note.isEmpty { parts.append("note “\(note.prefix(80))”") }
        return parts.joined(separator: ", ")
    }

    private static func detailTail(_ shown: Int, _ matched: Int) -> String {
        shown < matched ? "\nNewest \(shown) of \(matched)." : ""
    }
}
