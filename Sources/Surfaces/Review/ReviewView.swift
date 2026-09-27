import SwiftUI

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
