import Foundation

/// One neutral background family. Sheets, the popover and Awards drew on a
/// cool grey (#F2F2F7) while the main canvas and rail are warm neutrals, so
/// the same app looked like two. In light appearance every background token
/// now leans warm like `StoryStyle.canvas`, and supporting text still reads
/// on it.
enum NeutralFamilyChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The ground and the field are warm neutrals like the canvas, and supporting ink keeps 4.5:1 on them",
         backgroundsShareOneFamily),
    ]

    private static func channels(_ hex: UInt32) -> (r: Int, g: Int, b: Int) {
        (Int(hex >> 16) & 0xFF, Int(hex >> 8) & 0xFF, Int(hex) & 0xFF)
    }

    private static func backgroundsShareOneFamily() -> [String] {
        var problems: [String] = []
        for (name, token) in [("ground", Tokens.Colour.Name.ground), ("elevated", .elevated)] {
            let hex = Tokens.Colour.resolved(token, dark: false).hex
            let c = channels(hex)
            // The canvas (#FBFAF8), rail (#F6F5F3) and well (#F0EFED) each run
            // red > green > blue by a few steps; the cool grey ran blue > red.
            expect(c.r > c.g && c.g > c.b && c.r - c.b <= 10,
                   "light \(name) is not a warm neutral: \(String(hex, radix: 16))", &problems)
            // Supporting ink is the primary ink (black) at 75% over the surface.
            let ink = UInt32(c.r / 4) << 16 | UInt32(c.g / 4) << 8 | UInt32(c.b / 4)
            let ratio = SelfTest.contrastRatio(ink, hex)
            expect(ratio >= 4.5, "supporting ink on light \(name) is \(ratio):1, under 4.5:1", &problems)
            let dark = channels(Tokens.Colour.resolved(token, dark: true).hex)
            expect(abs(dark.r - dark.b) <= 4, "dark \(name) leans cool or warm: \(dark)", &problems)
        }
        return problems
    }
}
