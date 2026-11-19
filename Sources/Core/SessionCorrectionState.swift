import Foundation

/// Store-owned bookkeeping for one correction and its reversible field values.
/// It deliberately carries IDs and fields, never an archive replacement.
struct SessionStoreCorrectionState: Codable, Identifiable, Equatable {
    var id = UUID()
    var sequence = 0
    struct ActiveFields: Codable, Equatable {
        let name: String
        let workType: WorkType
        /// What the running stretch's provenance was, so Undo puts it back. Nil
        /// in corrections made before provenance existed.
        var provenance: SessionArchiveCorrectionSnapshot.Fields.Provenance? = nil
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
    /// For a split or a merge, saved as a removal that also wrote records in: those, which Undo takes out
    /// again as it puts `removedRecords` back. Nil on every other correction and on older journals.
    var addedRecords: [SessionRecord]? = nil
    /// When the person made the correction, so its notice stands at that
    /// moment rather than at the session's start. Nil on older journals.
    var madeAt: Date? = nil
    /// For the person's own category change: what it added to the remembered choices, so Undo takes it
    /// back with the change. Nil on every other correction and on older journals.
    var remembered: [RememberedFiling]? = nil

    /// What a correction that swapped whole records was, read from how many it took out and wrote in. Nil
    /// for a rename or a category. A build from before splits reads all three as a removal and its Undo of
    /// one refuses, since the head is still there.
    enum Restructure: Equatable { case removal, split, merge }
    var restructure: Restructure? {
        guard correction == .removed else { return nil }
        switch (removedRecords?.count ?? 0, addedRecords?.count ?? 0) {
        case (1, 2): return .split
        case (2, 1): return .merge
        default: return .removal
        }
    }

    /// The span the correction concerns when its records are no longer in
    /// the archive to say so.
    var removedRange: DateInterval? {
        guard let records = removedRecords, let first = records.map(\.start).min(),
              let last = records.map(\.end).max(), last > first else { return nil }
        return DateInterval(start: first, end: last)
    }
}
