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

extension View {
    /// A lifted surface on the ground: `Colour.surface`, continuous 16pt corners,
    /// one hairline. Cards size to their content; the ground between them is
    /// the layout.
    func card(padding: CGFloat = Tokens.Space.l,
              surface: Color = Tokens.Colour.surface) -> some View {
        modifier(CardModifier(padding: padding, surface: surface))
    }
}

/// An app's icon with its palette colour beside it, so the row is its own
/// legend. Falls back to a rounded square in the colour when the app has no
/// icon on this machine.
struct AppSwatch: View {
    let rank: Int
    var bundleID: String?
    var appName: String = ""
    var size: CGFloat = 18

    var body: some View {
        HStack(spacing: Tokens.Space.xs) {
            if let bundleID,
               AppIconProvider.shared.icon(for: bundleID, size: size) != nil {
                AppIcon(bundleID: bundleID, size: size, appName: appName)
            } else {
                RoundedRectangle(cornerRadius: Tokens.Radius.swatch, style: .continuous)
                    .fill(Tokens.Palette.app(rank: rank))
                    .frame(width: size, height: size)
                    .overlay(
                        Text(appName.first.map(String.init)?.uppercased() ?? "")
                            .font(.system(size: size * 0.55, weight: .semibold))
                            .foregroundStyle(.white)
                    )
            }
            Circle()
                .fill(Tokens.Palette.app(rank: rank))
                .frame(width: 6, height: 6)
        }
        .accessibilityHidden(true)
    }
}

/// A round 28pt button for the places a word would be louder than the action
/// deserves. Always carries a tooltip, because a glyph alone is a guess.
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
                .font(Tokens.Typography.control.weight(.medium))
                .symbolRenderingMode(.hierarchical)
                .symbolSwap()
                .symbolNod(on: isOn ?? false)
                .frame(width: AccessibilityMetrics.minimumTargetSize,
                       height: AccessibilityMetrics.minimumTargetSize)
                .background(prominent ? AnyShapeStyle(Tokens.Colour.focus.opacity(0.15))
                                      : AnyShapeStyle(Tokens.Colour.elevated),
                            in: Circle())
                .foregroundStyle(prominent ? AnyShapeStyle(Tokens.Colour.focus)
                                           : AnyShapeStyle(.secondary))
        }
        .buttonStyle(PressableStyle())
        .help(help)
        .accessibilityLabel(label ?? help)
        // A toggle says its state either way; a selected trait alone left
        // "off" unspoken.
        .accessibilityValue(isOn.map { $0 ? "On" : "Off" } ?? "")
    }
}
