import Foundation

/// Targets on an activity: coding, writing and AI, or design, counted in any
/// focus session whatever it is filed under, so coding inside a Deep work
/// session fills a Coding goal. Counted from each session row's credited
/// seconds (cut at midnight with the row), never from phases: a phase's
/// `counted` flag means mostly counted, and would drop or add seconds.
extension DailyGoalList {
    /// The purposes an activity target can be on, in the catalogue's order.
    static let targetablePurposes = AppPurpose.allCases.filter(\.isFocused)

    /// The activity targets that count today, by id, in the person's order.
    static func activityTargets(_ items: [DailyGoalItem]) -> [(id: UUID, purpose: AppPurpose, goal: TimeInterval)] {
        active(items).compactMap { item in
            guard case .activity(let raw) = item.target, item.kind == .target,
                  let purpose = AppPurpose(rawValue: raw), purpose.isFocused else { return nil }
            return (item.id, purpose, item.seconds)
        }
    }

    /// One session row's credit as timed slices for `focusByPurpose`: each phase that holds
    /// credit, so a paused stretch covers nothing, cut to the row's focus intervals, so a
    /// stretch filed under a category that does not count adds nothing. A phase cut short
    /// keeps the share of its credit that its remaining time holds. When the phases do not
    /// account for the row's credit (no phases, or a summary from another version), the
    /// whole row is one slice.
    static func focusSlices(credited: [String: TimeInterval], phases: [SessionPhase], span: DateInterval,
                            focus: [DateInterval]) -> [(span: DateInterval, credited: [String: TimeInterval])] {
        let total = credited.values.reduce(0, +)
        let fromPhases = phases.filter { $0.credited.values.reduce(0, +) > 0 }
        let phaseTotal = fromPhases.reduce(0) { $0 + $1.credited.values.reduce(0, +) }
        let whole: [(span: DateInterval, credited: [String: TimeInterval])] =
            !fromPhases.isEmpty && abs(phaseTotal - total) <= max(1, total * 0.01)
            ? fromPhases.map { (DateInterval(start: $0.start, end: max($0.start, $0.end)), $0.credited) }
            : [(span, credited)]
        return whole.flatMap { slice -> [(span: DateInterval, credited: [String: TimeInterval])] in
            if slice.span.duration == 0 {
                return focus.contains { $0.contains(slice.span.start) } ? [slice] : []
            }
            return focus.compactMap { interval in
                guard let cut = interval.intersection(with: slice.span), cut.duration > 0 else { return nil }
                let share = cut.duration / slice.span.duration
                return (cut, slice.credited.mapValues { $0 * share })
            }
        }
    }

    /// The day's focus by purpose: the credited seconds of each focus session
    /// row that day, summed, each capped at the ring so an activity row never
    /// reads more than the day's focus (the two are worked out separately).
    /// Where rows overlap, a later row counts only the share of its span no
    /// earlier row covers, so the same minutes are not counted twice; its
    /// credit is taken as spread evenly over its span.
    static func focusByPurpose(rows: [(span: DateInterval, credited: [String: TimeInterval])],
                               ring: TimeInterval) -> [String: TimeInterval] {
        var total: [String: TimeInterval] = [:]
        var covered: [DateInterval] = []   // earlier rows' spans, merged, in order
        for row in rows.sorted(by: { $0.span.start < $1.span.start }) {
            let overlap = covered.reduce(0.0) { $0 + ($1.intersection(with: row.span)?.duration ?? 0) }
            let fresh = row.span.duration > 0 ? max(0, 1 - overlap / row.span.duration) : 1
            total.merge(row.credited.mapValues { $0 * fresh }, uniquingKeysWith: +)
            if let last = covered.last, last.end >= row.span.start {
                covered[covered.count - 1] = DateInterval(start: last.start, end: max(last.end, row.span.end))
            } else {
                covered.append(row.span)
            }
        }
        return total.mapValues { min($0, max(0, ring)) }
    }
}
