import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    /// The callback is a lifecycle boundary, not an early mutation notice. A
    /// same-app confirmation must publish active, and suspend must publish
    /// stopped only after its checkpoint has settled.
    static func testUsageTrackerLifecycleCallbacks() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let directory = scratchDirectory()
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                      idle: .disabled, now: { clock.value })
        var states: [(bundleID: String?, observing: Bool)] = []
        tracker.onDidTransition = {
            states.append((tracker.currentBundleID, tracker.isObserving))
        }

        tracker.prepareToResume(bundleID: "com.apple.dt.Xcode", name: "Xcode")
        tracker.confirmPresence(at: clock.value)
        tracker.appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode")
        clock.advance(10 * 60)
        tracker.suspend()

        expect(states.count == 3,
               "waiting, confirmed active and suspended each publish once; got \(states.count)",
               &problems)
        if states.count == 3 {
            expect(states[0].bundleID == nil && states[0].observing,
                   "the waiting callback sees the final waiting state", &problems)
            expect(states[1].bundleID == "com.apple.dt.Xcode" && states[1].observing,
                   "same-app confirmation callback sees the final active state", &problems)
            expect(states[2].bundleID == nil && !states[2].observing,
                   "suspend callback sees the final stopped state", &problems)
        }
        expect(usage.sessions.count == 1,
               "suspend still commits the completed usage stretch", &problems)

        weak var releasedUsage: AppUsageArchive?
        weak var releasedTracker: AppUsageTracker?
        do {
            let lifecycleClock = TestClock(base)
            let lifecycleDirectory = scratchDirectory()
            let lifecycleUsage = AppUsageArchive(directory: lifecycleDirectory,
                                                 now: { lifecycleClock.value })
            let lifecycleTracker = AppUsageTracker(
                archive: lifecycleUsage, ownBundleID: "com.example.self",
                idle: .disabled, now: { lifecycleClock.value })
            let lifecycleStore = SessionStore(engine: makeEngine(lifecycleClock))
            lifecycleStore.attach(tracker: lifecycleTracker, usage: lifecycleUsage)
            releasedUsage = lifecycleUsage
            releasedTracker = lifecycleTracker
        }
        expect(releasedUsage == nil && releasedTracker == nil,
               "store attachment must not retain a usage archive/tracker cycle", &problems)
        return problems
    }

    // MARK: - Usage storage persistence

    /// A migration must change only the outer JSON container. The original
    /// bytes remain available for recovery, and every historical session field
    /// survives exactly as recorded.
    static func testLegacyUsageMigrationPreservesHistory() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base.addingTimeInterval(12_345))
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstID = UUID()
        let secondID = UUID()
        let legacy = "[\n"
            + "  {\"id\":\"\(firstID.uuidString)\",\"bundleID\":\"com.example.editor\","
            + "\"appName\":\"Editor\",\"start\":\(base.timeIntervalSinceReferenceDate),"
            + "\"end\":\(base.addingTimeInterval(600).timeIntervalSinceReferenceDate),"
            + "\"endReason\":\"idle\"},\n"
            + "  {\"id\":\"\(secondID.uuidString)\",\"bundleID\":\"com.example.browser\","
            + "\"appName\":\"Browser\",\"start\":\(base.addingTimeInterval(900).timeIntervalSinceReferenceDate),"
            + "\"end\":\(base.addingTimeInterval(1_500).timeIntervalSinceReferenceDate),"
            + "\"endReason\":\"appSwitch\"}\n"
            + "]\n"
        let originalBytes = Data(legacy.utf8)
        let usageURL = directory.appendingPathComponent("app-usage.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? originalBytes.write(to: usageURL)

        let migrated = AppUsageArchive(directory: directory, now: { clock.value })
        let expected = [
            AppUsageSession(id: firstID, bundleID: "com.example.editor", appName: "Editor",
                            start: base, end: base.addingTimeInterval(600), endReason: .idle),
            AppUsageSession(id: secondID, bundleID: "com.example.browser", appName: "Browser",
                            start: base.addingTimeInterval(900), end: base.addingTimeInterval(1_500),
                            endReason: .appSwitch)
        ]

        expect(migrated.sessions == expected,
               "migration must preserve every historical session field", &problems)
        expect(migrated.metadata.schemaVersion == 2,
               "migrated storage must identify itself as schema v2", &problems)
        expect(migrated.metadata.accurateFrom == clock.value,
               "migration must record when corrected usage becomes authoritative", &problems)
        guard let backupURL = migrated.legacyBackupURL else {
            problems.append("migration must retain a discoverable v1 backup URL")
            return problems
        }
        expect((try? Data(contentsOf: backupURL)) == originalBytes,
               "v1 backup must preserve the original bytes exactly", &problems)
        let migratedObject = try? JSONSerialization.jsonObject(with: Data(contentsOf: usageURL)) as? [String: Any]
        expect(migratedObject?["metadata"] != nil && migratedObject?["sessions"] != nil,
               "app-usage.json must be rewritten as a v2 envelope", &problems)

        let reloaded = AppUsageArchive(directory: directory, now: { clock.value.addingTimeInterval(60) })
        expect(reloaded.sessions == expected,
               "the v2 envelope must reload without changing history", &problems)
        expect(reloaded.metadata == migrated.metadata,
               "the authoritative date must persist in the v2 envelope", &problems)
        return problems
    }

    /// A checkpoint corrects its stable stretch rather than appending a fragment;
    /// meaningful mutations notify exactly once, while no-op corrections do not.
    static func testUsageCheckpointReplacesByIdentity() -> [String] {
        var problems: [String] = []
        let clock = TestClock(base)
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = AppUsageArchive(directory: directory, now: { clock.value })
        var notifications = 0
        archive.onDidChange = { notifications += 1 }
        let identity = UUID()
        let original = AppUsageSession(id: identity, bundleID: "com.example.editor", appName: "Editor",
                                       start: base, end: base.addingTimeInterval(60), endReason: .stillOpen)

        archive.checkpoint(original)
        expect(archive.sessions == [original], "the first checkpoint must create one record", &problems)
        expect(archive.revision == 1 && notifications == 1,
               "creating a checkpoint must revise and notify once", &problems)

        let corrected = AppUsageSession(id: identity, bundleID: "com.example.editor", appName: "Editor",
                                        start: base, end: base.addingTimeInterval(120), endReason: .stillOpen)
        archive.checkpoint(corrected)
        expect(archive.sessions == [corrected],
               "a checkpoint with the same UUID must replace, not append", &problems)
        expect(archive.revision == 2 && notifications == 2,
               "a corrected checkpoint must revise and notify once", &problems)

        archive.checkpoint(corrected)
        expect(archive.revision == 2 && notifications == 2,
               "an unchanged checkpoint must not revise or notify", &problems)

        let trimmedBelowMinimum = AppUsageSession(id: identity, bundleID: "com.example.editor",
                                                  appName: "Editor", start: base,
                                                  end: base.addingTimeInterval(4), endReason: .idle)
        archive.checkpoint(trimmedBelowMinimum)
        expect(archive.sessions.isEmpty,
               "a corrected checkpoint below five seconds must remove its record", &problems)
        expect(archive.revision == 3 && notifications == 3,
               "removing a corrected record must revise and notify once", &problems)

        archive.checkpoint(trimmedBelowMinimum)
        expect(archive.revision == 3 && notifications == 3,
               "discarding an absent short checkpoint must be a no-op", &problems)

        let appended = AppUsageSession(bundleID: "com.example.browser", appName: "Browser",
                                       start: base.addingTimeInterval(180),
                                       end: base.addingTimeInterval(240))
        expect(archive.record(appended), "a real segment is recorded", &problems)
        expect(archive.revision == 4 && notifications == 4,
               "recording a segment must revise and notify once", &problems)
        let rejected = AppUsageSession(bundleID: "com.example.short", appName: "Short",
                                       start: base.addingTimeInterval(300),
                                       end: base.addingTimeInterval(304))
        expect(!archive.record(rejected), "a sub-floor segment is rejected", &problems)
        expect(archive.revision == 4 && notifications == 4,
               "rejecting a segment must not revise or notify", &problems)

        // A correction is a replacement, never an insertion, and a genuinely
        // new UUID is added without evicting anything: history has no cap.
        let capacityDirectory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: capacityDirectory) }
        try? FileManager.default.createDirectory(at: capacityDirectory,
                                                 withIntermediateDirectories: true)
        let capacity = 25_000
        let stored = (0..<capacity).map { offset in
            AppUsageSession(id: UUID(), bundleID: "com.example.\(offset)",
                            appName: "App \(offset)",
                            start: base.addingTimeInterval(Double(offset) * 10),
                            end: base.addingTimeInterval(Double(offset) * 10 + 5))
        }
        let legacyURL = capacityDirectory.appendingPathComponent("app-usage.json")
        try? JSONEncoder().encode(stored).write(to: legacyURL)
        let bounded = AppUsageArchive(directory: capacityDirectory, now: { clock.value })
        let correctedOldest = AppUsageSession(id: stored[0].id,
                                              bundleID: stored[0].bundleID,
                                              appName: stored[0].appName,
                                              start: stored[0].start,
                                              end: stored[0].end.addingTimeInterval(60),
                                              endReason: .stillOpen)
        bounded.checkpoint(correctedOldest)
        expect(bounded.sessions.count == capacity && bounded.sessions.contains(correctedOldest)
               && bounded.sessions.contains(where: { $0.id == stored[1].id }),
               "correcting an existing UUID must not evict another record", &problems)

        let newIdentity = AppUsageSession(bundleID: "com.example.new", appName: "New",
                                          start: base.addingTimeInterval(999_999),
                                          end: base.addingTimeInterval(1_000_004))
        bounded.checkpoint(newIdentity)
        expect(bounded.sessions.count == capacity + 1 && bounded.sessions.contains(newIdentity)
               && bounded.sessions.contains(correctedOldest),
               "a new UUID beyond the old 20,000 cap keeps every earlier record", &problems)
        let reopened = AppUsageArchive(directory: capacityDirectory, now: { clock.value })
        expect(reopened.sessions.count == capacity + 1 && reopened.sessions.contains(newIdentity),
               "the uncapped history survives a relaunch", &problems)
        return problems
    }
}
