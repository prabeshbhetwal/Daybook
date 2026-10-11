import AppKit
import SwiftUI

/// Whether Ask's supporting text can be read: the ink under a label, a footer,
/// a placeholder. The system's secondary ink is 3.9:1 on the light surfaces,
/// which is under the 4.5:1 normal text needs, so Ask sets that text in
/// `StoryStyle.supportingInk`.
enum AskLegibilityChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Ask's supporting text holds 4.5:1 on every surface Ask draws on, in both appearances", supportingInkIsLegible),
    ]

    /// A colour as the given appearance resolves it, over nothing: sRGB and alpha.
    private static func resolved(_ color: Color, dark: Bool) -> (r: Double, g: Double, b: Double, a: Double) {
        var out = (r: 0.0, g: 0.0, b: 0.0, a: 1.0)
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            guard let c = NSColor(color).usingColorSpace(.sRGB) else { return }
            out = (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent))
        }
        return out
    }

    private static func hex(_ r: Double, _ g: Double, _ b: Double) -> UInt32 {
        func byte(_ v: Double) -> UInt32 { UInt32((max(0, min(1, v)) * 255).rounded()) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }

    private static func supportingInkIsLegible() -> [String] {
        var problems: [String] = []
        let grounds: [(String, Color)] = [
            ("the side panel's rail", StoryStyle.rail), ("the sheet's ground", Tokens.Colour.ground),
            ("the sources list", Tokens.Colour.surface), ("the question field", Tokens.Colour.elevated),
        ]
        let light = resolved(StoryStyle.supportingInk, dark: false)
        let dark = resolved(StoryStyle.supportingInk, dark: true)
        expect(light.r < 0.5 && dark.r > 0.5, "the ink does not follow the appearance: light \(light), dark \(dark)", &problems)
        for isDark in [false, true] {
            let ink = isDark ? dark : light
            for (name, ground) in grounds {
                let bg = resolved(ground, dark: isDark)
                let over = hex(ink.r * ink.a + bg.r * (1 - ink.a), ink.g * ink.a + bg.g * (1 - ink.a),
                               ink.b * ink.a + bg.b * (1 - ink.a))
                let ratio = SelfTest.contrastRatio(over, hex(bg.r, bg.g, bg.b))
                expect(ratio >= 4.5, "supporting text on \(name) in the \(isDark ? "dark" : "light") appearance is \(ratio):1", &problems)
            }
        }
        return problems
    }
}
