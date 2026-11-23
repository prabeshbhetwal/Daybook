import Foundation

/// What Save does in the session editor. A category pick applies at once, so
/// Save with the name untouched (or cleared) only closes the editor.
enum RenameSaveAction: Equatable {
    case close
    case rename(String)

    static func resolve(draft: String, current: String) -> RenameSaveAction {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == current ? .close : .rename(trimmed)
    }
}
