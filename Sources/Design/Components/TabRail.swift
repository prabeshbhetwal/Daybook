import SwiftUI

/// Shared interaction metrics for compact desktop controls. Callers use the
/// same value for their visible frame, so the accessibility regression checks
/// the hit area that production actually consumes rather than a test-only
/// constant.
enum AccessibilityMetrics {
    static var minimumTargetSize: CGFloat { 28.zoomed }
}

extension AppTab {
    func accessibilityLabel(isSelected: Bool) -> String {
        "\(title), \(isSelected ? "selected" : "not selected"), Command \(commandNumber)"
    }
}

