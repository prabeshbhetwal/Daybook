import Foundation

extension WorkTypeCatalog {
    /// The hidden built-in a record carries when it is filed under nothing: grey, a plain question mark, never
    /// focus. The catalogue resolves it, so a record shows its name, but it joins no list and no stored
    /// entry can change it.
    static let unsortedDefinition = WorkTypeDefinition(
        id: WorkType.unsorted.rawValue, name: "Unsorted", symbolName: "questionmark.circle.fill",
        hue: .grey, countsTowardFocus: false)
}
