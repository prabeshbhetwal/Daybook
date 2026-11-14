import SwiftUI

/// The five shades History's grid gives a day by how much focus it held: the
/// focus colour at a growing strength, so each shade is the next one's lighter
/// self over any surface. The strengths are chosen for contrast (FocusRampChecks).
enum FocusRamp {
    /// Opacity of `Tokens.Colour.focus` for each step; none is not drawn in it.
    static func strength(_ step: HistoryFocusStep, dark: Bool) -> Double {
        switch step {
        case .none: return 0
        case .under2h: return dark ? 0.35 : 0.46
        case .under5h: return dark ? 0.55 : 0.64
        case .under8h: return dark ? 0.76 : 0.82
        case .over8h: return 1.0
        }
    }

    /// Follows the appearance, and stays translucent so one fill serves the
    /// canvas and a card.
    static func fill(_ step: HistoryFocusStep) -> Color {
        guard step != .none else { return none }
        func tint(dark: Bool) -> NSColor {
            NSColor(hex: Tokens.Colour.resolved(.focus, dark: dark).hex,
                    alpha: strength(step, dark: dark))
        }
        return Color(light: tint(dark: false), dark: tint(dark: true))
    }

    /// A day with no focus: the story hairline, a faint cell on either surface.
    static var none: Color { StoryStyle.line }

    /// The outline of a day still to come.
    static var toCome: Color { StoryStyle.line }
}
