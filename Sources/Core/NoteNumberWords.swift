import Foundation

/// Reads a number written in words one word at a time: "forty-six" is 46 and
/// "two thousand twenty-six" is 2026. The live probe found the model writing
/// most of a week's or month's figures this way.
// ponytail: "and" ends a figure ("one hundred and five" reads as 100 and 5), and "half", "dozen" and ordinals are
// not read; widen if the probe finds them stating a figure.
struct NoteNumberWords {
    private static let units = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
                                "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen",
                                "eighteen", "nineteen"]
    private static let tens = ["twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]

    private var total = 0, current = 0
    private(set) var isOpen = false

    /// Adds `word` to the figure being read; false, with nothing changed,
    /// when it cannot be part of it. A lone "one" is a pronoun too ("no one
    /// was there"), so it counts only before "hundred" or "thousand" or a
    /// word that names what is counted (`next`).
    mutating func add(_ word: String, next: String?) -> Bool {
        let tail = current % 100
        if let unit = Self.units.firstIndex(of: word) {
            if word == "one", !isOpen, next != "hundred", next != "thousand", !NoteFigure.counted.contains(next ?? "") {
                return false
            }
            guard tail == 0 || (tail >= 20 && tail % 10 == 0 && unit > 0 && unit < 10) else { return false }
            current += unit
        } else if let ten = Self.tens.firstIndex(of: word) {
            guard tail == 0 else { return false }
            current += (ten + 2) * 10
        } else if word == "hundred" {
            guard isOpen, (1...9).contains(current) else { return false }
            current *= 100
        } else if word == "thousand" {
            guard isOpen, total == 0, current > 0 else { return false }
            total = current * 1_000
            current = 0
        } else {
            return false
        }
        isOpen = true
        return true
    }

    /// The figure read so far, or nil when no word has been added; starts over.
    mutating func finish() -> Int? {
        defer { total = 0; current = 0; isOpen = false }
        return isOpen ? total + current : nil
    }
}
