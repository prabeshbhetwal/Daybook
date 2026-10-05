import Foundation

/// The checks' shared moment, `SelfTest.base`, is a local morning in every
/// time zone. As one fixed instant it fell at 11 pm in Berlin, and checks
/// that step an hour on from it crossed midnight there and nowhere else.
enum FixtureClockChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The checks' shared moment is 9:13 am on 15 November 2023 in whatever time zone they run",
         baseIsLocalMorning)
    ]

    /// In Sydney the old fixed instant was also 9:13 am, so this can only
    /// fail elsewhere: on GitHub's UTC runner, for one.
    private static func baseIsLocalMorning() -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: SelfTest.base)
        var problems: [String] = []
        expect([parts.year, parts.month, parts.day, parts.hour, parts.minute] == [2023, 11, 15, 9, 13],
               "SelfTest.base reads \(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0) "
               + "\(parts.hour ?? 0):\(parts.minute ?? 0) in \(TimeZone.current.identifier)", &problems)
        return problems
    }
}
