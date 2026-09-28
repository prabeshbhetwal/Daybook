import SwiftUI

/// Reference-specific measures for the Story shell. Operational surfaces keep
/// their established controls; Story has one warm canvas and a quiet rail.
enum StoryStyle {
    static let canvas = Color(lightHex: 0xFBFAF8, darkHex: 0x1D1D1F)
    static let rail = Color(lightHex: 0xF6F5F3, darkHex: 0x232325)
    static let card = Color(lightHex: 0xFFFFFF, darkHex: 0x2C2C2E)
    static let well = Color(lightHex: 0xF0EFED, darkHex: 0x343437)
    static let focus = Color(lightHex: 0x4E4CCC, darkHex: 0xB6B3FF)
    /// Links and text actions. The light value is a shade under Apple's
    /// #0071E3, which fell to 4.1:1 on the well and the rail.
    static let action = Color(lightHex: 0x0068D1, darkHex: 0x75B5FF)
    static let successInk = Color(lightHex: 0x087C3B, darkHex: 0x73D79A)
    static let successWash = Color(lightHex: 0xEFF8EF, darkHex: 0x25352B)
    static let line = Color(light: NSColor.black.withAlphaComponent(0.07),
                            dark: NSColor.white.withAlphaComponent(0.09))
    static let columnInsets = EdgeInsets(top: 26, leading: 30, bottom: 34, trailing: 30)
    static let railInsets = EdgeInsets(top: 22, leading: 20, bottom: 30, trailing: 20)
    static let entryInsets = EdgeInsets(top: 13, leading: 15, bottom: 13, trailing: 15)
    static let tileInsets = EdgeInsets(top: 15, leading: 16, bottom: 15, trailing: 16)
    static let entryRadius: CGFloat = 13
    static let tileRadius: CGFloat = 14
    static let headline = Font.system(size: 25, weight: .semibold)
    static let headlineMeasure: CGFloat = 560

    /// Text-weight colour for a category: darker than its swatch in light
    /// mode, lighter in dark, so a name set in it still reads on the canvas.
    static func workTypeInk(_ type: WorkType) -> Color { ink(type.hue) }

    static func ink(_ hue: WorkTypeHue) -> Color {
        switch hue {
        case .indigo: return focus
        case .orange: return Color(lightHex: 0xA35F00, darkHex: 0xFFC575)
        case .teal: return Color(lightHex: 0x126C7C, darkHex: 0x73D1E2)
        case .pink: return Color(lightHex: 0xB12650, darkHex: 0xFF91AD)
        case .blue: return Color(lightHex: 0x0059B3, darkHex: 0x7DB8FF)
        case .purple: return Color(lightHex: 0x7A2FB5, darkHex: 0xD69BFF)
        case .green: return Color(lightHex: 0x1E7A3A, darkHex: 0x7EDC9A)
        case .yellow: return Color(lightHex: 0x8A6D00, darkHex: 0xFFE070)
        case .red: return Color(lightHex: 0xB3261E, darkHex: 0xFF8A80)
        case .brown: return Color(lightHex: 0x6B5236, darkHex: 0xD3B48F)
        case .grey: return .secondary
        }
    }

    static func columnInsets(for density: InterfaceDensity) -> EdgeInsets {
        density == .compact ? EdgeInsets(top: 20, leading: 24, bottom: 26, trailing: 24) : columnInsets
    }

    static func railInsets(for density: InterfaceDensity) -> EdgeInsets {
        density == .compact ? EdgeInsets(top: 16, leading: 16, bottom: 24, trailing: 16) : railInsets
    }

    static func entryInsets(for density: InterfaceDensity) -> EdgeInsets {
        density == .compact ? EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12) : entryInsets
    }

    static func tileInsets(for density: InterfaceDensity) -> EdgeInsets {
        density == .compact ? EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14) : tileInsets
    }
}

/// A text action in the app's own voice: semibold metadata in the action
/// colour, a hover tint, a press that dims. Every in-app link wears this —
/// the chrome's History and Insights, "Show all visits", "Undo", "Retry" —
/// where before half of them were AppKit's borderless text button and half
/// were this, two vocabularies for one kind of thing.
struct StoryLinkStyle: ButtonStyle {
    var tint: Color = StoryStyle.action
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Tokens.Typography.metadata.weight(.semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(enabled ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
            .padding(.horizontal, Tokens.Space.s)
            .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
            .contentShape(Rectangle())
            .hoverHighlight(cornerRadius: Tokens.Radius.control)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(Tokens.Motion.animation(configuration.isPressed ? Tokens.Motion.press
                                                                       : Tokens.Motion.release,
                                               reduceMotion: reduceMotion),
                       value: configuration.isPressed)
    }
}

/// A restrained press treatment, retaining the native Button's keyboard and
/// accessibility behaviour. It never adds motion when Reduce Motion is enabled:
/// the press dims but does not shrink.
struct StoryPressStyle: ButtonStyle {
    /// Rows and text actions that should also tint under the pointer.
    var hovers = false
    var cornerRadius: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Group {
            if hovers {
                configuration.label.hoverHighlight(cornerRadius: cornerRadius)
            } else {
                configuration.label
            }
        }
        .opacity(configuration.isPressed ? 0.6 : 1)
        .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
        .animation(Tokens.Motion.animation(configuration.isPressed ? Tokens.Motion.press
                                                                   : Tokens.Motion.release,
                                           reduceMotion: reduceMotion),
                   value: configuration.isPressed)
    }
}
