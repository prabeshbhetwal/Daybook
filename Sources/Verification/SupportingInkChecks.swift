import AppKit
import SwiftUI

/// Whether supporting text can be read wherever the app draws it. The system's
/// secondary ink is 3.8:1 on the light surfaces, under the 4.5:1 normal text
/// needs, so supporting text and the symbols beside it are set in
/// `StoryStyle.supportingInk`. This draws that text as the window does and
/// reads the pixels back, on every surface and wash it sits on.
enum SupportingInkChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Supporting text holds 4.5:1 in its rendered pixels on every surface and wash, in both appearances, at 80, 100 and 140%",
         supportingInkRendersLegibly),
    ]

    /// Each ground supporting text is drawn on: a surface, or a wash over one.
    private static var grounds: [(String, AnyView)] {
        func wash(_ tint: Color, _ amount: Double, over base: Color) -> AnyView {
            AnyView(ZStack { base; tint.opacity(amount) })
        }
        return [
            ("the canvas", AnyView(StoryStyle.canvas)), ("the rail", AnyView(StoryStyle.rail)),
            ("a card", AnyView(StoryStyle.card)), ("a well", AnyView(StoryStyle.well)),
            ("the ground", AnyView(Tokens.Colour.ground)), ("a surface", AnyView(Tokens.Colour.surface)),
            ("a field", AnyView(Tokens.Colour.elevated)), ("the success wash", AnyView(StoryStyle.successWash)),
            ("a focused row", wash(Tokens.Colour.focus, 0.12, over: StoryStyle.canvas)),
            ("an attention card", wash(Tokens.Colour.attention, 0.10, over: StoryStyle.card)),
            ("a chosen app", wash(StoryStyle.action, 0.12, over: StoryStyle.card)),
            ("a period card's badge", wash(StoryStyle.focus, 0.14, over: StoryStyle.card)),
        ]
    }

    private static func supportingInkRendersLegibly() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            for percent in [80, 100, 140] {
                InterfaceZoomChecks.withZoom(percent) {
                    for dark in [false, true] {
                        for (name, ground) in grounds {
                            for (role, font) in [("caption", Tokens.Typography.caption), ("body", Tokens.Typography.body)] {
                                let ratio = peakContrast(font: font, ground: ground, dark: dark)
                                expect(ratio >= 4.5, "\(role) supporting text on \(name), \(dark ? "dark" : "light"), "
                                       + "\(percent)%, should hold 4.5:1, got \(String(format: "%.2f", ratio)):1", &problems)
                            }
                        }
                    }
                }
            }
            return problems
        }
    }

    /// The strongest contrast any pixel of the text makes with the ground: at
    /// the window's 2× scale a stroke's middle reaches the ink's full colour.
    @MainActor private static func peakContrast(font: Font, ground: AnyView, dark: Bool) -> Double {
        let renderer = ImageRenderer(content: Text("Supporting text 4h 12m")
            .font(font)
            .foregroundStyle(StoryStyle.supportingInk)
            .padding(6)
            .background(ground)
            .environment(\.colorScheme, dark ? .dark : .light))
        renderer.scale = 2
        guard let image = renderer.cgImage else { return 0 }
        let bitmap = NSBitmapImageRep(cgImage: image)
        // The bitmap is sRGB, but colorAt tags its colours calibrated, and a
        // conversion back to sRGB lightens them, so read the bytes.
        func hex(_ x: Int, _ y: Int) -> UInt32 {
            var pixel = [Int](repeating: 0, count: 4)
            bitmap.getPixel(&pixel, atX: x, y: y)
            return UInt32(pixel[0]) << 16 | UInt32(pixel[1]) << 8 | UInt32(pixel[2])
        }
        let background = hex(1, 1)
        var peak = 1.0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide { peak = max(peak, SelfTest.contrastRatio(hex(x, y), background)) }
        }
        return peak
    }
}
