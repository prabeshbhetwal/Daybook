import Foundation

/// Phases for a session recorded before beats existed, read from foreground apps alone.
/// Records and shows only: nothing here changes what a session counts, its name or category.
extension ActivityDerivation {
    /// No input is known, so an ambiguous app (a browser) is `.browsing` and credits nothing; any
    /// other app is its purpose as if active. A stretch with no recorded app is `.away` and
    /// uncounted. Cells are the same 60 s cut as beats use, so `phases(cells:)` does the smoothing.
    /// `counted` is the session's counted time (its spans less trusted pauses; nil reads the spans
    /// whole): app use outside it, such as through a manual pause, credits nothing and is uncounted.
    /// `countedSeconds` is the counted time inside `bounds`, gaps included.
    static func appsOnly(_ activity: RecordedActivity, bounds: DateInterval,
                         purposeOverrides: [String: String], counted: [DateInterval]? = nil) -> SessionActivityShape {
        let spans = counted ?? activity.bounds
        let recorded: [(interval: DateInterval, key: PhaseActivity, purpose: AppPurpose?)] =
            activity.intervals.flatMap { item -> [(interval: DateInterval, key: PhaseActivity, purpose: AppPurpose?)] in
                guard let app = item.bundleID, item.end > item.start else { return [] }
                let ambiguous = ActivityCredit.isAmbiguous(app, purposeOverrides)
                let purpose = ambiguous ? nil : PurposeMap.purpose(for: app, activity: .active, overrides: purposeOverrides)
                return spans.compactMap { span in
                    let start = max(span.start, item.start), end = min(span.end, item.end)
                    guard end > start else { return nil }
                    return (DateInterval(start: start, end: end), purpose.map(PhaseActivity.purpose) ?? .browsing, purpose)
                }
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
            countedSeconds: spans.reduce(0) { sum, span in
                sum + max(0, min(span.end, bounds.end).timeIntervalSince(max(span.start, bounds.start)))
            },
            signals: [], phases: phases(cells: cells), depth: nil, label: named, credited: raw(total),
            fingerprint: nil, splitCandidates: [])
    }
}
