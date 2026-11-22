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

    /// The day's focus by purpose: the credited seconds of each focus session
    /// row that day, summed, each capped at the ring so an activity row never
    /// reads more than the day's focus (the two are worked out separately).
    static func focusByPurpose(rows: [[String: TimeInterval]], ring: TimeInterval) -> [String: TimeInterval] {
        var total: [String: TimeInterval] = [:]
        for row in rows { total.merge(row, uniquingKeysWith: +) }
        return total.mapValues { min($0, max(0, ring)) }
    }
}
