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

/// One headline figure with the line that gives it meaning. A bare number is
/// what the old stat row showed; the context line is what makes it a card.
struct StatCard: View {
    let label: String
    let value: String
    var context: String?
    var contextTint: Color?
    /// A per-day series drawn as a small bar strip under the context line,
    /// the last day full strength. Empty draws nothing.
    var spark: [Double] = []
    var sparkTint: Color = Tokens.Colour.focus
    /// Optional icon before the label and a small qualifier pill top-right.
    var symbol: String?
    var badge: String?
    var badgeTint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.xs) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                // The label never breaks; a long badge yields, scaling down
                // before it truncates — "TRACKE / D" was the alternative.
                Text(label.uppercased())
                    .font(Tokens.Typography.sectionLabel)
                    .kerning(0.7)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .layoutPriority(1)
                Spacer(minLength: Tokens.Space.xs)
                if let badge {
                    Text(badge)
                        .font(Tokens.Typography.detail.weight(.medium).monospacedDigit())
                        .foregroundStyle(badgeTint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background((badgeTint ?? Color.primary).opacity(badgeTint == nil ? 0.06 : 0.14),
                                    in: Capsule())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Text(value)
                .font(Tokens.Typography.stat)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(context ?? " ")
                .font(Tokens.Typography.detail)
                .foregroundStyle(contextTint.map(AnyShapeStyle.init)
                                 ?? AnyShapeStyle(.secondary))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if !spark.isEmpty {
                Sparkline(values: spark, tint: sparkTint)
                    .padding(.top, Tokens.Space.xs)
            }
        }
        // Stretches to the tallest card in its row, so a two-line context on
        // one card does not leave its neighbours shorter.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card(padding: Tokens.Space.m)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)\(context.map { ", \($0)" } ?? "")")
    }
}

/// Share of something, as a 6pt bar in a well. The number beside it carries
/// the fact; this carries the shape.
struct DataBar: View {
    let share: Double
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Tokens.Colour.elevated)
                Capsule()
                    .fill(tint)
                    .frame(width: max(3, geometry.size.width * min(1, max(0, share))))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 28, height: 28)
                .background(prominent ? AnyShapeStyle(Tokens.Colour.focus.opacity(0.15))
                                      : AnyShapeStyle(Tokens.Colour.elevated),
                            in: Circle())
                .foregroundStyle(prominent ? AnyShapeStyle(Tokens.Colour.focus)
                                           : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

extension View {
    /// No focus ring. The dashboard's segmented controls and the calendar are
    /// clicked, never tabbed to, and the ring AppKit drew around whichever
    /// became first responder read as a stray selection border.
    @ViewBuilder func quietFocus() -> some View {
        if #available(macOS 14.0, *) {
            self.focusEffectDisabled()
        } else {
            self.focusable(false)
        }
    }
}
