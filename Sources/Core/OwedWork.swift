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

    /// The records whose sidecar entries the step reads or writes: they must outlive it.
    var recordIDs: [UUID] {
        switch self {
        case .link(let record, _), .summary(let record, _), .headSummary(let record, _): return [record]
        case .movePower(let from, let to, _): return [from, to]
        }
    }
}

/// What a correction still owes beyond the archive, such as a split's link and its power readings, which live in
/// the sidecar. It travels with the correction's journal transaction, so a launch that finds the records written
/// finds the work too, and the store does it again and again until the journal is told it is done. A crash or a
/// refused write between the records and the sidecar then costs time, never the link or the readings.
struct OwedWork: Codable, Equatable, Identifiable {
    var id = UUID()
    let steps: [OwedStep]

    var recordIDs: Set<UUID> { Set(steps.flatMap(\.recordIDs)) }
}
