import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    /// Once presence confirms a queued app, its UUID and start are facts. A
    /// later app switch or suspension may close that interval, but cannot
    /// replace, rebase or discard it while an earlier close is still unwritable.
    static func testConfirmedPendingUsageSurvivesLaterLifecycleEvents() -> [String] {
        var problems: [String] = []

        do {
            let clock = TestClock(base)
            let root = scratchDirectory()
            let directory = root.appendingPathComponent("usage")
            let savedDirectory = root.appendingPathComponent("saved-usage")
            let usage = AppUsageArchive(directory: directory, now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })

            tracker.appActivated(bundleID: "com.example.editor", name: "Editor")
            clock.advance(10 * 60)
            tracker.flush()
            clock.advance(60)
            try? FileManager.default.moveItem(at: directory, to: savedDirectory)
            try? Data("blocked".utf8).write(to: directory)
            tracker.suspend()

            clock.advance(4 * 60)
            tracker.prepareToResume(bundleID: "com.example.browser", name: "Browser")
            tracker.confirmPresence(at: base.addingTimeInterval(15 * 60))
            clock.advance(5 * 60)
            let confirmedBrowserID = tracker.unpersistedSession()?.id
            tracker.appActivated(bundleID: "com.example.xcode", name: "Xcode")

            expectClose(usage.totalToday() + tracker.unpersistedSeconds(), 16 * 60,
                        "a later activation must retain confirmed Browser usage", &problems)

            clock.advance(5 * 60)
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.moveItem(at: savedDirectory, to: directory)
            tracker.flush()
            tracker.flush()

            let editor = usage.sessions.first { $0.bundleID == "com.example.editor" }
            let browser = usage.sessions.first { $0.bundleID == "com.example.browser" }
            let xcode = usage.sessions.first { $0.bundleID == "com.example.xcode" }
            expectClose(editor?.seconds ?? -1, 11 * 60,
                        "the earlier failed close remains frozen through a later switch", &problems)
            expect(editor?.endReason == .systemLock,
                   "the earlier failed close retains its terminal reason after a later switch",
                   &problems)
            expectClose(browser?.start.timeIntervalSince(base) ?? -1, 15 * 60,
                        "Browser retains the confirmed start before a later switch", &problems)
            expectClose(browser?.seconds ?? -1, 5 * 60,
                        "Browser closes at the intervening activation", &problems)
            expect(browser?.id == confirmedBrowserID,
                   "Browser retains the UUID created by confirmed presence", &problems)
            expect(browser?.endReason == .appSwitch,
                   "the intervening activation closes Browser as an app switch", &problems)
            expectClose(xcode?.start.timeIntervalSince(base) ?? -1, 20 * 60,
                        "Xcode starts at its own activation without rebasing Browser", &problems)
            expect(Set(usage.sessions.map(\.id)).count == 3,
                   "each preserved interval must retain a distinct UUID", &problems)
        }

        do {
            let clock = TestClock(base)
            let root = scratchDirectory()
            let directory = root.appendingPathComponent("usage")
            let savedDirectory = root.appendingPathComponent("saved-usage")
            let usage = AppUsageArchive(directory: directory, now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })

            tracker.appActivated(bundleID: "com.example.editor", name: "Editor")
            clock.advance(10 * 60)
            tracker.flush()
            clock.advance(60)
            try? FileManager.default.moveItem(at: directory, to: savedDirectory)
            try? Data("blocked".utf8).write(to: directory)
            tracker.suspend()

            clock.advance(4 * 60)
            tracker.prepareToResume(bundleID: "com.example.browser", name: "Browser")
            tracker.confirmPresence(at: base.addingTimeInterval(15 * 60))
            clock.advance(5 * 60)
            let confirmedBrowserID = tracker.unpersistedSession()?.id
            tracker.suspend()

            expectClose(usage.totalToday() + tracker.unpersistedSeconds(), 16 * 60,
                        "suspension must retain confirmed Browser usage", &problems)

            clock.advance(5 * 60)
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.moveItem(at: savedDirectory, to: directory)
            tracker.flush()

            let editor = usage.sessions.first { $0.bundleID == "com.example.editor" }
            let browser = usage.sessions.first { $0.bundleID == "com.example.browser" }
            expectClose(editor?.seconds ?? -1, 11 * 60,
                        "terminal queuing must not move the earlier failed close", &problems)
            expectClose(browser?.start.timeIntervalSince(base) ?? -1, 15 * 60,
                        "terminal queuing retains Browser's confirmed start", &problems)
            expectClose(browser?.seconds ?? -1, 5 * 60,
                        "suspension closes the confirmed Browser interval", &problems)
            expect(browser?.id == confirmedBrowserID,
                   "suspension retains the confirmed Browser UUID", &problems)
            expect(browser?.endReason == .systemLock,
                   "suspension retains Browser's terminal reason", &problems)
            expect(Set(usage.sessions.map(\.id)).count == 2,
                   "terminal queuing preserves both stable UUIDs", &problems)
            expect(!tracker.isObserving,
                   "recovery after queued suspension settles stopped", &problems)
        }

        return problems
    }

    /// Scalar and interval consumers must see the same disjoint unsaved facts:
    /// Editor's one-minute tail, Browser's five-minute close and Xcode's live
    /// five minutes, without filling the four-minute absence between them.
    static func testQueuedUsageIntervalsFeedFocusedActiveTotals() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let root = scratchDirectory()
        let directory = root.appendingPathComponent("usage")
        let savedDirectory = root.appendingPathComponent("saved-usage")
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                      idle: .disabled, now: { clock.value })
        let engine = makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Reconcile queued usage")

        tracker.appActivated(bundleID: "com.example.editor", name: "Editor")
        clock.advance(10 * 60)
        tracker.flush()
        clock.advance(60)
        try? FileManager.default.moveItem(at: directory, to: savedDirectory)
        try? Data("blocked".utf8).write(to: directory)
        tracker.suspend()

        clock.advance(4 * 60)
        tracker.prepareToResume(bundleID: "com.example.browser", name: "Browser")
        tracker.confirmPresence(at: base.addingTimeInterval(15 * 60))
        clock.advance(5 * 60)
        tracker.appActivated(bundleID: "com.example.xcode", name: "Xcode")
        clock.advance(5 * 60)

        let store = SessionStore(engine: engine, now: { clock.value })
        store.attach(tracker: tracker, usage: usage)

        expectClose(store.trackedToday, 21 * 60,
                    "scalar tracked time includes every disjoint queued interval", &problems)
        expectClose(store.goal.achieved, 21 * 60,
                    "focused-active time includes every disjoint queued interval", &problems)

        let rewardUsage = AppUsageSnapshot(archive: usage, tracker: tracker).sessions
        let rewardGoal = DailyGoal(archive: engine.archive,
                                   goal: engine.store.dailyGoal,
                                   usage: rewardUsage,
                                   usageAccurateFrom: usage.metadata.accurateFrom,
                                   running: engine.runningSpan,
                                   runningWork: engine.elapsedToday(),
                                   now: { clock.value })
        expectClose(rewardGoal.achievedToday(), 21 * 60,
                    "reward focused-active time includes every disjoint queued interval",
                    &problems)
        return problems
    }

    /// Persistence state, not the size of an additive tail, drives the existing
    /// minute cadence. A short terminal close and an idle correction behind the
    /// durable checkpoint are both immutable pending writes that must retry.
    static func testPendingUsageRetriesWithoutTailThreshold() -> [String] {
        var problems: [String] = []

        do {
            let clock = TestClock(base)
            let root = scratchDirectory()
            let directory = root.appendingPathComponent("usage")
            let savedDirectory = root.appendingPathComponent("saved-usage")
            let usage = AppUsageArchive(directory: directory, now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })

            tracker.appActivated(bundleID: "com.example.editor", name: "Editor")
            clock.advance(10 * 60)
            tracker.flush()
            clock.advance(30)
            try? FileManager.default.moveItem(at: directory, to: savedDirectory)
            try? Data("blocked".utf8).write(to: directory)
            tracker.suspend()

            expectClose(tracker.unpersistedSeconds(), 30,
                        "the failed terminal close has only a sub-minute tail", &problems)
            expect(tracker.openSeconds(exceeds: 60),
                   "a sub-minute pending close must request the persistence cadence", &problems)

            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.moveItem(at: savedDirectory, to: directory)
            if tracker.openSeconds(exceeds: 60) { tracker.flush() }
            expectClose(usage.sessions.first?.seconds ?? -1, 10.5 * 60,
                        "the cadence retries and persists the short frozen close", &problems)
        }

        do {
            let clock = TestClock(base)
            let root = scratchDirectory()
            let directory = root.appendingPathComponent("usage")
            let savedDirectory = root.appendingPathComponent("saved-usage")
            let usage = AppUsageArchive(directory: directory, now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })

            tracker.appActivated(bundleID: "com.example.editor", name: "Editor")
            clock.advance(10 * 60)
            tracker.flush()
            clock.advance(2 * 60)
            try? FileManager.default.moveItem(at: directory, to: savedDirectory)
            try? Data("blocked".utf8).write(to: directory)
            tracker.observeIdle(seconds: 7 * 60)

            expectClose(tracker.unpersistedSeconds(), 0,
                        "a backward correction has no additive tail", &problems)
            expect(tracker.openSeconds(exceeds: 60),
                   "a backward correction must still request the persistence cadence", &problems)

            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.moveItem(at: savedDirectory, to: directory)
            if tracker.openSeconds(exceeds: 60) { tracker.flush() }
            expectClose(usage.sessions.first?.seconds ?? -1, 5 * 60,
                        "the cadence retries and persists the backward correction", &problems)
            expect(usage.sessions.first?.endReason == .idle,
                   "the retried correction retains its idle reason", &problems)
        }

        return problems
    }
}
