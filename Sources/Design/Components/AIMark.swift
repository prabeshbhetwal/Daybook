import SwiftUI

/// The AI mark (ruling C17): a small sparkle beside a category Apple Intelligence set, in the supporting ink at
/// caption size, on the session row and in its report. VoiceOver hears its words, never the symbol, and its
/// help says where to keep or change the category.
struct AIMark: View {
    static let spoken = "assigned by AI"
    static let helpText = "Assigned by on-device AI. Open the session to keep or change it."

    var body: some View {
        Image(systemName: "sparkle")
            .font(Tokens.Typography.caption)
            .foregroundStyle(StoryStyle.supportingInk)
            .help(Self.helpText)
            .accessibilityLabel(Self.spoken)
    }
}
