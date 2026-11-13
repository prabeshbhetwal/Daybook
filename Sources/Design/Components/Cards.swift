import SwiftUI

// The card vocabulary shared by the popover and the dashboard. Plain values in,
// so the gallery can drive every one of these from fixtures.

private struct CardModifier: ViewModifier {
    let padding: CGFloat
    let surface: Color

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.panel,
                                                      style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.panel, style: .continuous)
                    .strokeBorder(Tokens.Colour.line, lineWidth: 1)
            )
    }
}

/// A question the Story asks in place: the amber wash and hairline of a
/// notice, cut like the entry cards around it.
private struct QuestionCardModifier: ViewModifier {
    @Environment(\.focusInterfaceDensity) private var density

    func body(content: Content) -> some View {
        content
            .padding(StoryStyle.entryInsets(for: density))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tokens.Colour.attention.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: StoryStyle.entryRadius,
                                             style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: StoryStyle.entryRadius, style: .continuous)
                .strokeBorder(Tokens.Colour.attention.opacity(0.35)))
    }
}

extension View {
    /// The one look of an unanswered question in the day's story, whether it
    /// is the away prompt or a past stretch asking how it should count.
    func questionCard() -> some View {
        modifier(QuestionCardModifier())
    }

    /// A lifted surface on the ground: `Colour.surface`, continuous 16pt corners,
    /// one hairline. Cards size to their content; the ground between them is
    /// the layout.
    func card(padding: CGFloat = Tokens.Space.l,
              surface: Color = Tokens.Colour.surface) -> some View {
        modifier(CardModifier(padding: padding, surface: surface))
    }
}

/// A 28pt symbol button for the places a word would be louder than the action
/// deserves: borderless like a toolbar symbol, with a tint only when it is the
/// prominent one. Always carries a tooltip, because a glyph alone is a guess.
struct IconButton: View {
    let systemImage: String
    let help: String
    var prominent: Bool = false
    /// Spoken name when the tooltip is a sentence rather than a name.
    var label: String?
    /// A toggle's state, so the circle can say it is on.
    var isOn: Bool?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(Tokens.Typography.control)
                .symbolRenderingMode(.hierarchical)
                .symbolSwap()
                .frame(width: AccessibilityMetrics.minimumTargetSize,
                       height: AccessibilityMetrics.minimumTargetSize)
                .background(prominent ? AnyShapeStyle(Tokens.Colour.focus.opacity(0.15))
                                      : AnyShapeStyle(Color.clear),
                            in: Circle())
                .hoverHighlight(cornerRadius: Tokens.Radius.well)
                .foregroundStyle(prominent ? AnyShapeStyle(Tokens.Colour.focus)
                                           : AnyShapeStyle(StoryStyle.supportingInk))
        }
        .buttonStyle(PressableStyle())
        .help(help)
        .accessibilityLabel(label ?? help)
        // A toggle says its state either way; a selected trait alone left
        // "off" unspoken.
        .accessibilityValue(isOn.map { $0 ? "On" : "Off" } ?? "")
    }
}
