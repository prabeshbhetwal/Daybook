import Foundation

/// Recent names are shortcuts, not new work categories. Their last explicitly
/// chosen work type travels with the name; picking one never starts a session.
enum ActivityChoices {
    static let limit = 20

    static func merging(_ recent: [QuickStart], _ history: [QuickStart]) -> [QuickStart] {
        var seen = Set<String>()
        return (recent + history).compactMap { item -> QuickStart? in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = name.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                   locale: Locale(identifier: "en_AU"))
            guard !name.isEmpty, item.workType.countsAsFocus, seen.insert(key).inserted else { return nil }
            return QuickStart(id: key, name: name, workType: item.workType)
        }.prefix(limit).map { $0 }
    }
}
