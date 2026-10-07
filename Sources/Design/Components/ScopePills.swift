import SwiftUI

/// The one scope-pill appearance. Every Day/Week/Month row draws through this
/// modifier, so the surfaces cannot drift apart by editing one copy.
extension View {
    func scopePillContainer() -> some View {
        padding(3.zoomed)
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
    @Namespace private var capsule
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2.zoomed) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                let isSelected = index == selectedIndex
                Text(title)
                    .font(Tokens.Typography.label)
                    .padding(.horizontal, Tokens.Space.m)
                    .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
                    .foregroundStyle(isSelected ? AnyShapeStyle(Tokens.Colour.onFocus)
                                                : AnyShapeStyle(Color.secondary))
                    // One capsule for the row, matched across pills, so a
                    // change of scope is the capsule sliding to the new word
                    // rather than one pill going out and another coming on.
                    .background {
                        if isSelected {
                            Capsule().fill(Tokens.Colour.focus)
                                .matchedGeometryEffect(id: "selected", in: capsule)
                        }
                    }
            }
        }
        .scopePillContainer()
        .animation(Tokens.Motion.animation(Tokens.Motion.selection, reduceMotion: reduceMotion),
                   value: selectedIndex)
        .accessibilityHidden(true)
    }
}
