import SwiftUI

/// Which span the story is telling. The scope control changes only what the
/// story is about; it never changes surface.
enum StoryScope: String, CaseIterable, Identifiable {
    case day, week, month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        }
    }

    /// The Review period a scope resolves to, or nil for the day — the day is
    /// the selected-day read model rather than a period rollup.
    var period: TrackingPeriod? {
        switch self {
        case .day: return nil
        case .week: return .week
        case .month: return .month
        }
    }
}

enum StoryLayout {
    /// The rail is fixed so the story column keeps a stable reading measure.
    static let railWidth: CGFloat = 336
}
