import Foundation

/// Rejects a note that states a figure its facts do not hold.
enum NoteAudit {
    /// The maximal runs of ASCII digits in `text`, leading zeros trimmed
    /// ("05" is "5"; "0" stays), so "09:13" and "9:13" name the same figures.
    static func digitRuns(in text: String) -> Set<String> {
        var runs: Set<String> = []
        var run = ""
        func close() {
            guard !run.isEmpty else { return }
            let trimmed = run.drop { $0 == "0" }
            runs.insert(trimmed.isEmpty ? "0" : String(trimmed))
            run = ""
        }
        for scalar in text.unicodeScalars {
            if scalar.value >= 0x30, scalar.value <= 0x39 {
                run.unicodeScalars.append(scalar)
            } else {
                close()
            }
        }
        close()
        return runs
    }

    private static let units = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
                                "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen",
                                "eighteen", "nineteen"]
    private static let tens = ["twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]

    /// The numbers `text` writes in words, as digit runs: "forty-six" is "46"
    /// and "two thousand twenty-six" is "2026". The live probe found the model
    /// writing most of a week's or month's figures this way.
    // ponytail: a lone "one" is skipped (it is a pronoun too), "and" ends a figure ("one hundred and five" reads
    // as 100 and 5), and "half", "dozen" and ordinals are not read; widen if the probe finds them stating a figure.
    static func wordRuns(in text: String) -> Set<String> {
        let lower = text.lowercased()
        var runs: Set<String> = []
        var total = 0, current = 0, open = false
        func close() {
            if open { runs.insert(String(total + current)) }
            total = 0; current = 0; open = false
        }
        /// Adds `word` to the figure being read; false when it cannot be part of it.
        func extend(_ word: String, next: String?) -> Bool {
            let tail = current % 100
            if let unit = units.firstIndex(of: word) {
                if word == "one", !open, next != "hundred", next != "thousand" { return false }
                guard tail == 0 || (tail >= 20 && tail % 10 == 0 && unit > 0 && unit < 10) else { return false }
                current += unit
            } else if let ten = tens.firstIndex(of: word) {
                guard tail == 0 else { return false }
                current += (ten + 2) * 10
            } else if word == "hundred" {
                guard open, (1...9).contains(current) else { return false }
                current *= 100
            } else if word == "thousand" {
                guard open, total == 0, current > 0 else { return false }
                total = current * 1_000
                current = 0
            } else {
                return false
            }
            open = true
            return true
        }
        let words = try! NSRegularExpression(pattern: "[a-z]+")
        let tokens = words.matches(in: lower, range: NSRange(lower.startIndex..., in: lower))
            .compactMap { Range($0.range, in: lower) }
        var previous: Range<String.Index>?
        for (index, range) in tokens.enumerated() {
            // Words run together only when a single space or hyphen lies between them.
            let gap = previous.map { String(lower[$0.upperBound..<range.lowerBound]) }
            if gap != " " && gap != "-" { close() }
            previous = range
            let word = String(lower[range])
            let next = index + 1 < tokens.count ? String(lower[tokens[index + 1]]) : nil
            if !extend(word, next: next) {
                close()
                _ = extend(word, next: next)
            }
        }
        close()
        return runs
    }

    /// Every figure in `text`: its digit runs and the numbers it spells out.
    static func figures(in text: String) -> Set<String> {
        digitRuns(in: text).union(wordRuns(in: text))
    }

    /// Whether every figure in the note's story, pattern and tip is also in the facts.
    static func passes(_ note: WrittenNote, facts: NoteFacts) -> Bool {
        let written = note.story + " " + note.pattern + " " + (note.tip ?? "")
        return figures(in: written).isSubset(of: figures(in: facts.text))
    }
}
