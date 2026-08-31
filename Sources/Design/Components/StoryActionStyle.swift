import SwiftUI

/// Quiet filled controls match the reference while keeping real Button roles,
/// keyboard focus and a complete padded hit area.
struct StoryActionStyle: ButtonStyle {
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        StoryActionLabel(label: configuration.label, tint: tint, pressed: configuration.isPressed)
    }
}

private struct StoryActionLabel<Label: View>: View {
    let label: Label
    let tint: Color?
    let pressed: Bool
    @StateObject private var hovered = BoolBox()
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        label
            .font(Tokens.Typography.metadata.weight(.semibold))
            .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary))
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .frame(minHeight: 28)
            .background(fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.45)
            .onHover { hovered.value = $0 }
    }

    private var fill: Color {
        if let tint { return tint.opacity(pressed ? 0.24 : hovered.value ? 0.19 : 0.13) }
        return hovered.value || pressed ? Tokens.Colour.hover : StoryStyle.well
    }
}
