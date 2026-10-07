import SwiftUI

/// A filter as a chip, cut like the bar's Away and Stop. Neutral while it
/// filters nothing; once something is picked it takes that pick's icon and
/// colour, and offers its own × so one filter clears without the other.
///
/// Built as `WorkTypePicker`'s quiet menu is: `.button` menu style over a
/// plain button, so the label draws as written. A borderless menu draws
/// AppKit's blue text instead, whatever the label asks for.
struct FilterChip<Icon: View, Items: View>: View {
    let title: String
    let isActive: Bool
    /// The wash and outline once active.
    var tint: Color = StoryStyle.action
    /// Text and × once active; a contrast-checked ink where one exists.
    var ink: Color = StoryStyle.action
    /// "App filter": read before the selection.
    let filterName: String
    /// "Show all apps": the ×'s label and tooltip.
    let clearLabel: String
    let onClear: () -> Void
    @ViewBuilder let icon: () -> Icon
    @ViewBuilder let items: () -> Items
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static var height: CGFloat { 32.zoomed }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous) }

    var body: some View {
        HStack(spacing: 0) {
            Menu { items() } label: {
                HStack(spacing: Tokens.Space.xs) {
                    icon()
                        .frame(width: 16.zoomed, height: 16.zoomed)
                        .foregroundStyle(isActive ? AnyShapeStyle(ink) : AnyShapeStyle(.secondary))
                    Text(title)
                        .font(Tokens.Typography.control)
                        .lineLimit(1)
                        .foregroundStyle(isActive ? AnyShapeStyle(ink) : AnyShapeStyle(.primary))
                    if !isActive {
                        Image(systemName: "chevron.down")
                            .font(Tokens.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, Tokens.Space.m)
                .padding(.trailing, isActive ? Tokens.Space.xs : Tokens.Space.m)
                .frame(height: Self.height)
                .contentShape(shape)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(isActive ? "Change \(filterName.lowercased())" : filterName)
            .accessibilityLabel("\(filterName), selected \(title)")
            if isActive {
                Button(action: onClear) {
                    Image(systemName: "xmark")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(ink)
                        .frame(width: AccessibilityMetrics.minimumTargetSize, height: Self.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(StoryPressStyle())
                .help(clearLabel)
                .accessibilityLabel(clearLabel)
                .transition(.opacity)
            }
        }
        .background(isActive ? AnyShapeStyle(tint.opacity(0.12)) : AnyShapeStyle(Tokens.Colour.elevated), in: shape)
        .overlay(shape.strokeBorder(isActive ? tint.opacity(0.35) : Tokens.Colour.line))
        .hoverHighlight(cornerRadius: Tokens.Radius.nested)
        .animation(Tokens.Motion.animation(Tokens.Motion.selection, reduceMotion: reduceMotion), value: isActive)
        .fixedSize()
    }
}
