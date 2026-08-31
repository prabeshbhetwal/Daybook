import Foundation

/// The two fields a person can correct after a stretch has been recorded.
/// Corrections intentionally have no timing fields: editing a label or work
/// kind must never redraw, merge, or otherwise rewrite the evidence span.
enum SessionCorrection: Codable, Equatable {
    case rename(String)
    case workType(WorkType)

    var retryDescription: String {
        switch self {
        case .rename: return "rename"
        case .workType: return "work-type correction"
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
