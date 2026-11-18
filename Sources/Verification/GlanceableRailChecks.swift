import Foundation

/// The rail says what its tiles measure, so a reader never has to guess the
/// period or decode a chart. Explanations sit behind each tile's info mark.
enum GlanceableRailChecks {
    static let tests: [(String, () -> [String])] = [
        ("The top apps tile says which day it covers and how many apps the list was cut from",
         appsHelpStatesPeriod)
    ]

    static func appsHelpStatesPeriod() -> [String] {
        let cases: [(shown: Int, total: Int, day: String, period: String, count: String)] = [
            (4, 10, "Today", "today", "Showing 4 of the 10 apps you used."),
            (3, 3, "Yesterday", "yesterday", "All 3 apps you used."),
            (1, 1, "Today", "today", "The only app you used."),
            (4, 7, "Mon 17 Nov", "on Mon 17 Nov", "Showing 4 of the 7 apps you used.")
        ]
        return cases.compactMap { item in
            let help = StoryRailFigures.appsHelp(shown: item.shown, total: item.total, dayLabel: item.day)
            let expected = [HelpEntry("What it shows", "Your most-used apps \(item.period), in and out of focus sessions."),
                            HelpEntry("How many", item.count)]
            return help == expected ? nil : "for \(item.day) \(item.shown)/\(item.total) read \(help.map(\.text))"
        }
    }
}
