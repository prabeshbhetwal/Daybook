import SwiftUI

/// The one scope-pill appearance. Every Day/Week/Month row draws through these
/// two modifiers, so the surfaces cannot drift apart by editing one copy.
extension View {
    func scopePillLabel(isSelected: Bool) -> some View {
        font(Tokens.Typography.metadata.weight(.semibold))
            .padding(.horizontal, Tokens.Space.m)
            .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
            .background(isSelected ? Tokens.Colour.focus : Color.clear, in: Capsule())
            .foregroundStyle(isSelected ? AnyShapeStyle(Tokens.Colour.onFocus)
                                        : AnyShapeStyle(Color.secondary))
    }

    func scopePillContainer() -> some View {
        padding(3)
            .background(Tokens.Colour.elevated, in: Capsule())
            .overlay(Capsule().strokeBorder(Tokens.Colour.line))
    }
}

/// The pill row as appearance only. Interaction, keyboard traversal and
/// accessibility belong to whatever control sits over it — in the Story chrome
/// that is a real `NSSegmentedControl`, which gives the row a single keyboard
/// target instead of one tab stop per pill.
struct ScopePills: View {
    let titles: [String]
    let selectedIndex: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                Text(title).scopePillLabel(isSelected: index == selectedIndex)
            }
        }
        .scopePillContainer()
        .accessibilityHidden(true)
    }
}
