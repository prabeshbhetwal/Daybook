import Foundation

/// One archive over four days with several categories and Break, and every figure that is meant to count
/// focus read off it: daily totals, session counts, streaks, the goal's credit, the dashboard and History.
/// "Reading" is the category of the person's own whose focus setting the checks vary.
enum FocusPropertyFixture {
    static let calendar = SelfTest.gregorian
    static let reading = WorkType(rawValue: "custom.reading")
    static let readingGoal: TimeInterval = 3_600

    /// What is read off the fixture, newest day first (today, then one, two and three days back).
    struct Figures: Equatable {
        var dayTotals: [TimeInterval]
        var sessions: [Int]
        var currentStreak: Int
        var bestStreak: Int
        var goalCredit: [TimeInterval]
        var dashboardSessions: [Int]
        var dashboardSeconds: [TimeInterval]
        var historyFocused: [TimeInterval]
        var historySessions: [Int]
        var historyRowFocused: [TimeInterval]
        var historyMainType: [String]
        var readingGoal: String
        var categoryGoalItems: Int
    }

    /// Each figure that differs, as a sentence.
    static func differences(_ actual: Figures, _ expected: Figures) -> [String] {
        zip(Mirror(reflecting: actual).children, Mirror(reflecting: expected).children).compactMap { pair in
            let (got, want) = pair
            return "\(got.value)" == "\(want.value)" ? nil : "\(got.label ?? "?") was \(got.value), expected \(want.value)"
        }
    }

    static func day(_ offset: Int) -> Date {
        let today = calendar.startOfDay(for: SelfTest.base)
        return calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }

    static func at(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day(offset)) ?? day(offset)
    }

    private static func record(_ type: WorkType, day offset: Int, hour: Int, minutes: Int) -> SessionRecord {
        let start = at(offset, hour)
        return SessionRecord(name: type.rawValue, workType: type, start: start,
                             end: start.addingTimeInterval(Double(minutes) * 60),
                             workSeconds: Double(minutes) * 60,
                             breakOrigin: type == .breakTime ? .started : nil)
    }

    /// Today: two hours of Deep work and an hour of Learning, then a Break. One day back: half an hour of
    /// Meetings and an hour of Reading. Two back: half an hour of Deep work beside a two-hour Break. Three
    /// back: two hours of Admin.
    static func records() -> [SessionRecord] {
        [record(.deepWork, day: 0, hour: 9, minutes: 120), record(.learning, day: 0, hour: 12, minutes: 60),
         record(.breakTime, day: 0, hour: 13, minutes: 30),
         record(.meetings, day: -1, hour: 9, minutes: 30), record(reading, day: -1, hour: 14, minutes: 60),
         record(.deepWork, day: -2, hour: 9, minutes: 30), record(.breakTime, day: -2, hour: 10, minutes: 120),
         record(.admin, day: -3, hour: 9, minutes: 120)]
    }

    /// Reading, with a daily goal, whether or not it counts toward focus.
    static func readingDefinition(_ configure: (inout WorkTypeDefinition) -> Void = { _ in }) -> WorkTypeDefinition {
        var definition = WorkTypeDefinition(id: reading.rawValue, name: "Reading", symbolName: "book.fill",
                                            hue: .green, dailyGoal: readingGoal)
        configure(&definition)
        return definition
    }

    /// Runs `body` with the shared catalogue holding `customisations`, then puts it back as shipped.
    static func withCatalogue<T>(_ customisations: [WorkTypeDefinition], _ body: () -> T) -> T {
        WorkTypeCatalog.shared.apply(customisations: customisations)
        defer { WorkTypeCatalog.shared.apply(customisations: []) }
        return body()
    }

    /// The figures, read with whatever the shared catalogue holds now.
    static func figures() -> Figures {
        let clock = TestClock(at(0, 19))
        let records = records()
        let archive = SelfTest.makeArchive(clock, records: records, calendar: calendar)
        archive.streakMinimum = 3_600
        let days = [0, -1, -2, -3]
        // The app is in front all day, so the goal's credit is the focus work and nothing else.
        let usage = days.map { AppUsageSession(bundleID: "test.focus", appName: "Focus fixture",
                                               start: at($0, 8), end: at($0, 18)) }
        let dashboard = DashboardStats(sessions: archive,
                                       usage: SelfTest.makeUsageArchive(clock, sessions: usage,
                                                                         accurateFrom: at(-4, 0)),
                                       calendar: calendar, now: { clock.value })
        let history = HistoryStats.build(sessionRecords: records, usage: usage, calendar: calendar).days
        let byDate = Dictionary(history.map { (calendar.startOfDay(for: $0.date), $0) },
                                uniquingKeysWith: { first, _ in first })
        let quality = days.map { dashboard.focusQuality(for: day($0)) }
        let rows = days.map { offset -> HistoryRow in
            let place = HistoryPlace(level: .day, span: DateInterval(start: day(offset), end: day(offset + 1)))
            return HistoryTreeBuilder.row(place, byDate: byDate, calendar: calendar)
        }
        return Figures(
            dayTotals: days.map { archive.workSeconds(on: day($0)) },
            sessions: days.map { archive.threadCount(on: day($0)) },
            currentStreak: archive.currentStreak(), bestStreak: archive.bestStreak(),
            goalCredit: days.map { FocusedActiveTime.seconds(on: day($0), records: records, usage: usage,
                                                             running: nil, calendar: calendar) },
            dashboardSessions: quality.map(\.sessionCount),
            dashboardSeconds: quality.map { $0.byWorkType.reduce(0) { $0 + $1.seconds } },
            historyFocused: days.map { byDate[day($0)]?.focused ?? -1 },
            historySessions: days.map { byDate[day($0)]?.sessions ?? -1 },
            historyRowFocused: rows.map(\.focused),
            historyMainType: rows.map { $0.mainWorkType?.rawValue ?? "none" },
            readingGoal: reading.dailyGoal.map { "\($0)" } ?? "none",
            categoryGoalItems: DailyGoalList.migrated(from: WorkTypeCatalog.shared.allDefinitions, into: []).count)
    }
}
