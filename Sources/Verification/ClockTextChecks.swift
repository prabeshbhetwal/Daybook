import Foundation

/// The live clock is drawn in two parts so only the minutes roll; the two
/// parts must still read as the one clock everything else prints.
enum ClockTextChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The live clock's rolling and plain parts join into the clock as printed elsewhere", partsJoin),
    ]

    private static func partsJoin() -> [String] {
        var problems: [String] = []
        for seconds in [0.0, 59, 60, 2_712, 3_661, 35_999, 86_399.9] {
            let parts = ClockText.parts(seconds)
            expect(parts.rolling + parts.plain == Tokens.clock(seconds),
                   "\(seconds)s splits into \(parts.rolling) and \(parts.plain), not \(Tokens.clock(seconds))", &problems)
            expect(parts.plain.hasPrefix(":") && parts.plain.count == 3,
                   "the plain part of \(seconds)s is the seconds alone", &problems)
        }
        expect(ClockText.parts(2_712).rolling == "00:45" && ClockText.parts(2_712).plain == ":12",
               "45 minutes 12 seconds rolls 00:45 and prints :12", &problems)
        expect(ClockText.parts(2_712).rolling == ClockText.parts(2_759).rolling,
               "the rolling part holds still within a minute", &problems)
        expect(ClockText.parts(.nan) == ("—", "") && ClockText.parts(.infinity) == ("—", ""),
               "an unshowable value is the dash, as Tokens.clock prints it", &problems)
        return problems
    }
}
