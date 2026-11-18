import Foundation

/// Phases for a session recorded before beats existed, read from foreground apps alone.
/// Records and shows only: nothing here changes what a session counts, its name or category.
extension ActivityDerivation {
    /// No input is known, so an ambiguous app (a browser) is `.browsing` and credits nothing; any
    /// other app is its purpose as if active. A stretch with no recorded app is `.away` and
    /// uncounted. Cells are the same 60 s cut as beats use, so `phases(cells:)` does the smoothing.
    /// `countedSeconds` is the session's counted spans inside `bounds`, gaps included.
    static func appsOnly(_ activity: RecordedActivity, bounds: DateInterval,
                         purposeOverrides: [String: String]) -> SessionActivityShape {
        let recorded: [(interval: DateInterval, key: PhaseActivity, purpose: AppPurpose?)] =
            activity.intervals.compactMap { item in
                guard let app = item.bundleID, item.end > item.start else { return nil }
                if ActivityCredit.isAmbiguous(app, purposeOverrides) { return (item.interval, .browsing, nil) }
                let purpose = PurposeMap.purpose(for: app, activity: .active, overrides: purposeOverrides)
                return (item.interval, .purpose(purpose), purpose)
            }

        var cells: [PhaseCell] = []
        var total: [AppPurpose: TimeInterval] = [:]
        var start = bounds.start
        while start < bounds.end {
            let cell = DateInterval(start: start, end: min(start.addingTimeInterval(cellLength), bounds.end))
            var seconds: [PhaseActivity: TimeInterval] = [:]
            var credited: [AppPurpose: TimeInterval] = [:]
            for item in recorded {
                let overlap = max(0, min(cell.end, item.interval.end).timeIntervalSince(max(cell.start, item.interval.start)))
                guard overlap > 0 else { continue }
                seconds[item.key, default: 0] += overlap
                if let purpose = item.purpose { credited[purpose, default: 0] += overlap; total[purpose, default: 0] += overlap }
            }
            let counted = seconds.values.reduce(0, +) > cell.duration / 2
            // Ties go to the earlier purpose in `AppPurpose.allCases`, browsing last.
            var leader: PhaseActivity?
            for key in AppPurpose.allCases.map(PhaseActivity.purpose) + [.browsing]
            where (seconds[key] ?? 0) > (leader.flatMap { seconds[$0] } ?? 0) { leader = key }
            cells.append(PhaseCell(start: cell.start, end: cell.end, activity: counted ? leader : .away,
                                   counted: counted, credited: raw(credited)))
            start = cell.end
        }

        let named: ActivityLabel = total.values.reduce(0, +) >= ActivityConstants.minCreditedSeconds
            ? top(total).map(ActivityLabel.activity) ?? .unsorted : .unsorted
        return SessionActivityShape(
            algorithmVersion: ActivityConstants.algorithmVersion, fidelity: .appsOnly, bounds: bounds,
            countedSeconds: activity.bounds.reduce(0) { sum, span in
                sum + max(0, min(span.end, bounds.end).timeIntervalSince(max(span.start, bounds.start)))
            },
            signals: [], phases: phases(cells: cells), depth: nil, label: named, credited: raw(total),
            fingerprint: nil, splitCandidates: [])
    }
}

private extension RecordedActivity.Interval {
    var interval: DateInterval { DateInterval(start: start, end: end) }
}
