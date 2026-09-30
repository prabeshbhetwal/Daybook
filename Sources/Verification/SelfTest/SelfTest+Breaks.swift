import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    // MARK: - 34

    static func testSessionGrouping() -> [String] {
        var problems: [String] = []
        let dayStart = Calendar.current.startOfDay(for: base)
        func seg(_ id: String, _ fromMin: Double, _ toMin: Double,
                 _ reason: UsageEndReason = .appSwitch) -> TimelineSegment {
            TimelineSegment(id: UUID(), bundleID: id, appName: id,
                            start: dayStart.addingTimeInterval(fromMin * 60),
                            end: dayStart.addingTimeInterval(toMin * 60),
                            colorIndex: 0, endReason: reason)
        }
        let gap: TimeInterval = 300, bridge: TimeInterval = 900

        // A three-minute detour joins into one sitting with two visits.
        let detour = AppSessionGrouper.group([seg("com.a", 0, 20), seg("com.a", 23, 40)],
                                             others: [seg("com.b", 20, 23)],
                                             sessionGap: gap, awayBridge: bridge)
        expect(detour.count == 1, "a short detour joins, got \(detour.count)", &problems)
        expect(detour.first?.visits == 2, "two visits", &problems)
        expectClose(detour.first?.attended ?? -1, 37 * 60,
                    "attended excludes the gap", &problems)
        expectClose(detour.first?.span ?? -1, 40 * 60, "the span includes the gap", &problems)

        // A lock is a boundary however short the gap.
        let locked = AppSessionGrouper.group([seg("com.a", 0, 20, .systemLock),
                                              seg("com.a", 21, 40)],
                                             others: [], sessionGap: gap, awayBridge: bridge)
        expect(locked.count == 2, "a lock splits, got \(locked.count)", &problems)

        // Real work elsewhere is a context switch, not a detour.
        let switched = AppSessionGrouper.group([seg("com.a", 0, 20), seg("com.a", 24, 40)],
                                               others: [seg("com.b", 20, 24)],
                                               sessionGap: 180, awayBridge: bridge)
        expect(switched.count == 2,
               "another app's real usage splits, got \(switched.count)", &problems)

        // Stepping away and returning to the same app joins, up to the bridge.
        let away = AppSessionGrouper.group([seg("com.a", 0, 20, .idle), seg("com.a", 32, 40)],
                                           others: [], sessionGap: gap, awayBridge: bridge)
        expect(away.count == 1, "an idle gap under the bridge joins, got \(away.count)",
               &problems)

        let longAway = AppSessionGrouper.group([seg("com.a", 0, 20, .idle),
                                                seg("com.a", 60, 70)],
                                               others: [], sessionGap: gap, awayBridge: bridge)
        expect(longAway.count == 2, "beyond the bridge splits", &problems)

        expect(AppSessionGrouper.group([], others: [], sessionGap: gap,
                                       awayBridge: bridge).isEmpty,
               "no stretches, no sessions", &problems)
        return problems
    }

    // MARK: - 35

    static func testHourlyBuckets() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let usageDir = scratchDirectory(), sessionDir = scratchDirectory()
        let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
        let dayStart = Calendar.current.startOfDay(for: base)

        // 9:45 to 10:15 — fifteen minutes either side of the hour boundary.
        usage.record(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                     start: dayStart.addingTimeInterval(9 * 3_600 + 2_700),
                                     end: dayStart.addingTimeInterval(10 * 3_600 + 900)))
        let stats = DashboardStats(sessions: SessionArchive(directory: sessionDir,
                                                            now: { clock.value }),
                                   usage: usage, now: { clock.value })
        let filled = stats.hourlyBuckets(for: base, bundleID: "com.a")
            .filter { $0.seconds > 0 }
        expect(filled.count == 2,
               "a stretch across the hour lands in two buckets, got \(filled.count)",
               &problems)
        expectClose(filled.first?.seconds ?? -1, 900, "fifteen minutes in the first hour",
                    &problems)
        expectClose(filled.reduce(0) { $0 + $1.seconds }, 1_800,
                    "buckets sum to the stretch", &problems)

        try? FileManager.default.removeItem(at: usageDir)
        try? FileManager.default.removeItem(at: sessionDir)
        return problems
    }

        // MARK: - 37

    static func testBreakReminder() -> [String] {
        var problems: [String] = []
        let now = base.addingTimeInterval(4 * 3_600)
        func stretch(_ fromMinAgo: Double, _ toMinAgo: Double) -> AppUsageSession {
            AppUsageSession(bundleID: "com.a", appName: "Alpha",
                            start: now.addingTimeInterval(-fromMinAgo * 60),
                            end: now.addingTimeInterval(-toMinAgo * 60))
        }
        // 53 minutes of work broken only by a 2 minute gap: continuous as far as
        // the cognitive tier is concerned, since its rest length is five minutes.
        let continuous = [stretch(55, 30), stretch(28, 0)]
        expectClose(BreakReminder.worked(continuous, now: now,
                                         restingAtLeast: BreakTier.cognitive.breakLength),
                    53 * 60,
                    "short gaps neither reset the clock nor count as work", &problems)
        // A two-minute gap does NOT clear even the shallowest tier: below the
        // three-minute idle cutoff the usage archive cannot tell rest from
        // recording noise, so nothing shorter is allowed to reset a clock.
        expectClose(BreakReminder.worked(continuous, now: now,
                                         restingAtLeast: BreakTier.micro.restGap),
                    53 * 60, "a two-minute gap is not observable rest", &problems)
        expect(BreakTier.micro.restGap == AppUsageTracker.idleCutoff,
               "the shallow tier resets at the idle cutoff, not its own 30s",
               &problems)
        expect(BreakReminder.dueTier(continuous, now: now) == .cognitive,
               "53 continuous minutes is a cognitive reset", &problems)

        // A 12 minute gap clears the cognitive tier but not the ultradian one.
        let rested = [stretch(90, 40), stretch(28, 0)]
        expectClose(BreakReminder.worked(rested, now: now,
                                         restingAtLeast: BreakTier.cognitive.breakLength),
                    28 * 60, "a long gap resets the cognitive clock", &problems)
        expect(BreakReminder.dueTier(rested, now: now) == .micro,
               "28 minutes since a rest is an eye break, got "
               + "\(String(describing: BreakReminder.dueTier(rested, now: now)))", &problems)

        // Having just spoken at this depth, it stays quiet until that tier's own
        // interval has passed.
        let saidCognitive = BreakNotice(tier: .cognitive, at: now.addingTimeInterval(-600))
        expect(BreakReminder.prompt(continuous, now: now, last: saidCognitive) == nil,
               "no second nudge ten minutes after the first", &problems)
        let saidLongAgo = BreakNotice(tier: .cognitive, at: now.addingTimeInterval(-60 * 60))
        expect(BreakReminder.prompt(continuous, now: now, last: saidLongAgo) != nil,
               "an hour later, due again", &problems)

        expectClose(BreakReminder.worked([], now: now, restingAtLeast: 300), 0,
                    "no usage, no work", &problems)
        return problems
    }
}
