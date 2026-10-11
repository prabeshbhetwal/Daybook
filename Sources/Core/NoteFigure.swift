import Foundation

/// A quantity a note or its facts state, typed by what it measures so that
/// "9h" is not "9:13": the audit compares what a figure means, never its
/// digits. A `Set` of them is one mention that reads more than one way.
struct NoteFigure: Hashable, CustomStringConvertible {
    enum Kind: String, Hashable {
        /// Seconds, however written: "1h 30m", "90 minutes", "one hour thirty minutes".
        case duration
        /// Minute of the day, 0...1439: "9:13 am", "21:13".
        case clock
        /// Month times 100 plus day: "14 November", "Tuesday 6 October 2026".
        case date
        /// "2026", a four-digit number in 1900...2100.
        case year
        /// A number of a thing counted, with the thing: "3 sessions", "two days".
        case count
        case percent
        /// Any other number: a session name's digits, "3 of 7".
        case bare
    }

    let kind: Kind
    let value: Double
    var noun = ""

    var description: String {
        let shown = value == value.rounded() ? String(Int(value)) : String(value)
        return "\(kind.rawValue) \(shown)" + (noun.isEmpty ? "" : " \(noun)")
    }

    // MARK: - Vocabulary

    static let units: [String: Double] = [
        "h": 3_600, "hr": 3_600, "hrs": 3_600, "hour": 3_600, "hours": 3_600,
        "m": 60, "min": 60, "mins": 60, "minute": 60, "minutes": 60,
        "s": 1, "sec": 1, "secs": 1, "second": 1, "seconds": 1,
    ]
    /// What is counted, as its singular.
    static let nouns: [String: String] = [
        "session": "session", "sessions": "session", "day": "day", "days": "day", "week": "week", "weeks": "week",
        "month": "month", "months": "month", "stretch": "stretch", "stretches": "stretch",
    ]
    /// The words after which a lone "one" is a number and not a pronoun. The
    /// one-letter units are left out: "one's" must not read as one second.
    static let counted: Set<String> = Set(units.keys.filter { $0.count > 3 }).union(nouns.keys).union(["percent", "%"])
    private static let months = ["jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3, "apr": 4,
                                 "april": 4, "may": 5, "jun": 6, "june": 6, "jul": 7, "july": 7, "aug": 8,
                                 "august": 8, "sep": 9, "sept": 9, "september": 9, "oct": 10, "october": 10,
                                 "nov": 11, "november": 11, "dec": 12, "december": 12]
    private static let ordinals: Set<String> = ["st", "nd", "rd", "th"]

    // MARK: - Reading

    /// Every figure in `text`, one set per mention. A time with no am or pm
    /// ("09:13") reads both ways; the rest read one way.
    static func read(_ text: String) -> [Set<NoteFigure>] {
        let pieces = NotePiece.pieces(in: text)
        var mentions: [Set<NoteFigure>] = []
        var i = 0
        while i < pieces.count {
            switch pieces[i].body {
            case .word:
                i += 1
            case .clock(let hour, let minute):
                let half = meridiem(pieces, i + 1)
                mentions.append(clock(hour, minute, half))
                i += half == nil ? 1 : 2
            case .number(let value):
                let (found, used) = number(value, at: i, in: pieces)
                mentions += found
                i += used
            }
        }
        return mentions
    }

    /// 0 for am, 12 for pm, when a piece is one of them just after a time.
    private static func meridiem(_ pieces: [NotePiece], _ k: Int) -> Int? {
        guard k < pieces.count, let word = pieces[k].word, joins(pieces[k].gap) else { return nil }
        return word == "am" ? 0 : word == "pm" ? 12 : nil
    }

    private static func clock(_ hour: Int, _ minute: Int, _ half: Int?) -> Set<NoteFigure> {
        func at(_ hour: Int) -> NoteFigure { NoteFigure(kind: .clock, value: Double(hour * 60 + minute)) }
        if let half { return [at(hour % 12 + half)] }
        return (1...12).contains(hour) ? [at(hour % 12), at(hour % 12 + 12)] : [at(hour)]
    }

    /// A number and what it is the number of, with how many pieces that took.
    private static func number(_ value: Double, at i: Int, in pieces: [NotePiece]) -> ([Set<NoteFigure>], Int) {
        func figure(_ kind: Kind, _ value: Double, _ noun: String = "") -> [Set<NoteFigure>] {
            [[NoteFigure(kind: kind, value: value, noun: noun)]]
        }
        func word(_ k: Int) -> String? { k < pieces.count ? pieces[k].word : nil }
        let whole = value == value.rounded() ? Int(exactly: value) : nil

        if let hour = whole, (1...12).contains(hour), let half = meridiem(pieces, i + 1) {
            return ([clock(hour, 0, half)], 2)
        }
        if let unit = word(i + 1).flatMap({ units[$0] }), joins(pieces[i + 1].gap) {
            var seconds = value * unit
            var next = i + 2
            var smallest = unit
            while let (more, end, size) = anotherTerm(pieces, next, below: smallest) {
                seconds += more
                next = end
                smallest = size
            }
            return (figure(.duration, seconds.rounded()), next - i)
        }
        if word(i + 1) == "%" && pieces[i + 1].gap.isEmpty || word(i + 1) == "percent" && joins(pieces[i + 1].gap) {
            return (figure(.percent, value), 2)
        }
        // "6th": the ending is part of the number.
        let ordinal = word(i + 1).map { ordinals.contains($0) && pieces[i + 1].gap.isEmpty } ?? false
        let after = i + (ordinal ? 2 : 1)
        if let day = whole, (1...31).contains(day) {
            // "6 October", "6th October", "6th of October".
            var month = after
            if word(month) == "of", joins(pieces[month].gap) { month += 1 }
            if let number = word(month).flatMap({ months[$0] }), joins(pieces[month].gap) {
                return (figure(.date, Double(number * 100 + day)), month + 1 - i)
            }
        }
        if !ordinal, let noun = word(after).flatMap({ nouns[$0] }), joins(pieces[after].gap) {
            return (figure(.count, value, noun), 2)
        }
        let kind: Kind = whole.map { (1900...2100).contains($0) } == true ? .year : .bare
        return (figure(kind, value), after - i)
    }

    /// Another `number unit` that carries on a duration with a smaller unit
    /// than `below`: "1h 30m", "1 hour and 30 minutes", "1 hour, 30
    /// minutes", "1h30m". Its seconds, the index after it and its unit.
    private static func anotherTerm(_ pieces: [NotePiece], _ j: Int,
                                    below: Double) -> (TimeInterval, Int, Double)? {
        var k = j
        func apart(_ gap: String) -> Bool { gap.allSatisfy { $0 == " " || $0 == "," } }
        if k < pieces.count, pieces[k].word == "and", apart(pieces[k].gap) { k += 1 }
        guard k + 1 < pieces.count, case .number(let value) = pieces[k].body,
              let unit = pieces[k + 1].word.flatMap({ units[$0] }), unit < below, joins(pieces[k + 1].gap),
              k == j ? apart(pieces[k].gap) : pieces[k].gap == " " else { return nil }
        return (value * unit, k + 2, unit)
    }

    /// Whether a number and the word naming it touch, or only a space or a hyphen lies between.
    private static func joins(_ gap: String) -> Bool { gap.isEmpty || gap == " " || gap == "-" }
}
