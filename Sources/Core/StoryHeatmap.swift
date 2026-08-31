import Foundation

/// A duration heatmap, independent of the daily goal. Resolved opaque colours
/// let small date labels choose an actually legible foreground in either theme.
enum StoryHeatmap {
    struct Paint: Equatable {
        let background: UInt32
        let foreground: UInt32
        let intensity: Double
    }

    static func paint(seconds: TimeInterval, peak: TimeInterval, dark: Bool) -> Paint {
        let hasValue = seconds.isFinite && seconds > 0 && peak.isFinite && peak > 0
        let intensity = hasValue ? 0.16 + 0.84 * min(1, seconds / peak) : 0
        let base: UInt32 = dark ? 0x2C2C2E : 0xFFFFFF
        let indigo: UInt32 = dark ? 0x7D7AFF : 0x4E4CCC
        let empty: UInt32 = dark ? 0x343437 : 0xF5F4F2
        let background = hasValue ? blend(indigo, over: base, alpha: intensity) : empty
        let luminance = relativeLuminance(background)
        // Max(black contrast, white contrast) is always at least 4.58:1.
        let whiteContrast = 1.05 / (luminance + 0.05)
        let blackContrast = (luminance + 0.05) / 0.05
        return Paint(background: background,
                     foreground: whiteContrast >= blackContrast ? 0xFFFFFF : 0x000000,
                     intensity: intensity)
    }

    private static func blend(_ foreground: UInt32, over background: UInt32,
                              alpha: Double) -> UInt32 {
        [16, 8, 0].reduce(UInt32(0)) { result, shift in
            let front = Double((foreground >> shift) & 0xFF)
            let back = Double((background >> shift) & 0xFF)
            let component = UInt32((front * alpha + back * (1 - alpha)).rounded())
            return result | (component << shift)
        }
    }

    private static func relativeLuminance(_ colour: UInt32) -> Double {
        let values = [16, 8, 0].map { shift -> Double in
            let component = Double((colour >> shift) & 0xFF) / 255
            return component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return values[0] * 0.2126 + values[1] * 0.7152 + values[2] * 0.0722
    }
}
