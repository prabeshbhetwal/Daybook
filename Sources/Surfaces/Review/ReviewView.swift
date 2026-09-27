import SwiftUI

/// The exact callback supplied to period bars and History day rows. Selecting
/// evidence explains that day inside Review; it never changes the tab and never
/// moves Today's own selected day. Opening the day in Today is a separate,
/// visibly named action on the selected-day detail.
@MainActor
enum ReviewDayRoute {
    static func select(store: SessionStore,
                       navigation: MainWindowModel) -> (Date) -> Void {
        { date in
            navigation.selectReviewDay(date)
        }
    }
}

/// Review's invariant reading sequence. Naming it makes the hierarchy testable
/// and stops a later edit from letting a breakdown drift above the answer it is
/// meant to support.
enum ReviewContentOrder: CaseIterable {
    case periodNavigation, summary, trend, selectedDetail, breakdowns, evidenceLists

    static func visible(selectedDay: Date?) -> [ReviewContentOrder] {
        allCases.filter { $0 != .selectedDetail || selectedDay != nil }
    }
}

/// Internal so every scope row and its checks name the sections identically.
extension ReviewSection {
    var title: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        case .history: return "History"
        }
    }
}
