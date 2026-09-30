import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    // MARK: - 70

    /// Every answer but "I was working" closes the session where the user
    /// walked away and opens a new one when they got back. What separates them
    /// is the thread: an afternoon split by lunch is still one piece of work.
    static func testAwayEndsSession() -> [String] {
        var problems: [String] = []
        let work: TimeInterval = 40 * 60
        let away: TimeInterval = 33 * 60

        func run(_ decision: UserDecision) -> (engine: SessionEngine,
                                               left: Date, back: Date) {
            let clock = TestClock(base)
            let engine = makeEngine(clock)
            engine.start(workType: .deepWork, intent: "Refactor")
            clock.advance(work)
            let left = clock.value
            engine.transition(on: .awayBegan(trigger: .screenLock))
            clock.advance(away)
            let back = clock.value
            engine.transition(on: .awayEnded)
            engine.transition(on: .decision(decision))
            return (engine, left, back)
        }

        for decision in [UserDecision.continueSession, .tookBreak, .resetTimer] {
            let (engine, left, back) = run(decision)
            expect(engine.state == .running,
                   "\(decision): a new session should be running", &problems)
            expectClose(engine.elapsed, 0,
                        "\(decision): the new session starts fresh", &problems)
            expectClose(engine.sessionStartDate.timeIntervalSince(back), 0,
                        "\(decision): and starts when the user got back", &problems)
            guard let closed = engine.archive.records
                .last(where: { $0.workType.countsAsFocus }) else {
                problems.append("\(decision): the old session should be archived")
                continue
            }
            expectClose(closed.workSeconds, work,
                        "\(decision): archived work is what was worked", &problems)
            expectClose(closed.end.timeIntervalSince(left), 0,
                        "\(decision): archived end is where they left", &problems)
        }

        // Thread identity is the whole difference between the three.
        let awayRun = run(.continueSession)
        expect(awayRun.engine.activeThreadID
                == awayRun.engine.archive.records.last?.threadID,
               "'I was away' keeps the thread", &problems)

        let freshRun = run(.resetTimer)
        expect(freshRun.engine.activeThreadID
                != freshRun.engine.archive.records.last?.threadID,
               "'Start fresh' takes a new thread", &problems)

        let breakRun = run(.tookBreak)
        let focusRecords = breakRun.engine.archive.records.filter {
            $0.workType.countsAsFocus
        }
        expect(breakRun.engine.activeThreadID == focusRecords.last?.threadID,
               "'It was a break' keeps the thread", &problems)
        expect(breakRun.engine.archive.records.contains { $0.workType == .breakTime },
               "and still records the break", &problems)

        // "I was working" is the one answer that does not split anything.
        let (merged, _, _) = run(.mergeTime)
        expect(merged.archive.records.isEmpty,
               "merging archives nothing, got \(merged.archive.records.count)", &problems)
        expectClose(merged.elapsed, work + away,
                    "and the gap becomes work", &problems)
        return problems
    }

    // MARK: - 71

    /// `Now: Claude 6h 50m` was the time since the process launched, rendered
    /// directly above `Claude 53m` in Top Apps. Two labels that read alike must
    /// not measure different things.
    static func testRunningStretch() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stats = DashboardStats(
            sessions: SessionArchive(directory: directory, now: { clock.value }),
            usage: AppUsageArchive(directory: directory, now: { clock.value }),
            now: { clock.value })
        let launched = base.addingTimeInterval(-6 * 3_600)

        let apps = stats.runningNow(from: [
            RunningAppInput(bundleID: "com.a", appName: "Alpha",
                            launched: launched, stretchSeconds: 12 * 60),
            RunningAppInput(bundleID: "com.b", appName: "Beta",
                            launched: launched, stretchSeconds: nil)
        ])

        guard let alpha = apps.first(where: { $0.bundleID == "com.a" }) else {
            problems.append("the frontmost app should be listed")
            return problems
        }
        expectClose(alpha.openFor ?? -1, 12 * 60,
                    "the current stretch, not six hours of uptime", &problems)

        let beta = apps.first { $0.bundleID == "com.b" }
        expect(beta?.openFor == nil,
               "an app with no open stretch reports no figure", &problems)
        expect(apps.first?.bundleID == "com.a",
               "the app you are actually in sorts first", &problems)
        return problems
    }

    // MARK: - 72

    /// The compact operational menu remains one column on every display and
    /// treats valid usable geometry as a hard bound, even below old floors.
    static func testPopoverMetrics() -> [String] {
        var problems: [String] = []

        // 14" MacBook Pro, menu bar and Dock removed.
        let laptop = PopoverMetrics.fitting(CGSize(width: 1_512, height: 900))
        expect(laptop.maxHeight < 900,
               "the panel must be shorter than the screen", &problems)
        expect(laptop.maxHeight >= 600,
               "but not uselessly short, got \(laptop.maxHeight)", &problems)

        let small = PopoverMetrics.fitting(CGSize(width: 1_366, height: 700))
        expect(small.maxHeight < 700, "shorter than a small screen too", &problems)
        expect(!small.twoColumn && small.width == 340,
               "a short screen remains a compact 340pt single column", &problems)

        // Genuinely narrow displays stay single-column: 560pt would be most of
        // the screen, and two panes of 250pt hold nothing.
        let narrow = PopoverMetrics.fitting(CGSize(width: 1_100, height: 900))
        expect(!narrow.twoColumn, "a narrow screen cannot host two panes", &problems)
        expect(narrow.width == Tokens.popoverWidth,
               "and keeps the single-column width", &problems)

        let desktop = PopoverMetrics.fitting(CGSize(width: 2_560, height: 1_440))
        expect(!desktop.twoColumn && desktop.width == 340,
               "a large display does not widen one-column content", &problems)

        let thirteen = PopoverMetrics.fitting(CGSize(width: 1_440, height: 845))
        expect(!thirteen.twoColumn,
               "a 13-inch remains one operational column", &problems)
        expect(thirteen.dense, "and the tighter density", &problems)
        expect(thirteen.rowHeight < 26 && thirteen.outerPadding < Tokens.Space.l,
               "which must actually change the measurements", &problems)
        expect(thirteen.maxHeight <= 845,
               "the panel respects the 13-inch usable height", &problems)

        // A roomy screen keeps the comfortable density.
        let roomy = PopoverMetrics.fitting(CGSize(width: 2_560, height: 1_440))
        expect(!roomy.dense, "a large screen has no need to tighten", &problems)
        let tiny = PopoverMetrics.fitting(CGSize(width: 312, height: 420))
        expect(tiny.width <= 312 && tiny.maxHeight <= 420,
               "valid tiny-screen geometry remains a hard bound", &problems)
        let fallback = PopoverMetrics.fitting(CGSize(width: CGFloat.nan, height: -1))
        expect(fallback.width == 340 && fallback.maxHeight > 0,
               "invalid screen geometry uses the safe fallback", &problems)
        return problems
    }

    // MARK: - 73

    /// Stepping the dashboard to Yesterday must not re-scope the menu bar. They
    /// shared one `dayOffset`, so the panel that exists to answer "how am I
    /// doing right now" quietly started answering it about a day that had
    /// ended. This pins the two computations apart so a refactor cannot
    /// collapse them back into one.
    static func testGlanceStaysToday() -> [String] {
        var problems: [String] = []
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let clock = TestClock(base)
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: clock.value)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else {
            return ["could not build a two-day window"]
        }
        usage.record(AppUsageSession(bundleID: "com.today", appName: "TodayApp",
                                     start: today.addingTimeInterval(3_600),
                                     end: today.addingTimeInterval(7_200)))
        usage.record(AppUsageSession(bundleID: "com.past", appName: "PastApp",
                                     start: yesterday.addingTimeInterval(3_600),
                                     end: yesterday.addingTimeInterval(7_200)))

        let stats = DashboardStats(
            sessions: SessionArchive(directory: directory, now: { clock.value }),
            usage: usage, now: { clock.value })

        // The glance is built for today whatever day is selected.
        let todayApps = stats.rankedApps(for: today)
        let pastApps = stats.rankedApps(for: yesterday)
        expect(todayApps.first?.appName == "TodayApp",
               "today's glance names today's app", &problems)
        expect(pastApps.first?.appName == "PastApp",
               "and the selected day is a separate question", &problems)
        expect(todayApps.first?.appName != pastApps.first?.appName,
               "the two must not be the same computation", &problems)
        return problems
    }
}
