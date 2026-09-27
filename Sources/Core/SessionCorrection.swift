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

}

/// The original values of the records touched by one saved correction. Undo
/// applies these fields back to their record IDs; it does not replace an
/// archive snapshot, so later and unrelated work remains intact.
struct SessionArchiveCorrectionSnapshot: Codable, Equatable {
    struct Fields: Codable, Equatable {
        let recordID: UUID
        let name: String
        let workType: WorkType
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
