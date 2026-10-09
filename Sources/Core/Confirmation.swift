import Foundation

/// A question the app asks before an action that Undo can reverse. The reader
/// can turn one off with its "Don't ask again" tick and back on in Settings.
/// A question about a change Undo cannot reverse is not listed: it always asks.
enum Confirmation: String, CaseIterable {
    /// Count as focus or Leave uncounted, on a recorded break.
    case changeBreak
    /// Remove, on a session card.
    case removeSession
}
