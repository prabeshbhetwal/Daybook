import Foundation

extension SessionStore {
    /// Something a relaunch would lose: a note being written, the away
    /// question being answered, an automatic session being named. An update's
    /// countdown waits for it rather than restart the app under the reader.
    var holdsUnsavedWork: Bool {
        !sessionNoteDrafts.isEmpty || !expandedNoteEditorIDs.isEmpty
            || hasUnresolvedAwayDecision || isNamingAutomaticSession
    }
}
