import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    /// Pending usage is the current truth for its stable UUID. It replaces a
    /// durable checkpoint in memory—possibly with an earlier end—and supplies
    /// queued UUIDs to the live, dashboard, period, goal and reward paths while
    /// the on-disk archive remains untouched.
    static func testAuthoritativePendingUsageOverlay() -> [String] {
        var problems: [String] = []

        do {
            let clock = TestClock(base)
            let root = scratchDirectory()
            let directory = root.appendingPathComponent("usage")
            let savedDirectory = root.appendingPathComponent("saved-usage")
            let usage = AppUsageArchive(directory: directory, now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            let engine = makeEngine(clock)
            engine.start(workType: .deepWork, intent: "Correct checkpoint")

            tracker.appActivated(bundleID: "com.example.editor", name: "Editor")
            clock.advance(10 * 60)
            tracker.flush()
            let stableID = usage.sessions.first?.id
            clock.advance(2 * 60)
            try? FileManager.default.moveItem(at: directory, to: savedDirectory)
            try? Data("blocked".utf8).write(to: directory)
            tracker.observeIdle(seconds: 7 * 60)

            let store = SessionStore(engine: engine, now: { clock.value })
            store.attach(tracker: tracker, usage: usage)
            store.setDashboardVisible(true)

            expectClose(usage.sessions.first?.seconds ?? -1, 10 * 60,
                        "the durable archive remains untouched while correction is pending",
                        &problems)
            expectClose(store.trackedToday, 5 * 60,
                        "the live tracked total replaces the durable checkpoint", &problems)
            expectClose(store.goal.achieved, 5 * 60,
                        "the live goal uses the corrected hands-on interval", &problems)
            expectClose(store.trackedForSelectedDay, 5 * 60,
                        "the dashboard total uses the corrected interval", &problems)
            expectClose(store.rankedApps.first?.total ?? -1, 5 * 60,
                        "the dashboard app ranking uses the corrected interval", &problems)
            expect(store.timelineSegments.count == 1
                       && store.timelineSegments.first?.id == stableID,
                   "the dashboard keeps one stable corrected UUID", &problems)

            let rewardUsage = AppUsageSnapshot(archive: usage, tracker: tracker).sessions
            expect(rewardUsage.count == 1 && rewardUsage.first?.id == stableID,
                   "the reward path replaces rather than duplicates the pending UUID", &problems)
            expectClose(rewardUsage.first?.seconds ?? -1, 5 * 60,
                        "the reward path sees the backward correction", &problems)
        }

        do {
            let clock = TestClock(base)
            let root = scratchDirectory()
            let directory = root.appendingPathComponent("usage")
            let savedDirectory = root.appendingPathComponent("saved-usage")
            let usage = AppUsageArchive(directory: directory, now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            let engine = makeEngine(clock)

            tracker.appActivated(bundleID: "com.example.editor", name: "Editor")
            clock.advance(10 * 60)
            tracker.flush()
            clock.advance(60)
            try? FileManager.default.moveItem(at: directory, to: savedDirectory)
            try? Data("blocked".utf8).write(to: directory)
            tracker.suspend()
            clock.advance(4 * 60)
            tracker.prepareToResume(bundleID: "com.example.browser", name: "Browser")
            tracker.confirmPresence(at: clock.value)
            clock.advance(5 * 60)
            tracker.appActivated(bundleID: "com.example.xcode", name: "Xcode")
            clock.advance(5 * 60)

            let store = SessionStore(engine: engine, now: { clock.value })
            store.attach(tracker: tracker, usage: usage)
            store.setDashboardVisible(true)

            expectClose(store.trackedForSelectedDay, 21 * 60,
                        "the Day dashboard includes every queued confirmed interval", &problems)
            expectClose(store.rankedApps.reduce(0) { $0 + $1.total }, 21 * 60,
                        "the Day app rows reconcile with the queued total", &problems)
            expect(Set(store.timelineSegments.map(\.id)).count == 3,
                   "the Day timeline contains the three authoritative UUIDs", &problems)

            store.period = .week
            expectClose(store.periodSummary.tracked, 21 * 60,
                        "the Week total includes every queued confirmed interval", &problems)
            expectClose(store.periodDays.reduce(0) { $0 + $1.tracked }, 21 * 60,
                        "the Week bars reconcile with their queued total", &problems)

            store.period = .month
            expectClose(store.periodSummary.tracked, 21 * 60,
                        "the Month total includes every queued confirmed interval", &problems)
            expectClose(store.periodDays.reduce(0) { $0 + $1.tracked }, 21 * 60,
                        "the Month bars reconcile with their queued total", &problems)
            expectClose(usage.sessions.first?.seconds ?? -1, 10 * 60,
                        "period views do not rewrite the durable checkpoint", &problems)
        }

        return problems
    }

    /// Migration and corrupt-file handling are preservation operations. If the
    /// destination cannot be created, the original bytes stay in place and no
    /// later mutation is allowed to overwrite them in that process.
    static func testUsagePreservationFailureFailsClosed() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let manager = FileManager.default

        do {
            let directory = scratchDirectory()
            try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("app-usage.json")
            let legacy = [AppUsageSession(bundleID: "com.apple.dt.Xcode", appName: "Xcode",
                                          start: base, end: base.addingTimeInterval(600))]
            let original = (try? JSONEncoder().encode(legacy)) ?? Data()
            try? original.write(to: file)
            let backup = directory.appendingPathComponent(
                "app-usage-v1-backup-\(Int(clock.value.timeIntervalSince1970)).json")
            try? manager.createDirectory(at: backup, withIntermediateDirectories: true)

            let usage = AppUsageArchive(directory: directory, now: { clock.value })
            let mutation = usage.record(AppUsageSession(
                bundleID: "com.microsoft.VSCode", appName: "Visual Studio Code",
                start: base.addingTimeInterval(700), end: base.addingTimeInterval(800)))
            expect(usage.sessions == legacy,
                   "failed backup still exposes the safely decoded legacy history", &problems)
            expect(usage.isReadOnly && !mutation,
                   "failed legacy preservation makes mutations fail closed", &problems)
            expect((try? Data(contentsOf: file)) == original,
                   "failed legacy backup leaves the source bytes untouched", &problems)
            expect(usage.revision == 0 && usage.legacyBackupURL == nil,
                   "failed migration publishes no revision or backup", &problems)
        }

        do {
            let directory = scratchDirectory()
            try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("app-usage.json")
            let original = Data("not valid usage json".utf8)
            try? original.write(to: file)
            // A taken name no longer blocks the move; a folder that cannot be
            // written does.
            try? manager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
            defer { try? manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }

            let usage = AppUsageArchive(directory: directory, now: { clock.value })
            let mutation = usage.record(AppUsageSession(
                bundleID: "com.apple.dt.Xcode", appName: "Xcode",
                start: base, end: base.addingTimeInterval(600)))
            expect(usage.isReadOnly && !mutation,
                   "failed corrupt-file preservation makes mutations fail closed", &problems)
            expect((try? Data(contentsOf: file)) == original,
                   "failed corrupt move preserves the unreadable source bytes", &problems)
            expect(usage.sessions.isEmpty && usage.revision == 0,
                   "unreadable evidence is not invented or published", &problems)
        }
        return problems
    }

    /// A safely decodable future envelope is useful for display, but this build
    /// cannot know how to preserve its semantics. It therefore rejects writes
    /// and leaves even unknown fields byte-for-byte intact.
    static func testFutureUsageSchemaIsReadOnly() -> [String] {
        struct FutureEnvelope: Codable {
            let metadata: AppUsageMetadata
            let sessions: [AppUsageSession]
            let futureField: String
        }

        var problems: [String] = []
        let clock = TestClock(base)
        let directory = scratchDirectory()
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("app-usage.json")
        let existing = AppUsageSession(bundleID: "com.apple.dt.Xcode", appName: "Xcode",
                                       start: base, end: base.addingTimeInterval(600))
        let original = (try? JSONEncoder().encode(FutureEnvelope(
            metadata: AppUsageMetadata(schemaVersion: 99, accurateFrom: base),
            sessions: [existing], futureField: "must survive"))) ?? Data()
        try? original.write(to: file)

        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        var callbacks = 0
        usage.onDidChange = { callbacks += 1 }
        let mutation = usage.record(AppUsageSession(
            bundleID: "com.microsoft.VSCode", appName: "Visual Studio Code",
            start: base.addingTimeInterval(700), end: base.addingTimeInterval(800)))

        expect(usage.sessions == [existing] && usage.metadata.schemaVersion == 99,
               "a safely decoded future envelope remains available for display", &problems)
        expect(usage.isReadOnly && !mutation,
               "an unsupported schema rejects mutation", &problems)
        expect(usage.revision == 0 && callbacks == 0,
               "a rejected future-schema write publishes nothing", &problems)
        expect((try? Data(contentsOf: file)) == original,
               "future schema bytes and unknown fields remain identical", &problems)
        return problems
    }
}
