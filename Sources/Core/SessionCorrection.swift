import Foundation

/// What a person can correct after a stretch has been recorded: its name,
/// its category, or that it should not have been recorded at all. Field
/// corrections intentionally have no timing fields: editing a label or work
/// kind must never redraw, merge, or otherwise rewrite the evidence span.
/// Removal takes the whole thread out of the archive and keeps the records
/// in the journal, so Undo puts back exactly what was there.
enum SessionCorrection: Codable, Equatable {
    case rename(String)
    case workType(WorkType)
    case removed
    /// One record cut in two, and two cut records joined again. Like a removal they swap whole records,
    /// and the correction keeps what it took out and what it wrote in, so Undo puts it back as it was.
    case split
    case merge

    /// Corrections Undo reverses by swapping whole records instead of writing fields back.
    var restoresRecords: Bool {
        switch self {
        case .removed, .split, .merge: return true
        case .rename, .workType: return false
        }
    }
}

/// The original values of the records touched by one saved correction. Undo
/// applies these fields back to their record IDs; it does not replace an
/// archive snapshot, so later and unrelated work remains intact.
struct SessionArchiveCorrectionSnapshot: Codable, Equatable {
    struct Fields: Codable, Equatable {
        let recordID: UUID
        let name: String
        let workType: WorkType
        /// Nil in snapshots written before provenance existed, and on the
        /// stand-in fields Undo builds for a stretch added since.
        var provenance: Provenance? = nil
    }

    let threadID: UUID
    let correction: SessionCorrection
    let fields: [Fields]
}

enum SessionArchiveCorrectionResult: Equatable {
    case applied(SessionArchiveCorrectionSnapshot)
    case unchanged
    case failed(String)
}
