import Foundation

/// One cell of a session cut for phases. A nil activity has no key and takes a neighbour's.
struct PhaseCell {
    let start: Date
    let end: Date
    let activity: PhaseActivity?
    let counted: Bool
    let credited: [String: TimeInterval]
}

extension ActivityDerivation {
    static let cellLength: TimeInterval = 60

    /// `bounds` cut into 60-second cells. A cell mostly counted takes the purpose with most
    /// credited seconds in it, or no key when nothing in it is credited to a purpose (3b inside
    /// the grace). A cell mostly uncounted takes the holder's purpose when it lies mostly in a
    /// watching pause (from where the engine started it, `ActivityCredit.watchPauses`), else away.
    static func cells(_ slices: [CreditedSlice], input: DerivationInput) -> [PhaseCell] {
        let watching = ActivityCredit.watchPauses(ActivityCredit.ordered(input.credit.beats),
                                                  counted: input.credit.counted,
                                                  overrides: input.credit.purposeOverrides,
                                                  signals: input.credit.signals)
        var cells: [PhaseCell] = []
        var start = input.bounds.start
        while start < input.bounds.end {
            let cell = DateInterval(start: start, end: min(start.addingTimeInterval(cellLength), input.bounds.end))
            let half = cell.duration / 2
            // `seen` names the cell, the Agent lane included; `credited` is the person's alone.
            var credited: [AppPurpose: TimeInterval] = [:], seen: [AppPurpose: TimeInterval] = [:]
            for slice in slices where slice.end > cell.start && slice.start < cell.end {
                guard let purpose = slice.purpose else { continue }
                seen[purpose, default: 0] += overlap(cell, slice.start, slice.end)
                if slice.state != .agent { credited[purpose, default: 0] += overlap(cell, slice.start, slice.end) }
            }
            let counted = input.credit.counted.reduce(0) { $0 + overlap(cell, $1.start, $1.end) } > half
            let activity: PhaseActivity?
            if counted {
                activity = top(seen).map(PhaseActivity.purpose)
            } else {
                let held = watching.map { (seconds: overlap(cell, $0.span.start, $0.span.end), purpose: $0.purpose) }
                let mostly = held.reduce(0) { $0 + $1.seconds } > half
                let holder = held.max { $0.seconds < $1.seconds }?.purpose
                activity = mostly ? holder.map(PhaseActivity.purpose) ?? .away : .away
            }
            cells.append(PhaseCell(start: cell.start, end: cell.end, activity: activity, counted: counted,
                                   credited: raw(credited)))
            start = cell.end
        }
        return cells
    }

    private static func overlap(_ cell: DateInterval, _ start: Date, _ end: Date) -> TimeInterval {
        max(0, min(cell.end, end).timeIntervalSince(max(cell.start, start)))
    }

    /// Run-length the cells' keys, then repeatedly merge the shortest run under `minPhase`
    /// into its longer neighbour (ties: the earlier, for both), until none is under it, one
    /// run is left or no legal merge remains. Counted and uncounted runs never merge, so a
    /// short uncounted run between counted ones stays as it is.
    internal static func phases(cells: [PhaseCell]) -> [SessionPhase] {
        // A cell with no key takes its earlier neighbour's; leading ones take the first key after them.
        var keys = cells.map(\.activity)
        for index in keys.indices.dropFirst() where keys[index] == nil { keys[index] = keys[index - 1] }
        let fallback = keys.compactMap { $0 }.first ?? .browsing
        var runs: [SessionPhase] = []
        for (cell, key) in zip(cells, keys) {
            let next = SessionPhase(start: cell.start, end: cell.end, activity: key ?? fallback,
                                    counted: cell.counted, credited: cell.credited)
            if let last = runs.last, last.activity == next.activity, last.counted == next.counted {
                runs[runs.count - 1] = joined(last, next)
            } else {
                runs.append(next)
            }
        }

        while runs.count > 1 {
            var pick: (index: Int, into: Int)?
            for index in runs.indices where length(runs[index]) < ActivityConstants.minPhase {
                let legal = [index - 1, index + 1].filter {
                    runs.indices.contains($0) && runs[$0].counted == runs[index].counted
                }
                guard var into = legal.first else { continue }
                if legal.count == 2, length(runs[legal[1]]) > length(runs[legal[0]]) { into = legal[1] }
                if pick.map({ length(runs[index]) < length(runs[$0.index]) }) ?? true { pick = (index, into) }
            }
            guard let chosen = pick else { break }
            runs[chosen.into] = joined(runs[chosen.into], runs[chosen.index])
            runs.remove(at: chosen.index)
            var merged: [SessionPhase] = []
            for run in runs {
                if let last = merged.last, last.activity == run.activity, last.counted == run.counted {
                    merged[merged.count - 1] = joined(last, run)
                } else {
                    merged.append(run)
                }
            }
            runs = merged
        }
        return runs
    }

    private static func length(_ phase: SessionPhase) -> TimeInterval { phase.end.timeIntervalSince(phase.start) }

    /// Both spans and credit, under the first's activity and counted flag.
    private static func joined(_ kept: SessionPhase, _ other: SessionPhase) -> SessionPhase {
        SessionPhase(start: min(kept.start, other.start), end: max(kept.end, other.end), activity: kept.activity,
                     counted: kept.counted, credited: kept.credited.merging(other.credited, uniquingKeysWith: +))
    }
}
