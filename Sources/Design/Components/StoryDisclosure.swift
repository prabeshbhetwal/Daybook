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
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text(title)
                    Spacer(minLength: 0)
                }
                .font(Tokens.Typography.metadata.weight(.medium))
                .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(StoryPressStyle())
            .accessibilityLabel(title)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            if isExpanded { content }
        }
    }
}
