import Foundation

/// A note's or its facts' text cut into the pieces its figures are read from:
/// numbers (in digits, or in words like "forty-six"), clock times and words,
/// each with what lies between it and the piece before.
struct NotePiece: Equatable {
    enum Body: Equatable {
        case number(Double)
        case clock(hour: Int, minute: Int)
        case word(String)
    }

    let body: Body
    /// The characters between the previous piece and this one, "" when they
    /// touch. Any one space (a no-break one too) is " ".
    let gap: String

    var word: String? {
        if case .word(let word) = body { return word }
        return nil
    }

    /// Lower-cased. A digit run with a point inside it ("1.3") is one number;
    /// "9:13" is a clock time; letters and digits that touch ("Q4", "2h") are
    /// separate pieces; "%" is a word. Everything else is gap.
    static func pieces(in text: String) -> [NotePiece] {
        spelledOut(scan(text.lowercased()))
    }

    private static func scan(_ text: String) -> [NotePiece] {
        let chars = Array(text)
        func isDigit(_ k: Int) -> Bool { k < chars.count && chars[k] >= "0" && chars[k] <= "9" }
        func end(of run: Int, _ keep: (Int) -> Bool) -> Int {
            var j = run
            while keep(j) { j += 1 }
            return j
        }
        var pieces: [NotePiece] = []
        var gap = ""
        var i = 0
        func add(_ body: Body, _ next: Int) {
            pieces.append(NotePiece(body: body, gap: gap))
            gap = ""
            i = next
        }
        while i < chars.count {
            if isDigit(i) {
                let whole = end(of: i, isDigit)
                if whole - i <= 2, whole < chars.count, chars[whole] == ":", isDigit(whole + 1), isDigit(whole + 2),
                   !isDigit(whole + 3), let hour = Int(String(chars[i..<whole])),
                   let minute = Int(String(chars[(whole + 1)...(whole + 2)])), hour < 24, minute < 60 {
                    add(.clock(hour: hour, minute: minute), whole + 3)
                } else if whole < chars.count, chars[whole] == ".", isDigit(whole + 1) {
                    let last = end(of: whole + 1, isDigit)
                    add(.number(Double(String(chars[i..<last])) ?? 0), last)
                } else {
                    add(.number(Double(String(chars[i..<whole])) ?? 0), whole)
                }
            } else if chars[i].isLetter {
                let last = end(of: i) { $0 < chars.count && chars[$0].isLetter }
                add(.word(String(chars[i..<last])), last)
            } else if chars[i] == "%" {
                add(.word("%"), i + 1)
            } else {
                gap.append(chars[i].isWhitespace && !chars[i].isNewline ? " " : chars[i])
                i += 1
            }
        }
        return pieces
    }

    /// Runs of number words become one number piece. Words run together only
    /// across a single space or hyphen.
    private static func spelledOut(_ pieces: [NotePiece]) -> [NotePiece] {
        var out: [NotePiece] = []
        var reader = NoteNumberWords()
        var startGap = ""
        func flush() {
            if let value = reader.finish() { out.append(NotePiece(body: .number(Double(value)), gap: startGap)) }
        }
        for (index, piece) in pieces.enumerated() {
            guard let word = piece.word else {
                flush()
                out.append(piece)
                continue
            }
            if reader.isOpen, piece.gap != " ", piece.gap != "-" { flush() }
            let next = index + 1 < pieces.count ? pieces[index + 1].word : nil
            let opening = !reader.isOpen
            if reader.add(word, next: next) {
                if opening { startGap = piece.gap }
                continue
            }
            flush()
            if reader.add(word, next: next) { startGap = piece.gap } else { out.append(piece) }
        }
        flush()
        return out
    }
}
