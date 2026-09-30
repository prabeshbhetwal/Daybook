import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    // MARK: - 19

    static func testDiscreteSessions() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let engine = makeEngine(clock)

        engine.start(workType: .deepWork, intent: "Refactor")
        expect(engine.state == .running, "start should run, got \(engine.state)", &problems)
        clock.advance(1_500)
        engine.transition(on: .manualPause)
        clock.advance(300)
        engine.transition(on: .manualResume)
        clock.advance(600)
        engine.stop()

        expect(engine.state == .idle, "stop should idle, got \(engine.state)", &problems)
        guard let record = engine.archive.records.last else {
            problems.append("stop should write a record")
            return problems
        }
        expectClose(record.workSeconds, 2_100, "paused time excluded from the record", &problems)
        expect(record.name == "Refactor", "record keeps the intent, got \(record.name)", &problems)
        expect(record.workType == .deepWork, "record keeps the work type", &problems)
        expectClose(engine.archive.todayTotal(), 2_100, "today total", &problems)

        engine.start(workType: .admin, intent: "Email")
        clock.advance(600)
        engine.stop()
        expectClose(engine.archive.todayTotal(), 2_700, "two sessions sum", &problems)
        expect(engine.archive.sessionsToday() == 2, "two sessions counted", &problems)
        expect(engine.archive.records.last?.workType == .admin, "second work type", &problems)

        // Starting while running archives the first rather than losing it.
        engine.start(workType: .learning, intent: "Read")
        clock.advance(300)
        engine.start(workType: .deepWork, intent: "Switch")
        expect(engine.archive.sessionsToday() == 3,
               "starting while running should archive the previous session", &problems)
        return problems
    }

    // MARK: - 20

    static func testAwayInsideSession() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let engine = makeEngine(clock)

        engine.start(workType: .deepWork, intent: "Write")
        clock.advance(600)
        engine.transition(on: .awayBegan(trigger: .screenLock))
        clock.advance(480)                      // micro-break, absorbed silently
        engine.transition(on: .awayEnded)
        clock.advance(600)
        engine.stop()

        expectClose(engine.archive.records.last?.workSeconds ?? -1, 1_200,
                    "micro-break excluded from the record", &problems)
        return problems
    }

    // MARK: - 21

    /// The menu bar label showed a static glyph because nothing observed the
    /// store. This covers the engine half of that chain: every real transition
    /// must reach an observer, so a view bound to it can redraw.
    static func testEngineNotifiesObservers() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let engine = makeEngine(clock)

        var seen: [SessionState] = []
        engine.onStateChanged = { seen.append($0) }

        engine.start(workType: .deepWork, intent: "Refactor")
        clock.advance(600)
        engine.transition(on: .manualPause)
        clock.advance(60)
        engine.transition(on: .manualResume)
        engine.stop()

        expect(seen.contains(.running), "observer should see running", &problems)
        expect(seen.contains { $0.isPaused }, "observer should see paused", &problems)
        expect(seen.last == .idle, "observer should see idle last, got \(String(describing: seen.last))",
               &problems)
        expect(seen.count >= 4,
               "start, pause, resume and stop should each notify, got \(seen.count)", &problems)

        // A no-op must not notify: redundant redraws are how menu bar items flicker.
        let before = seen.count
        engine.transition(on: .manualResume)   // already idle — documented no-op
        expect(seen.count == before, "a no-op must not notify", &problems)
        return problems
    }

    // MARK: - 22

    static func testUsageTracker() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let dir = scratchDirectory()
        let usage = AppUsageArchive(directory: dir, now: { clock.value })
        // Idle disabled: this test is about segmenting, and the real monitor
        // would read the actual machine's idle time and trim everything.
        let tracker = AppUsageTracker(archive: usage,
                                      ownBundleID: FocusConstants.bundleIdentifier,
                                      idle: .disabled,
                                      now: { clock.value })

        // Two hours in one app, then a switch.
        tracker.appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode")
        clock.advance(7_200)
        tracker.appActivated(bundleID: "com.apple.Safari", name: "Safari")
        clock.advance(600)
        tracker.suspend()

        expect(usage.sessions.count == 2, "two stretches, got \(usage.sessions.count)", &problems)
        expectClose(usage.sessions.first?.seconds ?? -1, 7_200, "Xcode stretch", &problems)
        expectClose(usage.sessions.last?.seconds ?? -1, 600, "Safari stretch", &problems)

        // A brief glance away and back continues the same session rather than
        // shattering a long stretch into fragments.
        tracker.appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode")
        clock.advance(1_800)
        tracker.appActivated(bundleID: "com.apple.Safari", name: "Safari")
        clock.advance(30)
        tracker.appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode")
        clock.advance(1_800)
        tracker.suspend()

        // Raw stretches are now kept apart on purpose: grouping joins them at
        // display time, non-destructively, so the threshold stays retunable.
        let xcode = usage.sessions.filter { $0.bundleID == "com.apple.dt.Xcode" }
        expect(xcode.count == 3, "raw stretches are kept, got \(xcode.count)", &problems)
        let segments = xcode.map {
            TimelineSegment(id: $0.id, bundleID: $0.bundleID, appName: $0.appName,
                            start: $0.start, end: $0.end, colorIndex: 0,
                            endReason: $0.endReason)
        }
        let grouped = AppSessionGrouper.group(segments, others: [])
        expect(grouped.count == 2,
               "grouping rejoins the glance into two sittings, got \(grouped.count)",
               &problems)

        // Sub-5s flickers are Cmd-Tab noise and are dropped entirely.
        let before = usage.sessions.count
        tracker.appActivated(bundleID: "com.flicker.app", name: "Flicker")
        clock.advance(2)
        tracker.suspend()
        expect(usage.sessions.count == before, "a 2s flicker must not be recorded", &problems)

        // Our own popover taking focus must not chop the user's stretch in two.
        tracker.appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode")
        clock.advance(300)
        tracker.appActivated(bundleID: FocusConstants.bundleIdentifier, name: "FocusContinuity")
        clock.advance(10)
        expect(tracker.currentBundleID == "com.apple.dt.Xcode",
               "our own activation must not end the stretch", &problems)

        // Disabling stops recording entirely.
        tracker.setEnabled(false)
        let afterDisable = usage.sessions.count
        tracker.appActivated(bundleID: "com.apple.Notes", name: "Notes")
        clock.advance(600)
        tracker.suspend()
        expect(usage.sessions.count == afterDisable, "disabled tracking records nothing",
               &problems)

        try? FileManager.default.removeItem(at: dir)
        return problems
    }

    /// A periodic checkpoint is a provisional view of one stretch, not an
    /// immutable fragment. An idle observation must be able to shorten that
    /// saved view before a later active stretch begins.
    static func testPeriodicCheckpointRollsBackIdleTail() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        var idle: TimeInterval = 0
        let tracker = AppUsageTracker(archive: usage,
                                      ownBundleID: FocusConstants.bundleIdentifier,
                                      idle: IdleMonitor(idleSeconds: { idle }),
                                      now: { clock.value })

        tracker.appActivated(bundleID: "com.example.editor", name: "Editor")
        clock.advance(60)
        tracker.flush()
        let firstCheckpointID = usage.sessions.first?.id
        clock.advance(60)
        tracker.flush()

        expect(usage.sessions.count == 1,
               "repeated checkpoints must retain one UUID, got \(usage.sessions.count)",
               &problems)
        expect(usage.sessions.first?.id == firstCheckpointID,
               "a periodic checkpoint must correct the original UUID", &problems)
        expect(usage.sessions.first?.endReason == .stillOpen,
               "an active checkpoint must remain provisional", &problems)
        expectClose(usage.totalToday() + tracker.unpersistedSeconds(), 120,
                    "saved checkpoints plus the live tail must not double-count", &problems)

        clock.advance(20 * 60)
        idle = 20 * 60
        tracker.flush()
        expect(usage.sessions.count == 1 && usage.sessions.first?.endReason == .idle,
               "idle must finalise the provisional checkpoint", &problems)
        expectClose(usage.totalToday(), 120,
                    "an idle tail must be removed from today total", &problems)
        expectClose(usage.totalToday() + tracker.unpersistedSeconds(), 120,
                    "a finalised checkpoint has no duplicated live tail", &problems)

        idle = 0
        tracker.confirmPresence(at: clock.value)
        clock.advance(60)
        tracker.flush()

        let ids = Set(usage.sessions.map(\.id))
        expect(ids.count == 2,
               "returning after idle must create exactly one new UUID, got \(ids.count)",
               &problems)
        expectClose(usage.totalToday(), 180,
                    "two active minutes, twenty idle minutes, then one active minute is 180s",
                    &problems)
        expectClose(usage.totalToday() + tracker.unpersistedSeconds(), 180,
                    "the returned stretch remains singly counted after checkpointing", &problems)
        return problems
    }
}
