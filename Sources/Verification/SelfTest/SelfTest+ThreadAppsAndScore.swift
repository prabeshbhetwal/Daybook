import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    // MARK: - 50

    static func testThreadApps() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let sessionDir = scratchDirectory(), usageDir = scratchDirectory()
        let archive = SessionArchive(directory: sessionDir, now: { clock.value })
        let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: base)
        let thread = UUID()
        let segmentStart = today.addingTimeInterval(9 * 3_600)
        // 3 pm, after both sessions below and within the window to continue
        // them; at `base` (9:13 am) they would still be ahead.
        clock.value = today.addingTimeInterval(15 * 3_600)

        archive.append(SessionRecord(name: "Refactor", workType: .deepWork,
                                     start: segmentStart,
                                     end: segmentStart.addingTimeInterval(3_600),
                                     workSeconds: 3_600, threadID: thread))

        // Inside the segment: Chrome longest, Xcode second, Terminal third,
        // Finder a flicker.
        usage.record(AppUsageSession(bundleID: "com.google.Chrome", appName: "Chrome",
                                     start: segmentStart,
                                     end: segmentStart.addingTimeInterval(1_800)))
        usage.record(AppUsageSession(bundleID: "com.apple.dt.Xcode", appName: "Xcode",
                                     start: segmentStart.addingTimeInterval(1_800),
                                     end: segmentStart.addingTimeInterval(3_000)))
        usage.record(AppUsageSession(bundleID: "com.apple.Terminal", appName: "Terminal",
                                     start: segmentStart.addingTimeInterval(3_000),
                                     end: segmentStart.addingTimeInterval(3_400)))
        usage.record(AppUsageSession(bundleID: "com.apple.finder", appName: "Finder",
                                     start: segmentStart.addingTimeInterval(3_400),
                                     end: segmentStart.addingTimeInterval(3_410)))
        // Outside the segment entirely — must not appear at all.
        usage.record(AppUsageSession(bundleID: "com.netflix.Netflix", appName: "Netflix",
                                     start: today.addingTimeInterval(20 * 3_600),
                                     end: today.addingTimeInterval(20 * 3_600 + 3_600)))

        let stats = ThreadStats(sessions: archive, usage: usage, now: { clock.value })
        guard let summary = stats.threads(on: base, running: nil).first else {
            problems.append("the thread must be present")
            return problems
        }
        let apps = stats.apps(for: summary, on: base)

        // Chrome has the most time, but Xcode is the focused-purpose app and so
        // is what the session was actually *for*.
        expect(apps.primary?.bundleID == "com.apple.dt.Xcode",
               "the primary app is the focused-purpose one, got "
               + "\(apps.primary?.bundleID ?? "nil")", &problems)
        expectClose(apps.primary?.total ?? -1, 1_200, "with its own attended time", &problems)

        let sideIDs = apps.side.map(\.bundleID)
        expect(sideIDs.contains("com.google.Chrome"), "Chrome is a side app", &problems)
        expect(sideIDs.contains("com.apple.Terminal"), "Terminal is a side app", &problems)
        expect(!sideIDs.contains("com.apple.finder"),
               "a ten-second flicker is below the floor", &problems)
        expect(!sideIDs.contains("com.netflix.Netflix"),
               "an app used outside the segment is not a side app", &problems)
        expect(!sideIDs.contains("com.apple.dt.Xcode"),
               "the primary app is not also a side app", &problems)
        expect(sideIDs.first == "com.google.Chrome",
               "side apps rank by attended time", &problems)

        // With no focused-purpose app at all, the most-attended one leads.
        let plainThread = UUID()
        let plainStart = today.addingTimeInterval(14 * 3_600)
        archive.append(SessionRecord(name: "Reading", workType: .learning,
                                     start: plainStart,
                                     end: plainStart.addingTimeInterval(1_800),
                                     workSeconds: 1_800, threadID: plainThread))
        usage.record(AppUsageSession(bundleID: "com.apple.Safari", appName: "Safari",
                                     start: plainStart,
                                     end: plainStart.addingTimeInterval(1_500)))
        let plainStats = ThreadStats(sessions: archive, usage: usage, now: { clock.value })
        if let plain = plainStats.threads(on: base, running: nil)
            .first(where: { $0.threadID == plainThread }) {
            expect(plainStats.apps(for: plain, on: base).primary?.bundleID
                   == "com.apple.Safari",
                   "with no focused app the most-attended one leads", &problems)
        } else {
            problems.append("the reading thread must be present")
        }

        try? FileManager.default.removeItem(at: sessionDir)
        try? FileManager.default.removeItem(at: usageDir)
        return problems
    }

    // MARK: - 51

    static func testContinueThread() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let engine = makeEngine(clock)
        let usageDir = scratchDirectory()
        let usage = AppUsageArchive(directory: usageDir, now: { clock.value })

        engine.start(workType: .learning, intent: "Read the paper")
        let thread = engine.activeThreadID
        clock.value = base.addingTimeInterval(1_200)
        engine.stop()

        // A different session runs in between and must be archived, not lost,
        // when the earlier thread is continued.
        clock.value = base.addingTimeInterval(2_000)
        engine.start(workType: .admin, intent: "Email")
        clock.value = base.addingTimeInterval(2_300)

        guard let summary = ThreadStats(sessions: engine.archive, usage: usage,
                                        now: { clock.value })
            .threads(on: base, running: nil)
            .first(where: { $0.threadID == thread }) else {
            problems.append("the earlier thread must be findable")
            try? FileManager.default.removeItem(at: usageDir)
            return problems
        }

        engine.start(workType: summary.workType, intent: summary.name,
                     threadID: summary.threadID)
        expect(engine.activeThreadID == thread, "the thread is adopted", &problems)
        expect(engine.activeWorkType == .learning, "the work type comes back", &problems)
        expect(engine.sessionName == "Read the paper",
               "the name comes back, got \(engine.sessionName)", &problems)
        expect(engine.archive.records.contains { $0.name == "Email" },
               "the interrupted session was archived, not discarded", &problems)

        clock.value = base.addingTimeInterval(3_000)
        engine.stop()
        let segments = engine.archive.records.filter { $0.threadID == thread }
        expect(segments.count == 2, "the thread now has two segments, got "
               + "\(segments.count)", &problems)

        try? FileManager.default.removeItem(at: usageDir)
        return problems
    }

    // MARK: - 52

    static func testFocusScore() -> [String] {
        var problems: [String] = []
        let scorer = FocusScorer()
        // 15 minutes, matching FocusConstants.focusWindow.
        let window = (start: base, end: base.addingTimeInterval(900))

        // Media veto: Netflix carries most of the window even though Warp is coding.
        let mediaSegments = [
            AppUsageSession(bundleID: "com.netflix.Netflix", appName: "Netflix",
                            start: base, end: base.addingTimeInterval(600)),
            AppUsageSession(bundleID: "dev.warp.Warp-Stable", appName: "Warp",
                            start: base.addingTimeInterval(600), end: base.addingTimeInterval(900))
        ]
        let vetoed = scorer.score(segments: mediaSegments, activity: .active, window: window)
        expect(vetoed.value == 0, "media veto forces the score to zero, got \(vetoed.value)", &problems)
        expectClose(vetoed.signals.mediaShare, 600.0 / 900.0,
                   "media share is still reported honestly", &problems)
        expectClose(vetoed.signals.focusedShare, 300.0 / 900.0,
                   "focused share is still reported honestly", &problems)
        expect(vetoed.explanation.contains("media"),
              "explanation notes the veto, got '\(vetoed.explanation)'", &problems)

        // Passive scores lower than active for identical segments.
        let steadySegments = [
            AppUsageSession(bundleID: "dev.warp.Warp-Stable", appName: "Warp",
                            start: base, end: base.addingTimeInterval(900))
        ]
        let activeScore = scorer.score(segments: steadySegments, activity: .active, window: window)
        let passiveScore = scorer.score(segments: steadySegments, activity: .passive, window: window)
        expectClose(activeScore.value, 1.0, "active, single app, no churn scores at full focus", &problems)
        expectClose(passiveScore.value, 0.4, "passive weight is 0.4", &problems)
        expect(activeScore.value > passiveScore.value,
              "active must outscore passive for identical input", &problems)

        // Heavy churn reduces the score even with the same focused share and activity.
        // The segments alternate between two focused apps: churn is switching
        // between apps, so 46 segments of one app would be no churn at all.
        let churnCount = 46
        let step = 900.0 / Double(churnCount)
        var churnSegments: [AppUsageSession] = []
        for index in 0..<churnCount {
            let segStart = base.addingTimeInterval(Double(index) * step)
            let segEnd = base.addingTimeInterval(Double(index + 1) * step)
            churnSegments.append(index.isMultiple(of: 2)
                ? AppUsageSession(bundleID: "dev.warp.Warp-Stable", appName: "Warp",
                                  start: segStart, end: segEnd)
                : AppUsageSession(bundleID: "com.apple.dt.Xcode", appName: "Xcode",
                                  start: segStart, end: segEnd))
        }
        let churnScore = scorer.score(segments: churnSegments, activity: .active, window: window)
        // 45 app changes / 15min = 3.0 switches/min; (3.0 - 2.0 calm) * 0.15 penalty = 0.15.
        expectClose(churnScore.signals.switchesPerMinute, 3.0,
                   "switch rate for 46 alternating segments over 15m", &problems)
        expectClose(churnScore.value, 0.85, "churn penalty lowers the score", &problems)
        expect(churnScore.value < activeScore.value,
              "heavy churn must score lower than the equivalent calm stretch", &problems)

        // An empty window returns zero without dividing by zero.
        let empty = scorer.score(segments: [], activity: .active, window: window)
        expect(empty == FocusScore.zero, "no segments yields FocusScore.zero", &problems)
        let outside = [
            AppUsageSession(bundleID: "dev.warp.Warp-Stable", appName: "Warp",
                            start: base.addingTimeInterval(-3_600), end: base.addingTimeInterval(-1_800))
        ]
        let noOverlap = scorer.score(segments: outside, activity: .active, window: window)
        expect(noOverlap == FocusScore.zero,
              "segments entirely outside the window also yield zero", &problems)

        // Explanation names the dominant app.
        let namedSegments = [
            AppUsageSession(bundleID: "dev.warp.Warp-Stable", appName: "Warp",
                            start: base, end: base.addingTimeInterval(360))
        ]
        let named = scorer.score(segments: namedSegments, activity: .active, window: window)
        expect(named.explanation.contains("Warp"),
              "explanation names the dominant app, got '\(named.explanation)'", &problems)
        expect(named.explanation.contains("6m"),
              "explanation states the dominant app's attended minutes, got '\(named.explanation)'",
              &problems)
        expect(named.signals.dominantApp == "dev.warp.Warp-Stable", "dominantApp is the bundle ID",
              &problems)
        expect(named.signals.dominantAppName == "Warp", "dominantAppName is the app name", &problems)
        expect(named.signals.dominantPurpose == .coding, "dominantPurpose is Warp's purpose", &problems)

        return problems
    }

        // MARK: - (N)
}
