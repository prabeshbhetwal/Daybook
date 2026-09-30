import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    // MARK: - 29

    /// Reproduces the exact state from the reported screenshot: 42 minutes into a
    /// session with nothing completed. Every figure must agree.
    static func testRunningSessionCountsEverywhere() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let engine = makeEngine(clock)

        engine.start(workType: .deepWork, intent: "Refactor")
        clock.advance(42 * 60)

        expectClose(engine.todayTotal, 42 * 60, "today counts the running session", &problems)
        let streak = engine.archive.currentStreak(includingToday: engine.elapsed)
        expect(streak == 1, "42 minutes of live work should light the streak, got \(streak)",
               &problems)
        expect(engine.sessionsToday == 1,
               "the running session counts as one, got \(engine.sessionsToday)", &problems)
        expectClose(engine.longestToday, 42 * 60,
                    "longest today includes the running session", &problems)

        // Under the 25 minute bar the streak stays honest.
        let clock2 = TestClock(base)
        let engine2 = makeEngine(clock2)
        engine2.start(workType: .deepWork, intent: "Short")
        clock2.advance(10 * 60)
        expect(engine2.archive.currentStreak(includingToday: engine2.elapsed) == 0,
               "10 minutes must not light the streak", &problems)
        return problems
    }

    // MARK: - 30

    /// The Screen Time criticism applied to us: an app left frontmost while
    /// nobody is at the keyboard must not accrue time.
    static func testIdleTrimsUsage() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let dir = scratchDirectory()
        let usage = AppUsageArchive(directory: dir, now: { clock.value })
        var idle: TimeInterval = 0
        let tracker = AppUsageTracker(archive: usage,
                                      ownBundleID: FocusConstants.bundleIdentifier,
                                      idle: IdleMonitor(idleSeconds: { idle }),
                                      now: { clock.value })

        tracker.appActivated(bundleID: "com.a", name: "Alpha")
        clock.advance(3_600)          // an hour frontmost
        idle = 2_400                  // but the last 40 minutes had no input
        tracker.suspend()

        expectClose(usage.sessions.first?.seconds ?? -1, 1_200,
                    "idle time must not count as usage", &problems)

        // Below the cutoff nothing is trimmed: a pause to read is still work.
        let dir2 = scratchDirectory()
        let usage2 = AppUsageArchive(directory: dir2, now: { clock.value })
        var idle2: TimeInterval = 0
        let tracker2 = AppUsageTracker(archive: usage2,
                                       ownBundleID: FocusConstants.bundleIdentifier,
                                       idle: IdleMonitor(idleSeconds: { idle2 }),
                                       now: { clock.value })
        tracker2.appActivated(bundleID: "com.b", name: "Beta")
        clock.advance(600)
        idle2 = 60                    // a minute of reading, under the 180s cutoff
        tracker2.suspend()
        expectClose(usage2.sessions.first?.seconds ?? -1, 600,
                    "a short pause must not be trimmed", &problems)

        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.removeItem(at: dir2)
        return problems
    }

    // MARK: - 31

    static func testPreciseDurationAndConsistency() -> [String] {
        var problems: [String] = []

        // D-2: a 45-second stretch rendered as "0m" before this.
        expect(Tokens.preciseDuration(0) == "0s", "zero, got \(Tokens.preciseDuration(0))", &problems)
        expect(Tokens.preciseDuration(45) == "45s", "45s, got \(Tokens.preciseDuration(45))", &problems)
        expect(Tokens.preciseDuration(59) == "59s", "below a minute", &problems)
        expect(Tokens.preciseDuration(60) == "1m", "at a minute", &problems)
        expect(Tokens.preciseDuration(3_599) == "59m", "below an hour", &problems)
        expect(Tokens.preciseDuration(3_600) == "1h", "at an hour", &problems)
        expect(Tokens.preciseDuration(7_980) == "2h 13m", "hours and minutes", &problems)

        // D-1: "1 session today" and "No sessions yet today" must never disagree.
        let clock = TestClock(base)
        let usageDir = scratchDirectory(), sessionDir = scratchDirectory()
        let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
        let sessions = SessionArchive(directory: sessionDir, now: { clock.value })
        let dayStart = Calendar.current.startOfDay(for: base)
        usage.record(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                     start: dayStart.addingTimeInterval(9 * 3_600),
                                     end: dayStart.addingTimeInterval(10 * 3_600)))

        let stats = DashboardStats(sessions: sessions, usage: usage, now: { clock.value })
        let running = stats.focusQuality(for: base, runningSeconds: 2_520)
        expect(running.sessionCount == 1,
               "a running session counts, got \(running.sessionCount)", &problems)
        expect(!running.byWorkType.isEmpty,
               "the running session contributes to the work-type split", &problems)
        let idle = stats.focusQuality(for: base, runningSeconds: nil)
        expect(idle.sessionCount == 0, "no running session, no count", &problems)

        try? FileManager.default.removeItem(at: usageDir)
        try? FileManager.default.removeItem(at: sessionDir)
        return problems
    }

    // MARK: - 32

    static func testWindowSnappingAndStretches() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let usageDir = scratchDirectory(), sessionDir = scratchDirectory()
        let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: base)

        // D-3: four minutes of data must not produce a one-hour axis.
        usage.record(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                     start: dayStart.addingTimeInterval(9 * 3_600 + 120),
                                     end: dayStart.addingTimeInterval(9 * 3_600 + 360)))
        let stats = DashboardStats(sessions: SessionArchive(directory: sessionDir,
                                                            now: { clock.value }),
                                   usage: usage, now: { clock.value })
        guard let window = stats.timelineWindow(for: base) else {
            problems.append("a day with data must have a window")
            return problems
        }
        let span = window.end.timeIntervalSince(window.start)
        expect(span >= FocusConstants.minimumTimelineSpan,
               "minimum four-hour span, got \(span / 3_600)h", &problems)
        expect(calendar.component(.minute, from: window.start) == 0,
               "window start snaps to the hour", &problems)
        expect(calendar.component(.minute, from: window.end) == 0,
               "window end snaps to the hour", &problems)

        // Grouping, span and hover hit-testing.
        usage.record(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                     start: dayStart.addingTimeInterval(16 * 3_600),
                                     end: dayStart.addingTimeInterval(16 * 3_600 + 600)))
        let stretches = stats.stretches(for: base, bundleID: "com.a")
        expect(stretches.count == 2, "two stretches, got \(stretches.count)", &problems)
        guard let appSpan = stats.span(for: base, bundleID: "com.a") else {
            problems.append("an app with usage must have a span")
            return problems
        }
        expectClose(appSpan.end.timeIntervalSince(appSpan.start), 7 * 3_600 + 480,
                    "span runs first start to last end", &problems)

        let hit = stats.segment(at: dayStart.addingTimeInterval(9 * 3_600 + 180), on: base)
        expect(hit?.bundleID == "com.a", "hover inside a stretch finds it", &problems)
        expect(stats.segment(at: dayStart.addingTimeInterval(12 * 3_600), on: base) == nil,
               "hover over a gap finds nothing", &problems)

        expect(stats.earliestRecordedDay() != nil,
               "an archive with data reports an earliest day", &problems)

        try? FileManager.default.removeItem(at: usageDir)
        try? FileManager.default.removeItem(at: sessionDir)
        return problems
    }

    // MARK: - 33

    static func testEndReasonsAndMigration() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let dir = scratchDirectory()
        let usage = AppUsageArchive(directory: dir, now: { clock.value })
        var idle: TimeInterval = 0
        let tracker = AppUsageTracker(archive: usage,
                                      ownBundleID: FocusConstants.bundleIdentifier,
                                      idle: IdleMonitor(idleSeconds: { idle }),
                                      now: { clock.value })

        tracker.appActivated(bundleID: "com.a", name: "Alpha")
        clock.advance(600)
        tracker.appActivated(bundleID: "com.b", name: "Beta")      // a switch
        clock.advance(900)
        idle = 300                                                  // last 5 min idle
        tracker.suspend()

        let reasons = usage.sessions.map(\.endReason)
        expect(reasons.first == .appSwitch,
               "a switch records .appSwitch, got \(String(describing: reasons.first))",
               &problems)
        expect(reasons.contains(.idle),
               "an idle-trimmed stretch records .idle, saw \(reasons)", &problems)

        // Stretches are no longer merged at write time: the gaps must survive.
        let clock2 = TestClock(base)
        let dir2 = scratchDirectory()
        let usage2 = AppUsageArchive(directory: dir2, now: { clock2.value })
        let tracker2 = AppUsageTracker(archive: usage2,
                                       ownBundleID: FocusConstants.bundleIdentifier,
                                       idle: .disabled,
                                       now: { clock2.value })
        tracker2.appActivated(bundleID: "com.a", name: "Alpha")
        clock2.advance(600)
        tracker2.appActivated(bundleID: "com.b", name: "Beta")
        clock2.advance(30)
        tracker2.appActivated(bundleID: "com.a", name: "Alpha")
        clock2.advance(600)
        tracker2.suspend()
        expect(usage2.sessions.filter { $0.bundleID == "com.a" }.count == 2,
               "raw stretches are kept apart; grouping joins them later", &problems)

        // Records written before `endReason` existed must still load.
        let legacyDir = scratchDirectory()
        try? FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        let legacy = "[{\"id\":\"\(UUID().uuidString)\",\"bundleID\":\"com.legacy\","
            + "\"appName\":\"Legacy\",\"start\":\(base.timeIntervalSinceReferenceDate),"
            + "\"end\":\(base.addingTimeInterval(600).timeIntervalSinceReferenceDate)}]"
        try? Data(legacy.utf8).write(to: legacyDir.appendingPathComponent("app-usage.json"))
        let migrated = AppUsageArchive(directory: legacyDir, now: { clock.value })
        expect(migrated.sessions.count == 1,
               "a legacy record must still decode, got \(migrated.sessions.count)", &problems)
        expect(migrated.sessions.first?.endReason == .appSwitch,
               "a legacy record defaults to .appSwitch", &problems)

        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.removeItem(at: dir2)
        try? FileManager.default.removeItem(at: legacyDir)
        return problems
    }
}
