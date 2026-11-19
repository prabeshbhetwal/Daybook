import Foundation

/// One thing a correction owes after its records are written. Each step sets a value and never adds to one, so
/// doing it again changes nothing: that is what lets it be done again, from the journal, until it is known done.
enum OwedStep: Codable, Equatable {
    /// The tail of a split names the head it was cut from (nil: it names none).
    case link(record: UUID, to: SplitLink?)
    /// The summary a record keeps once its beats expire becomes this one (nil: it keeps none).
    case summary(record: UUID, shape: SessionActivityShape?)
    /// The head's own summary, kept on the tail while the halves stand joined (nil: nothing to keep).
    case headSummary(tail: UUID, shape: SessionActivityShape?)
    /// The power readings from `atOrAfter` on go from one record to the other.
    case movePower(from: UUID, to: UUID, atOrAfter: Date)
    /// The remembered category choices that the category change made at `sequence` taught, taken back by its Undo.
    case forget(sequence: Int, filings: [RememberedFiling])

    /// The records whose sidecar entries the step reads or writes: they must outlive it.
    var recordIDs: [UUID] {
        switch self {
        case .link(let record, _), .summary(let record, _), .headSummary(let record, _): return [record]
        case .movePower(let from, let to, _): return [from, to]
        case .forget: return []
        }
    }
}

/// What a correction still owes beyond the archive, such as a split's link and its power readings, which live in
/// the sidecar, or the choice a category change taught, which lives in the remembered choices. It travels with
/// the correction's journal transaction, so a launch that finds the records written finds the work too, and the
/// store does it again and again until the journal is told it is done. A crash or a refused write between the
/// records and the rest then costs time, never the link, the readings or the forgetting.
struct OwedWork: Codable, Equatable, Identifiable {
    let id: UUID
    let steps: [OwedStep]

    init(id: UUID = UUID(), steps: [OwedStep]) {
        self.id = id
        self.steps = steps
    }

    var recordIDs: Set<UUID> { Set(steps.flatMap(\.recordIDs)) }

    private enum CodingKeys: String, CodingKey { case id, steps }

    /// Steps this build does not know, from a newer one, read as none: the work then reads as done. Failing instead
    /// would set the whole correction journal aside as unreadable, taking the receipts Undo needs with it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        steps = (try? container.decode([OwedStep].self, forKey: .steps)) ?? []
    }
}
