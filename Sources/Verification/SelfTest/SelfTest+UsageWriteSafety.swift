import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    /// A manual clock correction is not evidence that already-recorded work did
    /// not happen. Ordinary flushes and closes retain the last durable boundary;
    /// an explicit idle observation may still correct it backwards.
    static func testUsageClockRegressionSafety() -> [String] {
        var problems: [String] = []

        do {
            let clock = TestClock(base)
            let directory = scratchDirectory()
            let usage = AppUsageArchive(directory: directory, now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            tracker.appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode")
            clock.advance(10 * 60)
            tracker.flush()
            expectClose(usage.sessions.first?.seconds ?? -1, 10 * 60,
                        "the initial checkpoint is durable", &problems)

            clock.value = base.addingTimeInterval(5 * 60)
            tracker.flush()
            expectClose(usage.sessions.first?.seconds ?? -1, 10 * 60,
                        "a non-idle flush cannot move before its durable end", &problems)
            clock.value = base.addingTimeInterval(4 * 60)
            tracker.suspend()
            expectClose(usage.sessions.first?.seconds ?? -1, 10 * 60,
                        "a non-idle finalisation cannot shorten durable usage", &problems)
            expect(!tracker.isObserving,
                   "a successful clamped finalisation still stops tracking", &problems)
        }

        do {
            let clock = TestClock(base)
            let directory = scratchDirectory()
            let usage = AppUsageArchive(directory: directory, now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            tracker.appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode")
            clock.advance(10 * 60)
            tracker.flush()
            clock.advance(100)
            tracker.observeIdle(seconds: 400)
            expectClose(usage.sessions.first?.seconds ?? -1, 5 * 60,
                        "explicit idle evidence may roll a checkpoint backwards", &problems)
            expect(tracker.currentBundleID == nil && tracker.isObserving,
                   "idle correction settles in waiting-for-presence", &problems)
        }

        return problems
    }

    /// Atomic persistence is the commit point. A failed write leaves cache,
    /// revision, callbacks and the tracker's durable boundary untouched so the
    /// exact same stretch can be retried after storage becomes writable.
    static func testUsageWriteFailureRollsBack() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let root = scratchDirectory()
        try? FileManager.default.createDirectory(at: root,
                                                 withIntermediateDirectories: true)
        let blocked = root.appendingPathComponent("blocked-storage")
        try? Data("not a directory".utf8).write(to: blocked)
        let usage = AppUsageArchive(directory: blocked, now: { clock.value })
        var callbacks = 0
        usage.onDidChange = { callbacks += 1 }
        let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                      idle: .disabled, now: { clock.value })
        tracker.appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode")
        clock.advance(10 * 60)
        tracker.flush()

        expect(usage.sessions.isEmpty,
               "a failed write rolls back the in-memory checkpoint", &problems)
        expect(usage.revision == 0 && callbacks == 0,
               "failed persistence publishes neither revision nor callback", &problems)
        expectClose(tracker.unpersistedSeconds(), 10 * 60,
                    "the failed checkpoint remains wholly retryable", &problems)

        try? FileManager.default.removeItem(at: blocked)
        try? FileManager.default.createDirectory(at: blocked,
                                                 withIntermediateDirectories: true)
        tracker.flush()
        expect(usage.sessions.count == 1 && usage.revision == 1 && callbacks == 1,
               "the repaired filesystem accepts and publishes one retry", &problems)
        expectClose(tracker.unpersistedSeconds(), 0,
                    "only the successful retry advances the durable boundary", &problems)
        let reloaded = AppUsageArchive(directory: blocked, now: { clock.value })
        expectClose(reloaded.sessions.first?.seconds ?? -1, 10 * 60,
                    "the successful retry exists on disk", &problems)

        clock.advance(60)
        let savedDirectory = root.appendingPathComponent("saved-storage")
        try? FileManager.default.moveItem(at: blocked, to: savedDirectory)
        try? Data("blocked again".utf8).write(to: blocked)
        tracker.suspend()
        expect(tracker.currentBundleID == nil && tracker.isObserving,
               "a failed terminal checkpoint freezes closed while remaining retryable", &problems)
        expectClose(tracker.unpersistedSeconds(), 60,
                    "a failed terminal checkpoint exposes only its frozen tail", &problems)
        expectClose(usage.sessions.first?.seconds ?? -1, 10 * 60,
                    "failed finalisation rolls the cache back to its durable record", &problems)
        expect(usage.revision == 1 && callbacks == 1,
               "failed finalisation remains unpublished", &problems)

        try? FileManager.default.removeItem(at: blocked)
        try? FileManager.default.moveItem(at: savedDirectory, to: blocked)
        tracker.suspend()
        expect(!tracker.isObserving && usage.revision == 2 && callbacks == 2,
               "repair lets the identical finalisation persist and stop", &problems)
        expectClose(usage.sessions.first?.seconds ?? -1, 11 * 60,
                    "the retried close retains the whole active stretch", &problems)
        return problems
    }

    /// A failed terminal checkpoint is an immutable event, not permission to
    /// keep accruing until storage recovers. Its unsaved tail stays visible,
    /// while a confirmed return waits behind that exact close as a new UUID.
    static func testFailedTerminalCheckpointRetainsOriginalBoundary() -> [String] {
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
            let originalID = usage.sessions.first?.id

            clock.advance(60)
            try? FileManager.default.moveItem(at: directory, to: savedDirectory)
            try? Data("blocked".utf8).write(to: directory)
            tracker.suspend()

            expectClose(usage.totalToday() + tracker.unpersistedSeconds(), 11 * 60,
                        "the failed close tail remains visible without accruing", &problems)

            clock.advance(20 * 60)
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.moveItem(at: savedDirectory, to: directory)
            tracker.flush()

            expect(usage.sessions.first?.id == originalID,
                   "a delayed retry must retain the original usage UUID", &problems)
            expectClose(usage.sessions.first?.seconds ?? -1, 11 * 60,
                        "a delayed retry must retain the original suspend boundary", &problems)
            expect(usage.sessions.first?.endReason == .systemLock,
                   "the delayed retry must retain the original terminal reason", &problems)
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
            let originalID = usage.sessions.first?.id

            clock.advance(60)
            try? FileManager.default.moveItem(at: directory, to: savedDirectory)
            try? Data("blocked".utf8).write(to: directory)
            tracker.suspend()

            clock.advance(4 * 60)
            let confirmedReturn = base.addingTimeInterval(15 * 60)
            tracker.prepareToResume(bundleID: "com.example.browser", name: "Browser")
            tracker.confirmPresence(at: confirmedReturn)

            clock.advance(20 * 60)
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.moveItem(at: savedDirectory, to: directory)
            tracker.flush()
            tracker.flush()

            let oldSession = usage.sessions.first { $0.id == originalID }
            let returnedSession = usage.sessions.first { $0.id != originalID }
            expectClose(oldSession?.seconds ?? -1, 11 * 60,
                        "a queued return must not extend the failed close", &problems)
            expect(oldSession?.endReason == .systemLock,
                   "a queued return must not replace the failed close reason", &problems)
            expect(returnedSession?.bundleID == "com.example.browser",
                   "the queued return must retain its candidate app", &problems)
            expectClose(returnedSession?.start.timeIntervalSince(base) ?? -1, 15 * 60,
                        "the new UUID must begin at the confirmed return", &problems)
        }

        return problems
    }
}
