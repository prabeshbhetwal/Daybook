import Foundation

/// What the on-device model chose for a session with no name.
enum NameChoice: Equatable {
    /// One of the offered earlier names, numbered from 1.
    case earlier(Int)
    /// A name the model worded itself.
    case fresh(String)
    case none
}

/// Checks the model's choice before anything is shown: an earlier name comes
/// back as the exact text offered, a fresh one only when it looks like a name
/// a person would type.
enum NameAudit {
    static let maxWords = 4, maxCharacters = 30

    private static let quotes = CharacterSet(charactersIn: "\"'`“”„«»‘’‚‹›")

    /// 1 to `maxWords` words, at most `maxCharacters` characters, no digits or
    /// quote marks, and neither a category's name nor exactly an app's name.
    static func accepts(_ name: String, categories: [WorkType], appNames: [String]) -> Bool {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = text.split(whereSeparator: \.isWhitespace).count
        guard (1...maxWords).contains(words), text.count <= maxCharacters,
              !text.contains(where: \.isNumber),
              text.rangeOfCharacter(from: quotes) == nil else { return false }
        let key = SearchWords.fold(text)
        return !categories.contains { SearchWords.fold($0.displayName) == key }
            && !appNames.contains { SearchWords.fold($0) == key }
    }

    /// The name to offer, or nil. A fresh name that equals an earlier one,
    /// ignoring case and accents, takes the earlier spelling.
    static func resolve(_ choice: NameChoice, candidates: [NameCandidate], earlierNames: [String],
                        categories: [WorkType], appNames: [String]) -> String? {
        switch choice {
        case .earlier(let number):
            return candidates.indices.contains(number - 1) ? candidates[number - 1].name : nil
        case .fresh(let name):
            guard accepts(name, categories: categories, appNames: appNames) else { return nil }
            let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = SearchWords.fold(text)
            return earlierNames.first { SearchWords.fold($0) == key } ?? text
        case .none:
            return nil
        }
    }
}
