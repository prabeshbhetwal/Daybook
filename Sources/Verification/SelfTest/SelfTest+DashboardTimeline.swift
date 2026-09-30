import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    /// Integrity qualification needs a yes/no answer, not an allocated copy of
    /// the whole filtered archive. System processes remain excluded and both
    /// the selected interval and accuracy cutoff are respected.
    static func testIntegrityUsageQuery() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        let interval = DateInterval(start: base.addingTimeInterval(-4 * 3_600),
                                    end: base.addingTimeInterval(2 * 3_600))

        usage.record(AppUsageSession(bundleID: "com.apple.loginwindow", appName: "Login Window",
                                     start: base.addingTimeInterval(-3 * 3_600),
                                     end: base.addingTimeInterval(-2 * 3_600)))
        usage.record(AppUsageSession(bundleID: "com.example.after", appName: "After",
                                     start: base.addingTimeInterval(600),
                                     end: base.addingTimeInterval(1_200)))
        expect(!usage.containsUsage(in: interval, before: base),
               "system usage and ordinary usage after the cutoff do not qualify", &problems)

        usage.record(AppUsageSession(bundleID: "com.example.before", appName: "Before",
                                     start: base.addingTimeInterval(-1_200),
                                     end: base.addingTimeInterval(-600)))
        expect(usage.containsUsage(in: interval, before: base),
               "ordinary usage inside the interval before the cutoff qualifies", &problems)
        let later = DateInterval(start: base.addingTimeInterval(3_600),
                                 end: base.addingTimeInterval(7_200))
        expect(!usage.containsUsage(in: later, before: base.addingTimeInterval(7_200)),
               "usage outside the selected interval does not qualify", &problems)
        return problems
    }

        // MARK: - 24

    static func testHistoryFormatters() -> [String] {
        var problems: [String] = []
        let reference = base

        expect(Tokens.relative(reference.addingTimeInterval(-30), from: reference) == "just now",
               "30s should read 'just now'", &problems)
        expect(Tokens.relative(reference.addingTimeInterval(-3_600), from: reference) == "1 hour ago",
               "singular hour", &problems)
        expect(Tokens.relative(reference.addingTimeInterval(-4 * 3_600), from: reference)
               == "4 hours ago", "the example from the request", &problems)
        expect(Tokens.relative(reference.addingTimeInterval(-26 * 3_600), from: reference)
               == "yesterday", "26h should read 'yesterday'", &problems)

        expect(Tokens.spent(7_200) == "2 hours", "2h exactly, got \(Tokens.spent(7_200))",
               &problems)
        expect(Tokens.spent(7_980) == "2 hours 13 min",
               "2h13m, got \(Tokens.spent(7_980))", &problems)
        expect(Tokens.spent(60) == "1 minute", "singular minute", &problems)
        expect(Tokens.spent(0) == "0 seconds", "zero", &problems)

        // Range formatting is locale-dependent, so assert the structure only.
        let range = Tokens.timeRange(reference, reference.addingTimeInterval(7_200))
        expect(range.contains("–"), "range should use an en dash, got \(range)", &problems)
        return problems
    }

    // MARK: - 25

    static func testDashboardTimeline() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let usageDir = scratchDirectory(), sessionDir = scratchDirectory()
        let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
        let sessions = SessionArchive(directory: sessionDir, now: { clock.value })
        let dayStart = Calendar.current.startOfDay(for: base)

        func use(_ id: String, _ name: String, fromHour: Double, hours: Double) {
            let start = dayStart.addingTimeInterval(fromHour * 3_600)
            usage.record(AppUsageSession(bundleID: id, appName: name, start: start,
                                         end: start.addingTimeInterval(hours * 3_600)))
        }
        use("com.a", "Alpha", fromHour: 9, hours: 2)
        use("com.b", "Beta", fromHour: 11, hours: 1)
        use("com.a", "Alpha", fromHour: 14, hours: 1)

        let stats = DashboardStats(sessions: sessions, usage: usage, now: { clock.value })
        let segments = stats.timeline(for: base)
        expect(segments.count == 3, "three segments, got \(segments.count)", &problems)
        expect(segments.map(\.start) == segments.map(\.start).sorted(),
               "segments must be ordered by start", &problems)
        expect(segments.filter { $0.bundleID == "com.a" }.allSatisfy { $0.colorIndex == 0 },
               "the busiest app takes index 0 for all its segments", &problems)

        let ranked = stats.rankedApps(for: base)
        expect(ranked.count == 2, "two apps, got \(ranked.count)", &problems)
        expect(ranked.first?.bundleID == "com.a", "busiest first", &problems)
        expectClose(ranked.first?.total ?? -1, 3 * 3_600, "Alpha total", &problems)
        expectClose(ranked.first?.longest ?? -1, 2 * 3_600, "Alpha longest", &problems)
        expectClose(ranked.reduce(0) { $0 + $1.share }, 1.0, "shares sum to 1", &problems)
        expectClose(stats.trackedTotal(for: base), 4 * 3_600, "tracked total", &problems)

        // An empty day must publish 0, never NaN.
        let emptyStats = DashboardStats(sessions: SessionArchive(directory: scratchDirectory(),
                                                                 now: { clock.value }),
                                        usage: AppUsageArchive(directory: scratchDirectory(),
                                                               now: { clock.value }),
                                        now: { clock.value })
        expect(emptyStats.rankedApps(for: base).isEmpty, "no apps on an empty day", &problems)
        expectClose(emptyStats.trackedTotal(for: base), 0, "empty total", &problems)
        expect(emptyStats.timelineWindow(for: base) == nil,
               "an empty day has no drawing window", &problems)

        try? FileManager.default.removeItem(at: usageDir)
        try? FileManager.default.removeItem(at: sessionDir)
        return problems
    }

    // MARK: - 26

    static func testTimelineClipsAcrossMidnight() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let usageDir = scratchDirectory(), sessionDir = scratchDirectory()
        let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
        let dayStart = Calendar.current.startOfDay(for: base)

        // 23:30 to 00:30 — half belongs to each day, and to neither twice.
        let start = dayStart.addingTimeInterval(23.5 * 3_600)
        usage.record(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                     start: start, end: start.addingTimeInterval(3_600)))

        let stats = DashboardStats(sessions: SessionArchive(directory: sessionDir,
                                                            now: { clock.value }),
                                   usage: usage, now: { clock.value })
        let today = stats.timeline(for: base)
        expect(today.count == 1, "one clipped segment today, got \(today.count)", &problems)
        expectClose(today.first?.seconds ?? -1, 1_800, "today keeps the first half hour",
                    &problems)

        let tomorrow = stats.timeline(for: base.addingTimeInterval(86_400))
        expectClose(tomorrow.first?.seconds ?? -1, 1_800,
                    "tomorrow keeps the second half hour", &problems)
        expectClose(stats.trackedTotal(for: base) + stats.trackedTotal(for: base.addingTimeInterval(86_400)),
                    3_600, "the two halves sum to the whole, never double counted", &problems)

        try? FileManager.default.removeItem(at: usageDir)
        try? FileManager.default.removeItem(at: sessionDir)
        return problems
    }

    // MARK: - 27

    static func testFocusQualityAndRunning() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let usageDir = scratchDirectory(), sessionDir = scratchDirectory()
        let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
        let sessions = SessionArchive(directory: sessionDir, now: { clock.value })
        let dayStart = Calendar.current.startOfDay(for: base)

        func use(_ id: String, fromHour: Double, hours: Double) {
            let start = dayStart.addingTimeInterval(fromHour * 3_600)
            usage.record(AppUsageSession(bundleID: id, appName: id, start: start,
                                         end: start.addingTimeInterval(hours * 3_600)))
        }
        use("com.a", fromHour: 9, hours: 2)     // inside the session below
        use("com.b", fromHour: 13, hours: 2)    // outside it
        sessions.append(SessionRecord(name: "Deep", workType: .deepWork,
                                      start: dayStart.addingTimeInterval(9 * 3_600),
                                      end: dayStart.addingTimeInterval(11 * 3_600),
                                      workSeconds: 7_200))

        let stats = DashboardStats(sessions: sessions, usage: usage, now: { clock.value })
        let quality = stats.focusQuality(for: base)
        expectClose(quality.insideSessionShare, 0.5,
                    "half of tracked time was inside a session", &problems)
        expect(quality.sessionCount == 1, "one session", &problems)
        expect(quality.byWorkType.first?.workType == .deepWork, "deep work leads", &problems)

        clock.value = dayStart.addingTimeInterval(12 * 3_600)
        let running = stats.runningNow(from: [
            RunningAppInput(bundleID: "com.a", appName: "Alpha",
                            launched: dayStart.addingTimeInterval(9 * 3_600),
                            stretchSeconds: 3 * 3_600),
            RunningAppInput(bundleID: "com.finder", appName: "Finder", launched: nil)
        ])
        expectClose(running.first?.openFor ?? -1, 3 * 3_600,
                    "Alpha frontmost for three hours", &problems)
        expect(running.count == 1,
               "an app with no launch date is excluded, got \(running.count)", &problems)
        expect(running.first?.bundleID == "com.a", "the real app survives", &problems)

        try? FileManager.default.removeItem(at: usageDir)
        try? FileManager.default.removeItem(at: sessionDir)
        return problems
    }

    // MARK: - 28

    static func testInsightGating() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let usageDir = scratchDirectory(), sessionDir = scratchDirectory()
        let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
        let sessions = SessionArchive(directory: sessionDir, now: { clock.value })
        let stats = DashboardStats(sessions: sessions, usage: usage, now: { clock.value })

        expect(stats.insights(for: base).isEmpty,
               "no data must produce no insights, not empty cards", &problems)

        let dayStart = Calendar.current.startOfDay(for: base)
        usage.record(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                     start: dayStart.addingTimeInterval(9 * 3_600),
                                     end: dayStart.addingTimeInterval(11 * 3_600)))
        let withUsage = stats.insights(for: base)
        expect(withUsage.contains { $0.id == "longest-stretch" },
               "one usage session unlocks the longest-stretch insight", &problems)
        expect(!withUsage.contains { $0.id == "inside-session" },
               "with no focus session the in-session insight stays hidden", &problems)
        expect(!withUsage.contains { $0.id == "vs-yesterday" },
               "with no yesterday data the comparison stays hidden", &problems)

        sessions.append(SessionRecord(name: "Deep", workType: .deepWork,
                                      start: dayStart.addingTimeInterval(9 * 3_600),
                                      end: dayStart.addingTimeInterval(10 * 3_600),
                                      workSeconds: 3_600))
        let withSession = stats.insights(for: base)
        expect(withSession.contains { $0.id == "inside-session" },
               "a focus session unlocks the in-session insight", &problems)
        // Deep-work share is deliberately NOT an insight: the Focus quality
        // section already states it, and repeating a figure erodes trust in both.
        expect(!withSession.contains { $0.id == "deep-work-share" },
               "deep work share belongs to Focus quality, not Insights", &problems)

        try? FileManager.default.removeItem(at: usageDir)
        try? FileManager.default.removeItem(at: sessionDir)
        return problems
    }
}
