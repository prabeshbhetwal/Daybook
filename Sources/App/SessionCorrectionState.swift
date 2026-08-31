import Foundation

/// Store-owned bookkeeping for one correction and its reversible field values.
/// It deliberately carries IDs and fields, never an archive replacement.
struct SessionStoreCorrectionState {
    struct ActiveFields {
        let name: String
        let workType: WorkType
    }

    let threadID: UUID
    let correction: SessionCorrection
    let archiveSnapshot: SessionArchiveCorrectionSnapshot?
    /// The thread value before correction, including for archive-only edits.
    /// A later continuation inherits the corrected value, so Undo needs this
    /// independently of whether a stretch was active when Save was pressed.
    let originalFields: ActiveFields
    /// IDs already present when correction was made. Later continuations are
    /// restored through the same atomic archive candidate without changing
    /// evidence that pre-dated the correction.
    let archiveRecordIDs: Set<UUID>
}

enum SessionCorrectionRetry {
    case correction(threadID: UUID, correction: SessionCorrection)
    case undo(SessionStoreCorrectionState)
    case awayUndo(UUID)
    case awayDecision(UserDecision, label: String?, reviewing: Bool, expectedID: UUID)
}
