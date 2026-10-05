import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    /// Insights may describe only facts already established by canonical Core
    /// helpers. Missing inputs stay absent rather than becoming zero-valued
    /// prose, and secondary range navigation is earned by two evidenced ranges.
    static func testInsightSurfaceRequiresEvidence() -> [String] {
        var problems: [String] = []
        let emptyGoal = GoalProgress(goal: 4 * 3_600, achieved: 0, typical: nil)
        let emptyQuality = FocusQuality(byWorkType: [], insideSessionShare: 0,
                                        switchesPerSession: 0, sessionCount: 0)
        let empty = InsightSurface.make(
            range: .week,
            goal: emptyGoal,
            rhythm: [],
            rhythmPeak: nil,
            quality: emptyQuality,
            streak: 0,
            activeDays: 0,
            totalDays: 7,
            tracked: 0,
            comparableTracked: nil)

        expect(!empty.hasEvidence,
               "first-run Insights has no statements", &problems)
        expect([empty.pace, empty.rhythm, empty.quality, empty.continuity]
                .compactMap { $0 }.isEmpty,
               "missing evidence remains absent rather than rendering zero", &problems)
        expect(InsightSurface.insufficientEvidenceCopy
                   == "Keep using Daybook; patterns appear once there is enough comparable history.",
               "first-run copy explains how evidence becomes available", &problems)

        let zeroHour = RhythmHour(hour: base, seconds: 0, colorIndex: 6)
        let zeroRhythm = InsightSurface.make(
            range: .week,
            goal: emptyGoal,
            rhythm: [zeroHour],
            rhythmPeak: "9am",
            quality: emptyQuality,
            streak: 0,
            activeDays: 0,
            totalDays: 7,
            tracked: 0,
            comparableTracked: nil)
        expect(zeroRhythm.rhythm == nil && !zeroRhythm.hasEvidence,
               "Rhythm requires at least one non-zero canonical hour", &problems)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let today = calendar.startOfDay(for: base)
        let current = today.addingTimeInterval(10 * 3_600)
        let clock = TestClock(current)
        let archive = SessionArchive(directory: scratchDirectory(), calendar: calendar,
                                     now: { clock.value })
        var usage: [AppUsageSession] = []
        for offset in 1...3 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return problems + ["could not build authoritative Insights pace history"]
            }
            let start = day.addingTimeInterval(9 * 3_600)
            let seconds = TimeInterval((15 + offset * 15) * 60)
            archive.append(SessionRecord(name: "Focus", workType: .deepWork,
                                         start: start,
                                         end: start.addingTimeInterval(seconds),
                                         workSeconds: seconds))
            usage.append(AppUsageSession(bundleID: "org.example.editor", appName: "Editor",
                                         start: start,
                                         end: start.addingTimeInterval(seconds)))
        }
        let todayStart = today.addingTimeInterval(9 * 3_600)
        archive.append(SessionRecord(name: "Focus", workType: .deepWork,
                                     start: todayStart,
                                     end: todayStart.addingTimeInterval(60 * 60),
                                     workSeconds: 60 * 60))
        usage.append(AppUsageSession(bundleID: "org.example.editor", appName: "Editor",
                                     start: todayStart,
                                     end: todayStart.addingTimeInterval(60 * 60)))
        guard let migrationDay = calendar.date(byAdding: .day, value: -4, to: today) else {
            return problems + ["could not build the Insights accuracy epoch"]
        }
        let goal = DailyGoal(
            archive: archive,
            goal: 4 * 3_600,
            usage: usage,
            usageAccurateFrom: migrationDay.addingTimeInterval(12 * 3_600),
            calendar: calendar,
            now: { clock.value }).progress()
        expect(goal.typicalByNow != nil,
               "three authoritative active days establish the DailyGoal median", &problems)

        let pace = InsightSurface.make(
            range: .week,
            goal: goal,
            rhythm: [],
            rhythmPeak: nil,
            quality: emptyQuality,
            streak: 0,
            activeDays: 0,
            totalDays: 7,
            tracked: 0,
            comparableTracked: nil)
        expect(pace.pace != nil && pace.hasEvidence,
               "the established personal median permits a Pace statement", &problems)
        expect(pace.rhythm == nil && pace.quality == nil && pace.continuity == nil,
               "Pace does not manufacture the other three groups", &problems)

        let evidenced = InsightSurface.make(
            range: .month,
            goal: emptyGoal,
            rhythm: [RhythmHour(hour: base, seconds: 45 * 60, colorIndex: 0)],
            rhythmPeak: "9am",
            quality: FocusQuality(
                byWorkType: [WorkTypeShare(workType: .deepWork,
                                           seconds: 2 * 3_600, share: 1)],
                insideSessionShare: 0.6,
                switchesPerSession: 2,
                sessionCount: 2),
            streak: 2,
            activeDays: 4,
            totalDays: 31,
            tracked: 5 * 3_600,
            comparableTracked: 4 * 3_600)
        expect(evidenced.rhythm != nil && evidenced.quality != nil
                   && evidenced.continuity != nil,
               "present Rhythm, Focus quality and Continuity facts render", &problems)
        let written = [pace.pace, evidenced.rhythm, evidenced.quality, evidenced.continuity]
            .compactMap { $0 }
            .flatMap { [$0.headline, $0.detail] }
        expect(written.allSatisfy {
            !$0.hasPrefix("0m") && !$0.contains(" 0m")
                && !$0.hasPrefix("0%") && !$0.contains(" 0%")
        },
               "evidenced copy never substitutes a missing value with zero", &problems)

        expect(!InsightSurface.showsRangeSelector(week: pace, month: empty),
               "one evidenced range does not expose a selector", &problems)
        expect(!InsightSurface.showsRangeSelector(week: pace, month: evidenced),
               "global Pace alone does not expose a selector with no Week period fact",
               &problems)
        let evidencedWeek = InsightSurface.make(
            range: .week,
            goal: emptyGoal,
            rhythm: [RhythmHour(hour: base, seconds: 45 * 60, colorIndex: 0)],
            rhythmPeak: "9am",
            quality: emptyQuality,
            streak: 0,
            activeDays: 2,
            totalDays: 7,
            tracked: 2 * 3_600,
            comparableTracked: nil)
        expect(InsightSurface.showsRangeSelector(week: evidencedWeek, month: evidenced),
               "Week and Month selection appears only when both have evidence", &problems)

        let usageArchive = makeUsageArchive(
            clock,
            sessions: usage,
            accurateFrom: migrationDay.addingTimeInterval(12 * 3_600))
        let persistence = PersistenceStore(
            defaults: UserDefaults(suiteName: suiteName) ?? .standard)
        persistence.removeAll()
        let engine = SessionEngine(store: persistence, archive: archive,
                                   ownBundleID: "com.example.self", schedulesDwell: false,
                                   now: { clock.value })
        let tracker = AppUsageTracker(archive: usageArchive,
                                      ownBundleID: "com.example.self",
                                      idle: .disabled,
                                      now: { clock.value })
        let store = SessionStore(engine: engine, now: { clock.value })
        store.attach(tracker: tracker, usage: usageArchive)
        store.refreshInsights()
        expect(store.insightWeekSurface.pace != nil
                   && store.insightMonthSurface.pace != nil,
               "SessionStore composes both ranges from the canonical DailyGoal evidence",
               &problems)
        expect(store.insightSurface(for: .week) == store.insightWeekSurface,
               "the requested evidenced range is the surface selected for presentation",
               &problems)
        store.insightWeekSurface = pace
        store.insightMonthSurface = evidenced
        expect(store.insightSurface(for: .week) == pace,
               "each explicit Insights scope keeps its own evidence", &problems)

        var boundaryComponents = DateComponents()
        boundaryComponents.calendar = Calendar.current
        boundaryComponents.timeZone = Calendar.current.timeZone
        boundaryComponents.year = 2024
        boundaryComponents.month = 3
        boundaryComponents.day = 31
        boundaryComponents.hour = 12
        guard let monthBoundary = Calendar.current.date(from: boundaryComponents),
              let previousMonthDay = Calendar.current.date(
                byAdding: .month, value: -1, to: monthBoundary),
              let accurateFrom = Calendar.current.date(
                byAdding: .month, value: -3, to: monthBoundary) else {
            return problems + ["could not build unequal-month Insights boundaries"]
        }
        let boundaryClock = TestClock(monthBoundary)
        let currentStart = Calendar.current.startOfDay(for: monthBoundary)
            .addingTimeInterval(9 * 3_600)
        let previousStart = Calendar.current.startOfDay(for: previousMonthDay)
            .addingTimeInterval(9 * 3_600)
        let boundaryUsage = makeUsageArchive(
            boundaryClock,
            sessions: [
                AppUsageSession(bundleID: "org.example.current", appName: "Current",
                                start: currentStart,
                                end: currentStart.addingTimeInterval(3_600)),
                AppUsageSession(bundleID: "org.example.previous", appName: "Previous",
                                start: previousStart,
                                end: previousStart.addingTimeInterval(3_600))
            ],
            accurateFrom: accurateFrom)
        let boundaryPersistence = PersistenceStore(
            defaults: UserDefaults(suiteName: suiteName) ?? .standard)
        boundaryPersistence.removeAll()
        let boundaryEngine = SessionEngine(
            store: boundaryPersistence,
            archive: makeArchive(boundaryClock),
            ownBundleID: "com.example.self",
            schedulesDwell: false,
            now: { boundaryClock.value })
        let boundaryTracker = AppUsageTracker(
            archive: boundaryUsage,
            ownBundleID: "com.example.self",
            idle: .disabled,
            now: { boundaryClock.value })
        let boundaryStore = SessionStore(engine: boundaryEngine,
                                         now: { boundaryClock.value })
        boundaryStore.attach(tracker: boundaryTracker, usage: boundaryUsage)
        boundaryStore.refreshInsights()
        expect(boundaryStore.insightMonthSurface.continuity?.detail
                   .contains("like-for-like previous period") != true,
               "a month with no corresponding previous-month day has no comparison",
               &problems)
        return problems
    }
}
