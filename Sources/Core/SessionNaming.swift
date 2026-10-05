import Foundation

/// A session has a name (what exactly) and a category (what kind). A name
/// spelled like a category is not a name: typed as "Coding" under Deep work,
/// it read as coding everywhere except the Coding goal, which counts the
/// category alone. These keep the two from saying different things.
enum SessionNaming {
    /// The startable category a name spells, ignoring case, accents and
    /// surrounding space. Nil for any other name.
    static func category(named name: String) -> WorkType? {
        let key = SearchWords.fold(name.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !key.isEmpty else { return nil }
        return WorkType.startable.first { SearchWords.fold($0.displayName) == key }
    }

    /// What a typed name and a chosen category record: a name that spells a
    /// category files the session there and leaves it unnamed, so it is
    /// titled by its category like any other unnamed session.
    static func resolve(name: String, workType: WorkType) -> (name: String, workType: WorkType) {
        guard let named = category(named: name) else { return (name, workType) }
        return ("", named)
    }

    /// Whether a name says one category while the session is filed under
    /// another: the case the goal tile offers to tidy.
    static func contradicts(name: String, workType: WorkType) -> WorkType? {
        guard let named = category(named: name), named != workType else { return nil }
        return named
    }
}
