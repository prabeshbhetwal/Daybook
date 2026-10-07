import SwiftUI

/// Shared interaction metrics for compact desktop controls. Callers use the
/// same value for their visible frame, so the accessibility regression checks
/// the hit area that production actually consumes rather than a test-only
/// constant.
enum AccessibilityMetrics {
    // Never below 24pt, WCAG 2.5.8's target floor, which 28pt at 80% would miss.
    static var minimumTargetSize: CGFloat { max(24, 28.zoomed) }
}

extension AppTab {
    func accessibilityLabel(isSelected: Bool) -> String {
        "\(title), \(isSelected ? "selected" : "not selected"), Command \(commandNumber)"
    }
}

