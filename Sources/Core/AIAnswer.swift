import Foundation

/// What the model's answer came to once it was checked against what exists (Phase C, ruling C28). Ids, not
/// names, so the answer survives a rename. Stored in the cache and the tally.
enum AIAnswer: Codable, Equatable {
    /// One of the person's categories.
    case pick(String)
    /// An unkept label already made.
    case label(String)
    /// A new label, with the id it will carry from here on (C25), so a kept suggestion can be told from any other.
    case proposed(id: String, name: String)
    /// Nothing fits, or what was said could not be used.
    case none

    /// The category or label the answer stands for. Nil for none.
    var id: String? {
        switch self {
        case .pick(let id), .label(let id), .proposed(let id, _): return id
        case .none: return nil
        }
    }
}

/// Turns the model's constrained reply into an answer, deciding everything the model must not: a number past
/// the list is none, a proposal that is a name already in use is a pick of that one, and a name that belongs to
/// a category the model was not offered, or that the person removed, is never proposed.
enum AIAnswerResolver {
    /// `choice` is "1" to "20", "new" or "none"; `label` is read only for "new". `offered` is the numbered
    /// list the model saw, and `unofferedNames` the names of every other category that exists (Break, Unsorted,
    /// retired ones): a name in either, or past the 20th in `offered`, is the person's already, so it is none
    /// rather than a second category of that name, even when an unkept label holds it. `unkeptLabels` is the
    /// book's labels: an archived one is not matched, so a name it held can be proposed afresh (the caller
    /// passes `liveLabels(now:)`). `newID` is asked only when a label is really proposed.
    static func resolve(choice: String, label: String, offered: [(id: String, name: String)], unofferedNames: [String],
                        unkeptLabels: [AILabel], removedNames: [String], newID: () -> String) -> AIAnswer {
        let beyond = offered.dropFirst(AILabelConstants.maxOffered).map(\.name)
        let offered = Array(offered.prefix(AILabelConstants.maxOffered))
        if choice == "new" {
            guard let name = LabelAudit.clean(label) else { return .none }
            if let same = offered.first(where: { LabelAudit.matches($0.name, name) }) { return .pick(same.id) }
            // Before the unkept labels: one that holds such a name is not reused either, or the name would be filed twice.
            if (beyond + unofferedNames + removedNames).contains(where: { LabelAudit.matches($0, name) }) { return .none }
            if let same = unkeptLabels.first(where: { !$0.archived && LabelAudit.matches($0.name, name) }) {
                return .label(same.id)
            }
            return .proposed(id: newID(), name: name)
        }
        // Digits as the model's schema writes them: "01" and "+1" are not on the list.
        guard let number = Int(choice), String(number) == choice, number >= 1, number <= offered.count else { return .none }
        return .pick(offered[number - 1].id)
    }
}
