import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    /// An active day contributes a zero when all of its focused work is later
    /// than today's clock time. Filtering it out would turn [30m, 30m, 0m]
    /// into a two-day history and suppress the valid 30-minute median.
    static func testHistoricalPaceKeepsZeroCutoffSamples() -> [String] {
        var problems: [String] = []
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
            var components = DateComponents()
            components.calendar = calendar
            components.timeZone = calendar.timeZone
            components.year = year
            components.month = month
            components.day = day
            components.hour = hour
            return calendar.date(from: components) ?? base
        }
        let current = date(2024, 1, 10, 10)
        let clock = TestClock(current)
        let directory = scratchDirectory()
        let archive = SessionArchive(directory: directory, calendar: calendar, now: { clock.value })
        var usage: [AppUsageSession] = []

        func add(_ day: Date, hour: Int, minutes: Int) {
            let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
            let duration = TimeInterval(minutes * 60)
            archive.append(SessionRecord(name: "S", workType: .deepWork,
                                         start: start, end: start.addingTimeInterval(duration),
                                         workSeconds: duration))
            usage.append(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                         start: start, end: start.addingTimeInterval(duration)))
        }

        // The first complete authoritative day is 7 January. Its 11am work is
        // active for the day but contributes 0 by the 10am comparison cutoff.
        add(date(2024, 1, 7), hour: 11, minutes: 30)
        add(date(2024, 1, 8), hour: 9, minutes: 30)
        add(date(2024, 1, 9), hour: 9, minutes: 30)
        let accurateFrom = date(2024, 1, 6, 14)
        let pace = DailyGoal(archive: archive, goal: 4 * 3_600, usage: usage,
                             usageAccurateFrom: accurateFrom, calendar: calendar,
                             now: { clock.value }).typical()
        expectClose(pace ?? -1, 30 * 60,
                    "three active days with [30m, 30m, 0m] by the cutoff have a 30m median",
                    &problems)

        let zeroDirectory = scratchDirectory()
        let zeroArchive = SessionArchive(directory: zeroDirectory, calendar: calendar,
                                         now: { clock.value })
        var zeroUsage: [AppUsageSession] = []
        for day in [date(2024, 1, 7), date(2024, 1, 8), date(2024, 1, 9)] {
            let start = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: day) ?? day
            zeroArchive.append(SessionRecord(name: "S", workType: .deepWork,
                                             start: start, end: start.addingTimeInterval(30 * 60),
                                             workSeconds: 30 * 60))
            zeroUsage.append(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                              start: start, end: start.addingTimeInterval(30 * 60)))
        }
        let zeroPace = DailyGoal(archive: zeroArchive, goal: 4 * 3_600, usage: zeroUsage,
                                 usageAccurateFrom: accurateFrom, calendar: calendar,
                                 now: { clock.value }).typical()
        expect(zeroPace != nil, "three active zero-cutoff samples remain a real median", &problems)
        expectClose(zeroPace ?? -1, 0, "a valid all-zero cutoff median is reported", &problems)

        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.removeItem(at: zeroDirectory)
        return problems
    }

    /// Historical days must use the same local hour/minute/second as now, not
    /// elapsed seconds since midnight. This pins spring-forward's missing time
    /// to the next valid time and prevents a late cutoff spilling into tomorrow.
    static func testHistoricalPaceDSTCutoffs() -> [String] {
        var problems: [String] = []
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            var components = DateComponents()
            components.calendar = calendar
            components.timeZone = calendar.timeZone
            components.year = year
            components.month = month
            components.day = day
            components.hour = hour
            components.minute = minute
            return calendar.date(from: components) ?? base
        }
        func add(_ archive: SessionArchive, _ usage: inout [AppUsageSession],
                 day: Date, hour: Int, minutes: Int) {
            let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
            let duration = TimeInterval(minutes * 60)
            archive.append(SessionRecord(name: "S", workType: .deepWork,
                                         start: start, end: start.addingTimeInterval(duration),
                                         workSeconds: duration))
            usage.append(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                         start: start, end: start.addingTimeInterval(duration)))
        }

        // 02:30 does not exist on 10 March 2024. The historical cutoff is the
        // next valid local time (03:00), so the 03:00-03:30 work is excluded.
        let springCurrent = date(2024, 3, 12, 2, 30)
        let springClock = TestClock(springCurrent)
        let springDirectory = scratchDirectory()
        let springArchive = SessionArchive(directory: springDirectory, calendar: calendar,
                                           now: { springClock.value })
        var springUsage: [AppUsageSession] = []
        add(springArchive, &springUsage, day: date(2024, 3, 9, 0), hour: 1, minutes: 10)
        add(springArchive, &springUsage, day: date(2024, 3, 10, 0), hour: 1, minutes: 30)
        add(springArchive, &springUsage, day: date(2024, 3, 10, 0), hour: 3, minutes: 30)
        add(springArchive, &springUsage, day: date(2024, 3, 11, 0), hour: 1, minutes: 50)
        let accurateFrom = date(2024, 3, 8, 14)
        let springPace = DailyGoal(archive: springArchive, goal: 4 * 3_600,
                                   usage: springUsage, usageAccurateFrom: accurateFrom,
                                   calendar: calendar, now: { springClock.value }).typical()
        expectClose(springPace ?? -1, 30 * 60,
                    "spring-forward uses the next valid 03:00 cutoff, not elapsed 03:30",
                    &problems)

        // A 23:30 cutoff on the 23-hour spring-forward day must end at 23:30,
        // never at 00:30 on 11 March where this distinct 50-minute record sits.
        let lateCurrent = date(2024, 3, 13, 23, 30)
        let lateClock = TestClock(lateCurrent)
        let lateDirectory = scratchDirectory()
        let lateArchive = SessionArchive(directory: lateDirectory, calendar: calendar,
                                         now: { lateClock.value })
        var lateUsage: [AppUsageSession] = []
        add(lateArchive, &lateUsage, day: date(2024, 3, 10, 0), hour: 12, minutes: 30)
        add(lateArchive, &lateUsage, day: date(2024, 3, 11, 0), hour: 0, minutes: 50)
        add(lateArchive, &lateUsage, day: date(2024, 3, 12, 0), hour: 12, minutes: 40)
        let latePace = DailyGoal(archive: lateArchive, goal: 4 * 3_600,
                                 usage: lateUsage, usageAccurateFrom: accurateFrom,
                                 calendar: calendar, now: { lateClock.value }).typical()
        expectClose(latePace ?? -1, 40 * 60,
                    "a spring-forward day cutoff never spills into the next local day",
                    &problems)

        // 01:30 occurs twice on 3 November. The first occurrence is the
        // controller-selected cutoff, so work in the second occurrence remains
        // after the comparison point.
        let fallCurrent = date(2024, 11, 5, 1, 30)
        let fallClock = TestClock(fallCurrent)
        let fallDirectory = scratchDirectory()
        let fallArchive = SessionArchive(directory: fallDirectory, calendar: calendar,
                                         now: { fallClock.value })
        var fallUsage: [AppUsageSession] = []
        add(fallArchive, &fallUsage, day: date(2024, 11, 2, 0), hour: 0, minutes: 10)
        let fallDay = date(2024, 11, 3, 0)
        var repeated = DateComponents()
        repeated.hour = 1
        let secondOneAM = calendar.nextDate(
            after: calendar.startOfDay(for: fallDay).addingTimeInterval(-1),
            matching: repeated, matchingPolicy: .nextTime,
            repeatedTimePolicy: .last, direction: .forward) ?? fallDay
        fallArchive.append(SessionRecord(name: "S", workType: .deepWork,
                                         start: secondOneAM,
                                         end: secondOneAM.addingTimeInterval(30 * 60),
                                         workSeconds: 30 * 60))
        fallUsage.append(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                         start: secondOneAM,
                                         end: secondOneAM.addingTimeInterval(30 * 60)))
        add(fallArchive, &fallUsage, day: date(2024, 11, 4, 0), hour: 0, minutes: 50)
        let fallPace = DailyGoal(archive: fallArchive, goal: 4 * 3_600,
                                 usage: fallUsage,
                                 usageAccurateFrom: date(2024, 11, 1, 14),
                                 calendar: calendar, now: { fallClock.value }).typical()
        expectClose(fallPace ?? -1, 10 * 60,
                    "fall-back uses the first 01:30 occurrence as its cutoff",
                    &problems)

        try? FileManager.default.removeItem(at: springDirectory)
        try? FileManager.default.removeItem(at: lateDirectory)
        try? FileManager.default.removeItem(at: fallDirectory)
        return problems
    }
}
