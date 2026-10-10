import SwiftUI

/// The bar's way into Ask Daybook. ⌘K alone is found only by someone who
/// already knows it is there, so the bar shows the sparkles assistants use
/// and the word "Ask", and the help tag teaches the key. Apple's own
/// Apple Intelligence glyph may only name Apple Intelligence, not an app's
/// feature, so it is kept for the sheet's line about who answers. When the
/// bar is short of room the word goes and the sparkles stay. While Ask's side
/// panel is open the button looks pressed, and the same press closes it.
struct AskChromeButton: View {
    /// Whether the side panel is open.
    var isActive = false
    let action: () -> Void

    /// In the bar when Ask can run on this Mac and the Settings switch is on.
    /// A Mac that can never run Ask is not shown a way into it.
    static func isShown(switchOn: Bool, offered: Bool = AskModel.isOffered) -> Bool { switchOn && offered }

    var body: some View {
        Button(action: action) {
            ViewThatFits(in: .horizontal) {
                label(withWord: true)
                label(withWord: false)
            }
        }
        .buttonStyle(PressableStyle())
        .help(isActive ? "Close Ask (⌘K)" : "Ask Daybook about your focus (⌘K)")
        .accessibilityLabel("Ask Daybook")
        .accessibilityHint(isActive ? "Closes the Ask panel" : "Ask a question about your focus history")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func label(withWord: Bool) -> some View {
        HStack(spacing: Tokens.Space.xs) {
            Image(systemName: "sparkles")
                .font(Tokens.Typography.control)
                .foregroundStyle(StoryStyle.askSparkles)
            if withWord {
                Text("Ask")
                    .font(Tokens.Typography.label)
                    .fixedSize()
            }
        }
        .padding(.horizontal, withWord ? Tokens.Space.m : 0)
        .frame(minWidth: AccessibilityMetrics.minimumTargetSize,
               minHeight: AccessibilityMetrics.minimumTargetSize)
        .background {
            Capsule().fill(Tokens.Colour.elevated)
            // Pressed in: the fill a step darker (lighter in the dark).
            if isActive {
                Capsule().fill(Tokens.Colour.line)
                    .storyRenderEvidence(.askButtonActive)
            }
        }
        .foregroundStyle(.primary)
        .storyRenderEvidence(withWord ? .askButtonWithWord : .askButton)
    }
}
