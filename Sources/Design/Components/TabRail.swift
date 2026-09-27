import SwiftUI

/// Shared interaction metrics for compact desktop controls. Callers use the
/// same value for their visible frame, so the accessibility regression checks
/// the hit area that production actually consumes rather than a test-only
/// constant.
enum AccessibilityMetrics {
    static let minimumTargetSize: CGFloat = 28
}

extension AppTab {
    func accessibilityLabel(isSelected: Bool) -> String {
        "\(title), \(isSelected ? "selected" : "not selected"), Command \(commandNumber)"
    }
}

