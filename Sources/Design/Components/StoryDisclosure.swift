import SwiftUI

/// A full-row disclosure target, including its label. The title and content
/// stay in one stack instead of looking like two unrelated cards.
struct StoryDisclosure<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(Tokens.Motion.animation(
                    isExpanded ? Tokens.Motion.dismiss : Tokens.Motion.reveal,
                    reduceMotion: reduceMotion)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    // One glyph that turns, not two that swap.
                    Image(systemName: "chevron.right")
                        .font(Tokens.Typography.microLabel)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text(title)
                    Spacer(minLength: 0)
                }
                .font(Tokens.Typography.metadata.weight(.medium))
                .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(StoryPressStyle(hovers: true))
            .accessibilityLabel(title)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            if isExpanded {
                content.transition(Tokens.Motion.transition(Tokens.Motion.unfold,
                                                            reduceMotion: reduceMotion))
            }
        }
    }
}
