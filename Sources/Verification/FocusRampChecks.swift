import AppKit
import SwiftUI

/// Checks for the focus colour ramp: its steps, contrast and lightness order.
/// Each step is drawn as the window draws it, over the canvas and over a card,
/// and the composited pixel is read back.
enum FocusRampChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Every shade of focus can be told from the page", everyShadeShowsOnThePage),
        ("Each shade is clearly darker than the one before", eachShadeStepsAwayFromTheLast),
    ]

    private static let surfaces: [(name: String, view: AnyView)] = [
        ("the canvas", AnyView(StoryStyle.canvas)), ("a card", AnyView(StoryStyle.card)),
    ]

    /// A view drawn over a surface, as the window draws it: the rendered pixel.
    @MainActor private static func pixel(_ content: some View, over surface: AnyView, dark: Bool) -> UInt32 {
        let renderer = ImageRenderer(content: content
            .frame(width: 4, height: 4)
            .background(surface)
            .environment(\.colorScheme, dark ? .dark : .light))
        renderer.scale = 1
        guard let image = renderer.cgImage else { return 0 }
        return SupportingInkChecks.hex(NSBitmapImageRep(cgImage: image), 1, 1)
    }

    @MainActor private static func pixel(_ step: HistoryFocusStep, over surface: AnyView, dark: Bool) -> UInt32 {
        pixel(FocusRamp.fill(step), over: surface, dark: dark)
    }

    private static func everyShadeShowsOnThePage() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            for dark in [false, true] {
                for (name, surface) in surfaces {
                    let page = pixel(Color.clear, over: surface, dark: dark)
                    let lightest = pixel(.under2h, over: surface, dark: dark)
                    let ratio = SelfTest.contrastRatio(lightest, page)
                    expect(ratio >= 2.0, "The lightest filled step on \(name), \(dark ? "dark" : "light"), "
                           + "should hold 2:1, got \(String(format: "%.2f", ratio)):1", &problems)
                }
            }
            return problems
        }
    }

    private static func eachShadeStepsAwayFromTheLast() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let steps = HistoryFocusStep.allCases
            for dark in [false, true] {
                for (name, surface) in surfaces {
                    let pixels = steps.map { pixel($0, over: surface, dark: dark) }
                    for index in 1..<pixels.count {
                        let ratio = SelfTest.contrastRatio(pixels[index], pixels[index - 1])
                        expect(ratio >= 1.3, "\(steps[index]) against \(steps[index - 1]) on \(name), "
                               + "\(dark ? "dark" : "light"), should hold 1.3:1, got \(String(format: "%.2f", ratio)):1",
                               &problems)
                        // Contrast with black rises with luminance: light mode darkens, dark mode lightens.
                        let rising = SelfTest.contrastRatio(pixels[index], 0) > SelfTest.contrastRatio(pixels[index - 1], 0)
                        expect(rising == dark, "\(steps[index]) should be \(dark ? "lighter" : "darker") than "
                               + "\(steps[index - 1]) on \(name), \(dark ? "dark" : "light")", &problems)
                    }
                }
            }
            return problems
        }
    }
}
