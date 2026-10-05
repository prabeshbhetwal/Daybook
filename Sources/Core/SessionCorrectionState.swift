import Foundation

/// Store-owned bookkeeping for one correction and its reversible field values.
/// It deliberately carries IDs and fields, never an archive replacement.
struct SessionStoreCorrectionState: Codable, Identifiable, Equatable {
    var id = UUID()
    var sequence = 0
    struct ActiveFields: Codable, Equatable {
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
    /// For `.removed`: the records taken out, whole, so Undo restores them
    /// as they were. Nil on every other correction and on older journals.
    var removedRecords: [SessionRecord]? = nil

    /// The span the correction concerns when its records are no longer in
    /// the archive to say so.
    var removedRange: DateInterval? {
        guard let records = removedRecords, let first = records.map(\.start).min(),
              let last = records.map(\.end).max(), last > first else { return nil }
        return DateInterval(start: first, end: last)
    }
}
