import Foundation

/// The rail says what its tiles measure, so a reader never has to guess the
/// period or decode a chart. Explanations sit behind each tile's info mark.
enum GlanceableRailChecks {
    static let tests: [(String, () -> [String])] = [
        ("The top apps tile says which day it covers and how many apps the list was cut from",
         appsHelpStatesPeriod),
        ("The streak line says what today still needs, and when the dots show only part of the streak",
         streakStatusIsExact),
        ("The session strip's info names its marks and carries the session's own facts",
         stripHelpCarriesSession),
        ("Time of day splits the day into 3-hour blocks with focus capped at app use and later hours marked ahead",
         timeOfDayBlocks)
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

    static func streakStatusIsExact() -> [String] {
        var problems: [String] = []
        let minimum: TimeInterval = 25 * 60
        // 12m 40s printed as 12m: 13m more makes the printed 25m.
        let pending = StreakStatus.line(streak: 15, today: 12 * 60 + 40, minimum: minimum)
        if pending != "13m more focus today makes it 16 days." { problems.append("pending read \(pending)") }
        let fresh = StreakStatus.line(streak: 0, today: 0, minimum: minimum)
        if fresh != "25m more focus today makes it 1 day." { problems.append("a fresh day read \(fresh)") }
        // 24m 59s prints 24m; never "0m more".
        let almost = StreakStatus.line(streak: 3, today: 25 * 60 - 1, minimum: minimum)
        if almost != "1m more focus today makes it 4 days." { problems.append("almost there read \(almost)") }
        let met = StreakStatus.line(streak: 16, today: minimum, minimum: minimum)
        if met != "Today counts. Keep it going tomorrow." { problems.append("met read \(met)") }
        // 14 dots: 13 past days and today.
        if StreakStatus.outrunsDots(streak: 13, todayCounts: false, dots: 14) {
            problems.append("13 days pending fit the 13 past dots but were called partial")
        }
        if !StreakStatus.outrunsDots(streak: 14, todayCounts: false, dots: 14) {
            problems.append("14 days pending outrun the 13 past dots but were not called partial")
        }
        if StreakStatus.outrunsDots(streak: 14, todayCounts: true, dots: 14) {
            problems.append("14 days with today counted fit all 14 dots but were called partial")
        }
        if !StreakStatus.outrunsDots(streak: 15, todayCounts: true, dots: 14) {
            problems.append("15 days outrun 14 dots but were not called partial")
        }
        return problems
    }

    static func stripHelpCarriesSession() -> [String] {
        var problems: [String] = []
        let full = StoryShapeChart.help(shape: "You switched apps 4 times.", gap: "Nothing was recorded for 5m.")
        if full.map(\.name) != ["Blue blocks", "Hatched", "This session"]
            || full.last?.text != "You switched apps 4 times. Nothing was recorded for 5m." {
            problems.append("the strip's info read \(full.map(\.text))")
        }
        if StoryShapeChart.help(shape: nil, gap: nil).map(\.name) != ["Blue blocks", "Hatched"] {
            problems.append("a session with nothing to add still had a This session entry")
        }
        return problems
    }

    static func timeOfDayBlocks() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: SelfTest.base)
        func at(_ hours: Double) -> Date { midnight.addingTimeInterval(hours * 3_600) }
        func segment(_ id: String, _ name: String, _ from: Double, _ to: Double) -> TimelineSegment {
            TimelineSegment(id: UUID(), bundleID: id, appName: name, start: at(from), end: at(to))
        }
        let segments = [segment("a.claude", "Claude", 0.5, 2.5), segment("a.dia", "Dia", 2.5, 2.75),
                        segment("a.xcode", "Xcode", 9, 10)]
        let blocks = Rhythm.blocks(segments: segments, day: midnight, now: at(10), calendar: calendar) { block in
            block.start == at(0) ? 3_600 : block.start == at(9) ? 3 * 3_600 : 0
        }
        guard blocks.count == 8 else { return ["expected 8 blocks, got \(blocks.count)"] }
        if blocks[0].seconds != 2.25 * 3_600 || blocks[0].focusSeconds != 3_600 || blocks[0].topAppName != "Claude" {
            problems.append("midnight block read \(blocks[0])")
        }
        if blocks[3].focusSeconds != 3_600 {
            problems.append("focus was not capped at the block's app use: \(blocks[3].focusSeconds)")
        }
        if blocks.filter(\.isAhead).count != 4 || blocks[3].isAhead {
            problems.append("blocks ahead of 10 am were \(blocks.filter(\.isAhead).map(\.start))")
        }
        let expected = "Most focus \(DateFormats.hourLabel(at(0)))–\(DateFormats.hourLabel(at(3))) · Claude"
        if TimeOfDayChart.headline(blocks) != expected {
            problems.append("the headline read \(TimeOfDayChart.headline(blocks) ?? "nothing"), not \(expected)")
        }
        let unfocused = Rhythm.blocks(segments: segments, day: midnight, now: at(10), calendar: calendar) { _ in 0 }
        if TimeOfDayChart.headline(unfocused)?.hasPrefix("Most app use") != true {
            problems.append("a day without focus did not name its busiest block")
        }
        if TimeOfDayChart.headline(Rhythm.blocks(segments: [], day: midnight, now: at(10)) { _ in 0 }) != nil {
            problems.append("an empty day still had a headline")
        }
        return problems
    }
}
