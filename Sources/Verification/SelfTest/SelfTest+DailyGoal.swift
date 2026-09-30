import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    /// The daily goal must judge "on track" against the user's own recent
    /// history at this same hour, not against the clock or the raw target.
    static func testDailyGoal() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let dir = scratchDirectory()
        let archive = SessionArchive(directory: dir, now: { clock.value })
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: base)
        let current = dayStart.addingTimeInterval(10 * 3_600)   // "now" is 10am
        clock.value = current
        let usageAccurateFrom = calendar.date(byAdding: .day, value: -15, to: current) ?? current

        func addDay(offset: Int, hours: Double) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: current) else {
                return
            }
            let start = calendar.startOfDay(for: day).addingTimeInterval(9 * 3_600)
            archive.append(SessionRecord(name: "s", workType: .deepWork,
                                         start: start, end: start.addingTimeInterval(hours * 3_600),
                                         workSeconds: hours * 3_600))
        }

        let todayStart = dayStart.addingTimeInterval(9 * 3_600)
        archive.append(SessionRecord(name: "s", workType: .deepWork,
                                     start: todayStart, end: todayStart.addingTimeInterval(3_600),
                                     workSeconds: 3_600))
        // The goal is the intersection of "a session ran" and "you were at the
        // keyboard", so the fixture has to supply both halves. Without the
        // hands-on side it reads zero — correctly, since an archived session
        // with no record of anyone using the machine is not evidence of work.
        let handsOn = [AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                       start: todayStart,
                                       end: todayStart.addingTimeInterval(3_600))]

        // Only two active days in history — below the 3-day minimum.
        addDay(offset: 1, hours: 0.5)
        addDay(offset: 2, hours: 0.5)

        let underGoal = DailyGoal(archive: archive, goal: 2 * 3_600,
                                  usage: handsOn, usageAccurateFrom: usageAccurateFrom,
                                  now: { clock.value }).progress()
        expectClose(underGoal.achieved, 3_600, "under-goal achieved", &problems)
        expectClose(underGoal.share, 0.5, "under-goal share", &problems)
        expect(!underGoal.isMet, "1h against a 2h goal should not be met", &problems)
        expect(underGoal.typicalByNow == nil, "two active days is below the minimum", &problems)
        expect(underGoal.aheadBy == nil, "aheadBy must be nil when typicalByNow is nil", &problems)

        // An archived session with no hands-on time behind it fills nothing —
        // the rule that stops a wall-clock session from claiming a goal.
        let unattended = DailyGoal(archive: archive, goal: 2 * 3_600,
                                   usageAccurateFrom: usageAccurateFrom,
                                   now: { clock.value }).progress()
        expectClose(unattended.achieved, 0,
                    "a session nobody was present for fills no goal", &problems)

        let overGoal = DailyGoal(archive: archive, goal: 1_800,
                                 usage: handsOn, usageAccurateFrom: usageAccurateFrom,
                                 now: { clock.value }).progress()
        expectClose(overGoal.share, 2.0, "over-goal share is uncapped", &problems)
        expect(overGoal.isMet, "1h against a 30m goal should be met", &problems)

        try? FileManager.default.removeItem(at: dir)

        // Five active days with a clean median, plus two inactive days inside
        // the same window that must not drag the median down.
        let dir2 = scratchDirectory()
        let archive2 = SessionArchive(directory: dir2, now: { clock.value })
        var historyUsage2: [AppUsageSession] = []
        let todayStart2 = dayStart.addingTimeInterval(9 * 3_600)
        archive2.append(SessionRecord(name: "s", workType: .deepWork,
                                      start: todayStart2, end: todayStart2.addingTimeInterval(3_600),
                                      workSeconds: 3_600))

        func addDay2(offset: Int, minutesByNow: Double) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: current) else {
                return
            }
            let start = calendar.startOfDay(for: day).addingTimeInterval(9 * 3_600)
            archive2.append(SessionRecord(name: "s", workType: .deepWork,
                                          start: start,
                                          end: start.addingTimeInterval(minutesByNow * 60),
                                          workSeconds: minutesByNow * 60))
            historyUsage2.append(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                                  start: start,
                                                  end: start.addingTimeInterval(minutesByNow * 60)))
        }
        // Active days at offsets 1-5 reach 10, 50, 30, 40, 20 minutes by 10am;
        // sorted that is 10/20/30/40/50 so the median is 30 minutes. Offsets 6
        // and 7 (inside the 14-day window) are left with no records at all —
        // if they were folded in as zeros the median would drop to 20 minutes
        // instead of staying at 30, so this assertion also covers that rule.
        addDay2(offset: 1, minutesByNow: 10)
        addDay2(offset: 2, minutesByNow: 50)
        addDay2(offset: 3, minutesByNow: 30)
        addDay2(offset: 4, minutesByNow: 40)
        addDay2(offset: 5, minutesByNow: 20)

        let handsOn2 = [AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                        start: todayStart2,
                                        end: todayStart2.addingTimeInterval(3_600))]
        let goal2 = DailyGoal(archive: archive2, goal: 3_600,
                              usage: handsOn2 + historyUsage2,
                              usageAccurateFrom: usageAccurateFrom,
                              now: { clock.value }).progress()
        expect(goal2.typicalByNow != nil, "five active days should be enough for a median",
               &problems)
        if let typical = goal2.typicalByNow {
            expectClose(typical, 30 * 60, "median of five active days", &problems)
        }
        expect(goal2.aheadBy != nil, "aheadBy should exist once typicalByNow exists", &problems)
        if let ahead = goal2.aheadBy {
            expectClose(ahead, 3_600 - 30 * 60, "aheadBy is achieved minus the median", &problems)
        }

        try? FileManager.default.removeItem(at: dir2)
        return problems
    }

    /// Historical pace must describe the same proved work as today's goal:
    /// session time intersected with hands-on usage, not a session's full span.
    /// Before the reconciliation, this fixture reported a raw two-hour median
    /// instead of the one authoritative focused-active hour.
    static func testHistoricalPaceUsesFocusedActiveTime() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let directory = scratchDirectory()
        let archive = SessionArchive(directory: directory, now: { clock.value })
        let calendar = Calendar.current
        let current = calendar.startOfDay(for: base).addingTimeInterval(10 * 3_600)
        clock.value = current
        var usage: [AppUsageSession] = []

        func addDay(offset: Int, startingAt startHour: Double, usageStartsAt usageHour: Double) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: current) else { return }
            let start = calendar.startOfDay(for: day).addingTimeInterval(startHour * 3_600)
            archive.append(SessionRecord(name: "S", workType: .deepWork,
                                         start: start, end: start.addingTimeInterval((10 - startHour) * 3_600),
                                         workSeconds: (10 - startHour) * 3_600))
            usage.append(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                         start: calendar.startOfDay(for: day)
                                             .addingTimeInterval(usageHour * 3_600),
                                         end: calendar.startOfDay(for: day)
                                             .addingTimeInterval(10 * 3_600)))
        }

        // The day before migration and the migration day have both enough
        // activity to influence a raw median, but neither has a uniform
        // checkpoint guarantee and must be excluded.
        addDay(offset: 5, startingAt: 5, usageStartsAt: 5)
        addDay(offset: 4, startingAt: 5, usageStartsAt: 5)
        // `accurateFrom` lies in offset 4, so offsets 3 through 1 are the
        // first eligible complete days. Each has two session hours but only
        // one hour of usage inside the same cutoff.
        addDay(offset: 2, startingAt: 8, usageStartsAt: 9)
        addDay(offset: 1, startingAt: 8, usageStartsAt: 9)
        let migrationDay = calendar.date(byAdding: .day, value: -4, to: current) ?? current
        let accurateFrom = calendar.startOfDay(for: migrationDay).addingTimeInterval(14 * 3_600)
        func typical() -> TimeInterval? {
            DailyGoal(archive: archive, goal: 4 * 3_600, usage: usage,
                      usageAccurateFrom: accurateFrom, now: { clock.value }).typical()
        }

        expect(typical() == nil,
               "pre-epoch and migration-day records cannot satisfy the three-day minimum",
               &problems)

        addDay(offset: 3, startingAt: 8, usageStartsAt: 9)
        let result = typical()
        expectClose(result ?? 0, 3_600,
                    "two session hours with one usage hour contribute one historical hour",
                    &problems)

        try? FileManager.default.removeItem(at: directory)
        return problems
    }
}
