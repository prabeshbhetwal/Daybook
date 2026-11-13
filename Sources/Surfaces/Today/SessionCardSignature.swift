import SwiftUI

/// Everything a session card in the day timeline shows, as plain values.
///
/// The day column watches the whole store, which publishes every second while
/// a session runs. Without this, each of those seconds rebuilt every card in
/// view; with it, a card whose signature has not changed is not rebuilt, and
/// only the running one, whose worked time and clock change, is.
///
/// A new thing the card shows must be added here, or the card will not redraw
/// when it changes. That includes anything the card reads from the store
/// itself rather than from its arguments (the notes, below).
struct SessionCardSignature: Equatable {
    var session: DaySession
    var apps: [AppRank]
    var shape: String?
    var shapeCaption: String?
    var activity: RecordedActivity?
    var canContinue: Bool
    var canStartNewSession: Bool
    var isOpen: Bool
    var clock: String?
    var liveStatus: String?
    var power: PowerContextSummary?
    var recordIDs: [UUID]
    /// Read by the card from the store: each stretch's note, whether its
    /// editor is open, and the power metadata error.
    var notes: [String?]
    var editorsOpen: [Bool]
    var metadataError: String?
    var isHistory: Bool
    var canRemove: Bool
    var removeBlockReason: String?
    var pauseTitle: String
    var canControl: Bool
    var minimumRecorded: TimeInterval

    /// The store-side reads, taken once for the card's stretches.
    static func noteFacts(of recordIDs: [UUID], in store: SessionStore)
        -> (notes: [String?], editorsOpen: [Bool], error: String?) {
        (recordIDs.map { store.sessionMetadata(for: $0)?.note },
         recordIDs.map { store.expandedNoteEditorIDs.contains($0) },
         store.powerMetadataError(for: recordIDs))
    }
}

/// A session card that is rebuilt only when its signature changes. The
/// closures the card carries act on the same store and session whatever the
/// moment, so a card that is not rebuilt acts exactly as a rebuilt one would.
struct StableSessionCard: View, Equatable {
    let signature: SessionCardSignature
    let card: () -> SessionEntryCard

    static func == (lhs: StableSessionCard, rhs: StableSessionCard) -> Bool {
        lhs.signature == rhs.signature
    }

    var body: some View { card() }
}
