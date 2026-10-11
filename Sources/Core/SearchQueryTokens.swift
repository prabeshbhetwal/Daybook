import Foundation

/// One whitespace-separated word of a search, and where it sits in the text.
struct SearchToken {
    let range: Range<String.Index>
    /// As typed, which is what a word that stays a word is kept as.
    let text: String
    /// Without the punctuation around it, in the case typed: a name's first
    /// letter is compared by case.
    let bare: String
    /// `bare`, lowercased: what the phrase matchers read.
    let word: String
    let commaAfter: Bool
    /// Inside double quotes: never part of a phrase.
    let literal: Bool

    static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: ",;:.!?()"))
    }
}

/// A search split into words, quoted ones marked.
struct SearchTokens {
    let items: [SearchToken]

    init(_ text: String) {
        let quotes: Set<Character> = ["\"", "\u{201C}", "\u{201D}"]
        var inQuote = false
        items = text.split(whereSeparator: \.isWhitespace).map { piece in
            let opens = !inQuote && piece.first.map(quotes.contains) == true
            let literal = inQuote || opens
            if literal {
                // A quote closes on a word ending in one; a lone quote mark opens.
                inQuote = !(piece.last.map(quotes.contains) == true && (inQuote || piece.count > 1))
            }
            let bare = SearchToken.trimmed(String(piece))
            return SearchToken(range: piece.startIndex..<piece.endIndex, text: String(piece), bare: bare,
                               word: bare.lowercased(), commaAfter: piece.hasSuffix(","), literal: literal)
        }
    }

    /// The lowercased word at `i`; nil past the end or inside quotes.
    func word(_ i: Int) -> String? {
        items.indices.contains(i) && !items[i].literal ? items[i].word : nil
    }

    /// The words from `i`, `count` of them, as one space-separated string.
    func phrase(_ i: Int, _ count: Int) -> String {
        (i..<i + count).compactMap(word).joined(separator: " ")
    }

    /// A whole number from `i` of 1 to 1000: digits, number words ("twenty
    /// one", "forty-six") and, when `article` is set, "a" or "an".
    func count(_ i: Int, article: Bool = false) -> (value: Int, used: Int)? {
        guard let first = word(i) else { return nil }
        if Self.isDigits(first) { return Int(first).flatMap { (1...1_000).contains($0) ? ($0, 1) : nil } }
        if article, first == "a" || first == "an" { return (1, 1) }
        var reader = NoteNumberWords()
        var used = 0
        while let piece = word(i + used) {
            // The caller checks what follows the number, so a lone "one" is a number here.
            var trial = reader
            guard piece.split(separator: "-").allSatisfy({ trial.add(String($0), next: "hours") }) else { break }
            reader = trial
            used += 1
        }
        guard let value = reader.finish(), (1...1_000).contains(value) else { return nil }
        return (value, used)
    }

    static func isDigits(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { ("0"..."9").contains($0) }
    }
}
