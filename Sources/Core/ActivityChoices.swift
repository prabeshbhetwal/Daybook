import Foundation

/// An activity the user pinned: a name and the category it is filed under,
/// in the order they keep it. The short list of what they usually do.
struct SavedActivity: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var workType: WorkType

    init(id: UUID = UUID(), name: String, workType: WorkType) {
        self.id = id
        self.name = name
        self.workType = workType
    }

    /// The category to start with: the saved one, or Deep work when that
    /// category has since been retired. The row still shows the saved name
    /// so nothing changes silently.
    var startableWorkType: WorkType {
        WorkType.startable.contains(workType) ? workType : .deepWork
    }
}

/// Rules for the pinned list: short, one entry per name, in the user's order.
enum SavedActivities {
    static let limit = 8

    static func normalisedName(_ name: String) -> String {
        name.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    static func key(_ name: String) -> String {
        normalisedName(name).folding(options: [.caseInsensitive, .diacriticInsensitive],
                                     locale: Locale(identifier: "en_AU"))
    }

    /// Trims, drops blanks and rest, keeps the first of a repeated name, and
    /// stops at the limit.
    static func normalised(_ items: [SavedActivity]) -> [SavedActivity] {
        var seen = Set<String>()
        return items.compactMap { item -> SavedActivity? in
            let name = normalisedName(item.name)
            guard !name.isEmpty, item.workType.countsAsFocus, seen.insert(key(name)).inserted else { return nil }
            return SavedActivity(id: item.id, name: name, workType: item.workType)
        }.prefix(limit).map { $0 }
    }

    /// Recents that are not already pinned, so the menu never shows a name
    /// twice, capped so it stays a glance.
    static func recents(_ quickStarts: [QuickStart], excluding saved: [SavedActivity],
                        limit: Int = 6) -> [QuickStart] {
        let pinned = Set(saved.map { key($0.name) })
        return quickStarts.filter { !pinned.contains(key($0.name)) }.prefix(limit).map { $0 }
    }
}

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
