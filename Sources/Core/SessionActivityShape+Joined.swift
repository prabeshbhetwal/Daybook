import Foundation

extension SessionActivityShape {
    /// The shapes stored for a session's records, which run one after another, read as the one session.
    /// Time, credit and phases add up and the label follows the summed credit; depth and the
    /// fingerprint belong to one run of evidence, so a join of several has neither. One shape is itself.
    static func joined(_ parts: [SessionActivityShape]) -> SessionActivityShape? {
        guard let first = parts.first else { return nil }
        guard parts.count > 1 else { return first }
        var credited: [String: TimeInterval] = [:]
        for part in parts { credited.merge(part.credited, uniquingKeysWith: +) }
        return SessionActivityShape(
            algorithmVersion: parts.map(\.algorithmVersion).min() ?? first.algorithmVersion,
            fidelity: parts.allSatisfy { $0.fidelity == .beats } ? .beats : .appsOnly,
            bounds: DateInterval(start: parts.map(\.bounds.start).min() ?? first.bounds.start,
                                 end: parts.map(\.bounds.end).max() ?? first.bounds.end),
            countedSeconds: parts.reduce(0) { $0 + $1.countedSeconds },
            signals: Set(parts.flatMap(\.signals)).sorted { $0.rawValue < $1.rawValue },
            phases: parts.flatMap(\.phases).sorted { $0.start < $1.start },
            depth: nil, label: label(of: credited), credited: credited, fingerprint: nil,
            splitCandidates: parts.flatMap(\.splitCandidates).sorted())
    }

    /// The part of the shape inside `row`: a session over midnight is a row on each day, and once its beats
    /// have expired each takes its own part of the one shape kept. Phases are cut to the row and a phase
    /// cut short keeps its credit in proportion to the time kept; the label follows what is left, and
    /// depth and the fingerprint, which are of the whole run, are dropped. A row that holds the whole shape gets it.
    func clipped(to row: DateInterval) -> SessionActivityShape {
        guard bounds.start < row.start || bounds.end > row.end else { return self }
        var credited: [String: TimeInterval] = [:]
        var kept: [SessionPhase] = []
        for phase in phases {
            let start = max(phase.start, row.start), end = min(phase.end, row.end)
            guard end > start else { continue }
            let share = end.timeIntervalSince(start) / phase.end.timeIntervalSince(phase.start)
            let part = phase.credited.mapValues { $0 * share }
            credited.merge(part, uniquingKeysWith: +)
            kept.append(SessionPhase(start: start, end: end, activity: phase.activity, counted: phase.counted, credited: part))
        }
        let start = max(bounds.start, row.start)
        return SessionActivityShape(
            algorithmVersion: algorithmVersion, fidelity: fidelity,
            bounds: DateInterval(start: start, end: max(start, min(bounds.end, row.end))),
            countedSeconds: kept.filter(\.counted).reduce(0) { $0 + $1.end.timeIntervalSince($1.start) },
            signals: signals, phases: kept, depth: nil, label: Self.label(of: credited), credited: credited,
            fingerprint: nil, splitCandidates: splitCandidates.filter { row.contains($0) })
    }

    /// The purpose with most credited seconds, `.unsorted` under `minCreditedSeconds`.
    private static func label(of credited: [String: TimeInterval]) -> ActivityLabel {
        let purposes = Dictionary(uniqueKeysWithValues: credited.compactMap { key, seconds in
            AppPurpose(rawValue: key).map { ($0, seconds) }
        })
        guard purposes.values.reduce(0, +) >= ActivityConstants.minCreditedSeconds,
              let leader = ActivityDerivation.top(purposes) else { return .unsorted }
        return .activity(leader)
    }
}
