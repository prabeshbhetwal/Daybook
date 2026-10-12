import Foundation

/// A skipped midnight must not lengthen a day or leave subsequent day keys at 01:00.
enum MidnightDayChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Day bounds end at the next day's start after a skipped midnight", dayBounds),
        ("History preserves both days of focus and app use after a skipped midnight", history),
        ("Streaks and week bars retain days before a skipped midnight", streaks),
        ("Period charts and app logs retain canonical day keys after a skipped midnight", periods),
    ]

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Santiago")!
        return calendar.forPeriods
    }

    private static func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2023, month: 9, day: day, hour: hour))!
    }

    private static func record() -> SessionRecord {
        SessionRecord(name: "Midnight fixture", workType: .deepWork,
                      start: date(3), end: date(4), workSeconds: 86_400)
    }

    private static func usage() -> AppUsageSession {
        AppUsageSession(bundleID: "test.midnight", appName: "Midnight fixture",
                        start: date(3), end: date(4))
    }

    private static func archives(now: Date) -> (SessionArchive, AppUsageArchive) {
        let directory = SelfTest.scratchDirectory()
        let sessions = SessionArchive(directory: directory, calendar: calendar, now: { now })
        let apps = AppUsageArchive(directory: directory, calendar: calendar, now: { now })
        sessions.append(record())
        apps.record(usage())
        return (sessions, apps)
    }

    private static func dayBounds() -> [String] {
        var problems: [String] = []
        let start = calendar.startOfDay(for: date(3))
        let end = calendar.startOfDay(for: date(4))
        expect(calendar.component(.hour, from: start) == 1,
               "the transition fixture must begin at 01:00", &problems)
        expect(SessionRecord.dayBounds(date(3), calendar: calendar)?.end == end,
               "the transition day must end at the following 00:00", &problems)
        expect(record().workSeconds(on: date(3), calendar: calendar) == 43_200,
               "the first day must contain twelve hours", &problems)
        let (sessions, apps) = archives(now: date(3))
        let dashboard = DashboardStats(sessions: sessions, usage: apps,
                                       calendar: calendar, now: { date(3) })
        expect(dashboard.trackedTotal(for: date(3)) == 43_200,
               "the dashboard must not take an hour from the following day", &problems)
        expect(apps.totalToday() == 43_200,
               "the popover must use the same twelve-hour slice", &problems)
        return problems
    }

    private static func history() -> [String] {
        var problems: [String] = []
        let days = HistoryStats.build(sessionRecords: [record()], usage: [usage()], calendar: calendar).days
        expect(days.count == 2, "both days must survive; got \(days.count)", &problems)
        expect(days.allSatisfy { $0.date == calendar.startOfDay(for: $0.date) },
               "History keys must be canonical day starts", &problems)
        expect(days.allSatisfy { $0.focused == 43_200 && $0.tracked == 43_200 },
               "each day must retain twelve hours: \(days)", &problems)
        expect(days.reduce(0) { $0 + $1.focused } == 86_400,
               "History must preserve the record's total", &problems)
        return problems
    }

    private static func streaks() -> [String] {
        var problems: [String] = []
        let sessions = SessionArchive(directory: SelfTest.scratchDirectory(),
                                      calendar: calendar, now: { date(3) })
        for day in 1...3 {
            sessions.append(SessionRecord(name: "Streak fixture", workType: .deepWork,
                start: date(day), end: date(day).addingTimeInterval(1_800), workSeconds: 1_800))
        }
        expect(sessions.currentStreak() == 3,
               "the skipped midnight must not erase earlier streak days", &problems)
        let bars = sessions.weekBars()
        expect(bars.suffix(3).allSatisfy { $0.minutes == 30 },
               "the last three bars must each show thirty minutes: \(bars)", &problems)
        expect(bars.allSatisfy { $0.id == calendar.startOfDay(for: $0.id) },
               "week bars must use canonical day starts", &problems)
        return problems
    }

    private static func periods() -> [String] {
        var problems: [String] = []
        let (sessions, apps) = archives(now: date(5))
        let stats = PeriodStats(sessions: sessions, usage: apps,
                                calendar: calendar, now: { date(5) })
        expect(stats.bounds(for: .day, containing: date(3)).end == calendar.startOfDay(for: date(4)),
               "a day period must end at the following midnight", &problems)
        let rollup = stats.rollup(for: .month, containing: date(3))
        expect(rollup.days.allSatisfy { $0.date == calendar.startOfDay(for: $0.date) },
               "period bars must use canonical day starts", &problems)
        expect(rollup.entriesByDay.keys.allSatisfy { $0 == calendar.startOfDay(for: $0) },
               "period log keys must use canonical day starts", &problems)
        expect(rollup.summary.tracked == 86_400,
               "period tracked time must preserve twenty-four hours; got \(rollup.summary.tracked)", &problems)
        let days = stats.days(for: .month, containing: date(3))
        expect(days == rollup.days, "standalone days and the rollup must agree", &problems)
        for group in rollup.exactAppGroups {
            let totals = group.dailyTotals(from: date(3), to: date(4), calendar: calendar)
            expect(totals.count == 2 && totals.reduce(0) { $0 + $1.seconds } == 86_400,
                   "app daily totals must retain both twelve-hour days: \(totals)", &problems)
        }
        return problems
    }
}
