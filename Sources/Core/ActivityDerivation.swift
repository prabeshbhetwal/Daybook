import Foundation

/// A session's derived view from its beats (spec sections 2 to 4): credited seconds,
/// label, depth over the working set, split candidates, phases and a fingerprint.
/// Pure. A run is the whole session in this phase; cutting runs at split candidates is phase B.
enum ActivityDerivation {
    static func derive(_ input: DerivationInput) -> SessionActivityShape {
        let slices = ActivityCredit.credit(input.credit)
        let credited = purposeSeconds(slices)
        let named = label(credited, input: input)
        let walked = ActivityWorkingSet.walk(slices, beats: input.credit.beats,
                                             countsWhileWatching: input.countsWhileWatching)
        // A departure with no return splits once its window has closed, or the session has ended.
        let splits = walked.departures.filter {
            !$0.returned && (!input.isRunning || input.now.timeIntervalSince($0.at) >= ActivityConstants.returnWindow)
        }.map(\.at)
        return SessionActivityShape(
            algorithmVersion: ActivityConstants.algorithmVersion, fidelity: .beats, bounds: input.bounds,
            countedSeconds: input.credit.counted.reduce(0) { $0 + $1.duration },
            signals: input.credit.signals.sorted { $0.rawValue < $1.rawValue },
            phases: phases(cells: cells(slices, input: input)),
            // A split means the session held more than one piece of work, and one depth would describe neither.
            depth: named == .unsorted || !splits.isEmpty ? nil : depth(slices, members: walked.members,
                                                                       countsWhileWatching: input.countsWhileWatching),
            label: named, credited: raw(credited), fingerprint: fingerprint(slices, credited),
            splitCandidates: splits, countsWhileWatching: input.countsWhileWatching,
            overridesDigest: SessionActivityShape.digest(input.credit.purposeOverrides))
    }

    /// Whether beats lie over all of the counted time but less than a phase (`minPhase`): the last open
    /// beat, a tick or two lost. Recording switched on partway leaves counted time no beat saw, and a cell
    /// there would take its neighbour's purpose, so such a session is read from its apps instead.
    static func recordsWhole(_ counted: [DateInterval], beats: [Beat]) -> Bool {
        let seen = beats.map { DateInterval(start: $0.start.addingTimeInterval(TimeInterval($0.offset)),
                                            end: max($0.start.addingTimeInterval(TimeInterval($0.offset)), $0.end)) }
            .sorted { $0.start < $1.start }
        var unseen: TimeInterval = 0
        for span in counted {
            var cursor = span.start
            for beat in seen where beat.end > cursor && beat.start < span.end {
                unseen += max(0, beat.start.timeIntervalSince(cursor))
                cursor = beat.end
            }
            unseen += max(0, span.end.timeIntervalSince(cursor))
        }
        return unseen <= ActivityConstants.minPhase
    }

    /// Seconds credited to each purpose; a slice credited to nothing is left out.
    static func purposeSeconds(_ slices: [CreditedSlice]) -> [AppPurpose: TimeInterval] {
        var seconds: [AppPurpose: TimeInterval] = [:]
        for slice in slices {
            if let purpose = slice.purpose { seconds[purpose, default: 0] += slice.end.timeIntervalSince(slice.start) }
        }
        return seconds
    }

    /// The purpose with most seconds; a tie goes to the earlier in `AppPurpose.allCases`.
    static func top(_ seconds: [AppPurpose: TimeInterval]) -> AppPurpose? {
        var best: AppPurpose?
        for purpose in AppPurpose.allCases where (seconds[purpose] ?? 0) > (best.flatMap { seconds[$0] } ?? 0) {
            best = purpose
        }
        return best
    }

    static func raw(_ seconds: [AppPurpose: TimeInterval]) -> [String: TimeInterval] {
        Dictionary(uniqueKeysWithValues: seconds.map { ($0.key.rawValue, $0.value) })
    }

    /// `.unsorted` under `minCreditedSeconds`, else the top purpose. With a weak signal on
    /// (phase D's site kind), the credit is worked out again without it, and a different top
    /// purpose gives `.mixed`. With no beat carrying a site the signal is off and that second pass does not run.
    static func label(_ credited: [AppPurpose: TimeInterval], input: DerivationInput) -> ActivityLabel {
        guard credited.values.reduce(0, +) >= ActivityConstants.minCreditedSeconds,
              let leader = top(credited) else { return .unsorted }
        let weak: Set<SignalKind> = [.siteKind]
        let credit = input.credit
        guard !credit.signals.isDisjoint(with: weak) else { return .activity(leader) }
        let without = CreditInput(beats: credit.beats, counted: credit.counted,
                                  signals: credit.signals.subtracting(weak), purposeOverrides: credit.purposeOverrides)
        return top(purposeSeconds(ActivityCredit.credit(without))) == leader ? .activity(leader) : .mixed
    }

    /// Passive when held and passive seconds pass half of credited (held left out when watching
    /// is the work); deep when the credited run lasts `deepMinRun` with enough inside and little
    /// outside; else light. Inside: engaged or quiet-kept on a member, and every held second when
    /// watching is the work.
    static func depth(_ slices: [CreditedSlice], members: Set<String>, countsWhileWatching: Bool) -> SessionDepth {
        var credited: TimeInterval = 0, watched: TimeInterval = 0, inside: TimeInterval = 0
        for slice in slices where slice.purpose != nil {
            let seconds = slice.end.timeIntervalSince(slice.start)
            credited += seconds
            switch slice.state {
            case .held where countsWhileWatching: inside += seconds
            case .held, .passive: watched += seconds
            // A leisure site is outside even on a member: social browsing is not deep work.
            case .engaged, .quietKept: if members.contains(slice.app) && slice.site?.isLeisure != true { inside += seconds }
            }
        }
        if watched > credited / 2 { return .passive }
        let deep = credited >= ActivityConstants.deepMinRun
            && inside >= ActivityConstants.deepInsideShare * credited
            && credited - inside < ActivityConstants.deepOutsideShare * credited
        return deep ? .deep : .light
    }

    static func fingerprint(_ slices: [CreditedSlice], _ credited: [AppPurpose: TimeInterval]) -> ActivityFingerprint {
        let total = credited.values.reduce(0, +)
        // The small epsilon keeps a share like 0.6 in its 20% step despite binary rounding.
        let shares = AppPurpose.allCases.map { purpose -> Int in
            total > 0 ? min(5, Int(((credited[purpose] ?? 0) / total * 5 + 1e-9).rounded(.down))) : 0
        }
        var byApp: [String: TimeInterval] = [:]
        for slice in slices where slice.purpose != nil {
            byApp[slice.app, default: 0] += slice.end.timeIntervalSince(slice.start)
        }
        let ranked = byApp.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
        return ActivityFingerprint(shares: shares, topApps: Array((ranked + ["", ""]).prefix(2)), siteKind: siteKind(slices))
    }
}
