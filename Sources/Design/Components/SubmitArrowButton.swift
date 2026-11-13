import SwiftUI

/// The round arrow that sends what a text box holds: Ask's question, the away
/// prompt's name for a break. A glyph in the accent circle, with a tooltip,
/// because a glyph alone is a guess. Dims when disabled.
struct SubmitArrowButton: View {
    let help: String
    /// Spoken name when the tooltip is a sentence rather than a name.
    var label: String?
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(Tokens.Typography.ring)
                .foregroundStyle(Tokens.Colour.onFocus)
                .frame(width: AccessibilityMetrics.minimumTargetSize,
                       height: AccessibilityMetrics.minimumTargetSize)
                .background(Tokens.Colour.focus, in: Circle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.45)
        .help(help)
        .accessibilityLabel(label ?? help)
    }
}
