import SwiftUI

/// Reference-specific measures for the Story shell. Operational surfaces keep
/// their established controls; Story has one warm canvas and a quiet rail.
enum StoryStyle {
    static let canvas = Color(lightHex: 0xFBFAF8, darkHex: 0x1D1D1F)
    static let rail = Color(lightHex: 0xF6F5F3, darkHex: 0x232325)
    static let card = Color(lightHex: 0xFFFFFF, darkHex: 0x2C2C2E)
    static let well = Color(lightHex: 0xF0EFED, darkHex: 0x343437)
    static let focus = Color(lightHex: 0x4E4CCC, darkHex: 0xB6B3FF)
    static let action = Color(lightHex: 0x0071E3, darkHex: 0x75B5FF)
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

    static func workTypeInk(_ type: WorkType) -> Color {
        switch type {
        case .deepWork: return focus
        case .meetings: return Color(lightHex: 0xA35F00, darkHex: 0xFFC575)
        case .admin: return Color(lightHex: 0x126C7C, darkHex: 0x73D1E2)
        case .learning: return Color(lightHex: 0xB12650, darkHex: 0xFF91AD)
        case .breakTime: return .secondary
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

/// A restrained press treatment, retaining the native Button's keyboard and
/// accessibility behaviour. It never adds motion when Reduce Motion is enabled.
struct StoryPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12),
                       value: configuration.isPressed)
    }
}
