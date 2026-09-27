import SwiftUI

/// Shared interaction metrics for compact desktop controls. Callers use the
/// same value for their visible frame, so the accessibility regression checks
/// the hit area that production actually consumes rather than a test-only
/// constant.
enum AccessibilityMetrics {
    static let minimumTargetSize: CGFloat = 28
}

enum TabRailPresentation {
    static let usesOuterSurface = false
    static let unselectedUsesBorder = false
    static let showsLabelsInIconFallback = true
}

extension AppTab {
    func accessibilityLabel(isSelected: Bool) -> String {
        "\(title), \(isSelected ? "selected" : "not selected"), Command \(commandNumber)"
    }
}

