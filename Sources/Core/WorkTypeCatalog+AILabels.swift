import Foundation

extension AILabel {
    /// The label as the catalogue sees it: hidden. It resolves by id, so a record carrying it shows its name
    /// and symbol, but it is not active, not startable, in no picker, not offered to the model and not in
    /// Settings (C10), and it is never encoded into the person's categories.
    var hiddenDefinition: WorkTypeDefinition {
        WorkTypeDefinition(id: id, name: name, symbolName: symbolName, hue: hue,
                           countsTowardFocus: countsTowardFocus, isUnkeptAILabel: true)
    }
}

extension WorkTypeCatalog {
    /// What a category's name is checked against (`nameProblem`) wherever the person names one: every category,
    /// Unsorted, and the AI labels given, so no two of them read alike.
    static func namedDefinitions(besides labels: [AILabel]) -> [WorkTypeDefinition] {
        shared.allDefinitions + [unsortedDefinition] + labels.map(\.hiddenDefinition)
    }
}
