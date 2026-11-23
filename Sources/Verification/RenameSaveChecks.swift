import Foundation

/// Guards the session editor's Save: usable after a category pick alone.
enum RenameSaveChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Save with the name unchanged or empty closes the editor; a new name renames", saveResolves),
    ]

    private static func saveResolves() -> [String] {
        var problems: [String] = []
        expect(RenameSaveAction.resolve(draft: "Coding", current: "Coding") == .close, "unchanged name should close", &problems)
        expect(RenameSaveAction.resolve(draft: "  Coding ", current: "Coding") == .close, "padded unchanged name should close", &problems)
        expect(RenameSaveAction.resolve(draft: "  ", current: "Coding") == .close, "empty name should close", &problems)
        expect(RenameSaveAction.resolve(draft: " Docs ", current: "Coding") == .rename("Docs"), "new name should rename to the trimmed text", &problems)
        return problems
    }
}
