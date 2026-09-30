import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    // MARK: - 66

    /// The tiered break system: thresholds, escalation, and the wording.
    static func testBreakTiers() -> [String] {
        var problems: [String] = []
        let now = base.addingTimeInterval(6 * 3_600)
        func run(_ minutes: Double, app: String = "Xcode",
                 bundle: String = "com.apple.dt.Xcode") -> AppUsageSession {
            AppUsageSession(bundleID: bundle, appName: app,
                            start: now.addingTimeInterval(-minutes * 60), end: now)
        }

        expect(BreakReminder.dueTier([run(19)], now: now) == nil,
               "nineteen minutes is not yet anything", &problems)
        expect(BreakReminder.dueTier([run(21)], now: now) == .micro,
               "twenty minutes is an eye break", &problems)
        expect(BreakReminder.dueTier([run(51)], now: now) == .cognitive,
               "fifty minutes escalates past the eye break", &problems)
        expect(BreakReminder.dueTier([run(91)], now: now) == .ultradian,
               "ninety minutes is the deep one", &problems)

        // The deepest due tier wins, and escalation does not wait out the
        // shallower tier's quiet period.
        let justSaidMicro = BreakNotice(tier: .micro, at: now.addingTimeInterval(-120))
        let escalated = BreakReminder.prompt([run(91)], now: now, last: justSaidMicro)
        expect(escalated?.tier == .ultradian,
               "a deeper break must interrupt a shallower one's quiet period", &problems)
        // ...but two prompts inside a minute are noise whatever the tiers say.
        let secondsAgo = BreakNotice(tier: .micro, at: now.addingTimeInterval(-10))
        expect(BreakReminder.prompt([run(91)], now: now, last: secondsAgo) == nil,
               "nothing fires twice inside a minute", &problems)

        // Wording: the app is named, and the figure is what was actually worked
        // rather than the threshold that was crossed.
        guard let prompt = BreakReminder.prompt([run(63)], now: now, last: nil) else {
            problems.append("63 minutes should produce a prompt")
            return problems
        }
        expect(prompt.appName == "Xcode", "the app is named, got "
               + "\(prompt.appName ?? "nil")", &problems)
        expect(prompt.body.contains("Xcode"), "the body names it too", &problems)
        // The real figure, not the 50m threshold that was crossed.
        expect(prompt.body.contains("1h 3m"),
               "should report what was actually worked: \(prompt.body)", &problems)
        expect(!prompt.body.contains("50m"),
               "must not claim the threshold as the elapsed time", &problems)
        expect(prompt.title == BreakTier.cognitive.title, "titled by tier", &problems)

        // No dominant app means no app is named, rather than an arbitrary one.
        let scattered = [
            AppUsageSession(bundleID: "com.a", appName: "Alpha",
                            start: now.addingTimeInterval(-60 * 60),
                            end: now.addingTimeInterval(-40 * 60)),
            AppUsageSession(bundleID: "com.b", appName: "Beta",
                            start: now.addingTimeInterval(-40 * 60),
                            end: now.addingTimeInterval(-20 * 60)),
            AppUsageSession(bundleID: "com.c", appName: "Gamma",
                            start: now.addingTimeInterval(-20 * 60), end: now)
        ]
        expect(BreakReminder.dominantApp(scattered, now: now, within: 300) == nil,
               "three equal thirds name nobody", &problems)
        guard let vague = BreakReminder.prompt(scattered, now: now, last: nil) else {
            problems.append("an hour of scattered work is still a break")
            return problems
        }
        expect(!vague.body.contains("Alpha") && !vague.body.contains("Gamma"),
               "no app should be named: \(vague.body)", &problems)

        // An unknown name degrades rather than appearing verbatim.
        expect(BreakReminder.dominantApp([run(30, app: "Unknown", bundle: "com.x")],
                                         now: now, within: 300) == nil,
               "'Unknown' is not an app name", &problems)

        // The morning that wrote "You have been in Vorssaint for 20m": one
        // app with half the stretch, the rest in three others. The figure
        // is the Mac's; the app only colours it.
        func stretch(_ app: String, _ from: Double, _ to: Double) -> AppUsageSession {
            AppUsageSession(bundleID: "app.\(app)", appName: app,
                            start: now.addingTimeInterval(-from * 60), end: now.addingTimeInterval(-to * 60))
        }
        let login = [stretch("Claude", 20, 17), stretch("Finder", 17, 15), stretch("Vorssaint", 15, 8),
                     stretch("Dia", 8, 6), stretch("Vorssaint", 6, 1), stretch("Claude", 1, 0)]
        guard let majority = BreakReminder.prompt(login, now: now, last: nil) else {
            problems.append("twenty continuous minutes after login is a look-away"); return problems
        }
        expect(majority.body.hasPrefix("You have been at the Mac for 20m, mostly in Vorssaint."),
               "a 60% share was written as the app's own stretch: \(majority.body)", &problems)
        // Exactly half is not most.
        let half = [stretch("Claude", 20, 10), stretch("Vorssaint", 10, 0)]
        expect(BreakReminder.prompt(half, now: now, last: nil)?.body
                   .hasPrefix("You have been at the Mac for 20m.") == true,
               "exactly half was called most", &problems)
        let third = [stretch("Claude", 20, 13), stretch("Dia", 13, 7), stretch("Vorssaint", 7, 0)]
        expect(BreakReminder.prompt(third, now: now, last: nil)?.body
                   .hasPrefix("You have been at the Mac for 20m.") == true,
               "a plurality named an app", &problems)
        let whole = [stretch("Claude", 20, 19), stretch("Vorssaint", 19, 0)]
        expect(BreakReminder.prompt(whole, now: now, last: nil)?.body
                   .hasPrefix("You have been in Vorssaint for 20m.") == true,
               "nineteen of twenty minutes in one app is that app's stretch", &problems)

        // The countdown names the soonest tier. From a standing start that is
        // the eye break.
        expect(BreakReminder.next([run(10)], now: now)?.tier == .micro,
               "ten minutes in, the eye break is next", &problems)

        // But a pause resets only the shallow clock, so after one the *deeper*
        // tier is often sooner — forty minutes of work then a three-minute
        // breather leaves the cognitive reset ten minutes away and the eye
        // break a full twenty. The countdown has to follow the clocks, not the
        // tier order, or it promises a break later than the one you will get.
        let afterPause = [
            AppUsageSession(bundleID: "com.a", appName: "Alpha",
                            start: now.addingTimeInterval(-43 * 60),
                            end: now.addingTimeInterval(-3 * 60))
        ]
        guard let upcoming = BreakReminder.next(afterPause, now: now) else {
            problems.append("something should always be next")
            return problems
        }
        expect(upcoming.tier == .cognitive,
               "the cognitive reset is sooner after a short pause, got "
               + "\(upcoming.tier)", &problems)
        expectClose(upcoming.seconds, 10 * 60, "ten minutes to it", &problems)
        return problems
    }

    // MARK: - 38

    static func testTimelineLayout() -> [String] {
        var problems: [String] = []
        let dayStart = Calendar.current.startOfDay(for: base)
        func seg(_ fromMin: Double, _ toMin: Double) -> TimelineSegment {
            TimelineSegment(id: UUID(), bundleID: "com.a", appName: "Alpha",
                            start: dayStart.addingTimeInterval(fromMin * 60),
                            end: dayStart.addingTimeInterval(toMin * 60),
                            colorIndex: 0)
        }

        // 30 minutes, three hours of nothing, 30 minutes.
        let layout = TimelineLayout(segments: [seg(0, 30), seg(210, 240)],
                                    gapThreshold: 20 * 60)
        expect(layout.clusters.count == 2, "two clusters, got \(layout.clusters.count)",
               &problems)
        expect(layout.gaps.count == 1, "one elided gap, got \(layout.gaps.count)", &problems)
        expectClose(layout.gaps.first?.duration ?? -1, 180 * 60, "the gap is three hours",
                    &problems)

        let first = layout.clusters[0], second = layout.clusters[1]
        expectClose(first.xEnd - first.xStart, second.xEnd - second.xStart,
                    "equal durations get equal widths", &problems)
        expectClose(layout.clusters.last?.xEnd ?? -1, 1.0, "the band is fully used", &problems)
        expect(first.xEnd <= (layout.gaps.first?.xStart ?? -1) + 0.0001,
               "the separator sits between the clusters", &problems)

        // Under the threshold nothing is elided.
        let tight = TimelineLayout(segments: [seg(0, 30), seg(45, 60)], gapThreshold: 20 * 60)
        expect(tight.clusters.count == 1, "a 15 minute gap stays inside one cluster",
               &problems)
        expect(tight.gaps.isEmpty, "and produces no separator", &problems)

        // Mapping round-trips inside a cluster, refuses inside a gap.
        let inside = dayStart.addingTimeInterval(15 * 60)
        guard let fraction = layout.fraction(for: inside) else {
            problems.append("an instant inside a cluster must have a position")
            return problems
        }
        expectClose(layout.date(at: fraction)?.timeIntervalSince(inside) ?? 999, 0,
                    "fraction and date round-trip", &problems)
        expect(layout.fraction(for: dayStart.addingTimeInterval(120 * 60)) == nil,
               "an instant inside an elided gap has no position", &problems)

        // A tiny cluster beside a huge one stays visible.
        let lopsided = TimelineLayout(segments: [seg(0, 2), seg(120, 360)],
                                      gapThreshold: 20 * 60)
        let tiny = lopsided.clusters[0]
        expect(tiny.xEnd - tiny.xStart >= 0.035,
               "a two-minute cluster keeps a readable width, got \(tiny.xEnd - tiny.xStart)",
               &problems)

        // Hours are drawn inside clusters only.
        expect(layout.hourTicks().allSatisfy { layout.fraction(for: $0) != nil },
               "every hour tick has a position", &problems)
        expect(TimelineLayout(segments: [], gapThreshold: 20 * 60).isEmpty,
               "no segments, no clusters", &problems)
        return problems
    }

    // MARK: - 39

    static func testInsightCopyAndRunningFilter() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let usageDir = scratchDirectory(), sessionDir = scratchDirectory()
        let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
        let sessions = SessionArchive(directory: sessionDir, now: { clock.value })
        let dayStart = Calendar.current.startOfDay(for: base)

        usage.record(AppUsageSession(bundleID: "com.a", appName: "Claude",
                                     start: dayStart.addingTimeInterval(9 * 3_600),
                                     end: dayStart.addingTimeInterval(9 * 3_600 + 600)))
        let stats = DashboardStats(sessions: sessions, usage: usage, now: { clock.value })

        guard let longest = stats.insights(for: base)
            .first(where: { $0.id == "longest-stretch" }) else {
            problems.append("the longest-stretch insight must be present")
            return problems
        }
        expect(longest.headline == "Longest stretch in one app",
               "the headline names the measure, got '\(longest.headline)'", &problems)
        expect(longest.detail.contains("Claude"),
               "the detail names the app, got '\(longest.detail)'", &problems)
        expect(longest.detail.contains("10m"),
               "the detail carries the duration, got '\(longest.detail)'", &problems)
        expect(longest.detail.contains("–"),
               "the detail carries the clock range as evidence, got '\(longest.detail)'",
               &problems)

        // A process with no launch date tells us nothing, so it is not listed.
        let running = stats.runningNow(from: [
            RunningAppInput(bundleID: "com.a", appName: "Claude",
                            launched: dayStart.addingTimeInterval(8 * 3_600)),
            RunningAppInput(bundleID: "com.apple.finder", appName: "Finder", launched: nil)
        ])
        expect(running.count == 1,
               "apps with no launch date are excluded, got \(running.count)", &problems)
        expect(running.first?.bundleID == "com.a", "the real app survives", &problems)

        try? FileManager.default.removeItem(at: usageDir)
        try? FileManager.default.removeItem(at: sessionDir)
        return problems
    }
}
