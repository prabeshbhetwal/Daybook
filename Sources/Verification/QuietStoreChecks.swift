import Foundation
import Combine

/// What the store does when nothing is asked of it: with no session running a
/// tick must not wake every view that watches the store, and a power reading
/// must not throw away the story of a day that is over. Every fixture owns
/// isolated preferences and scratch folders, and a clock the check moves.
enum QuietStoreChecks: CheckSuite {

    static let tests: [(String, () -> [String])] = [
        ("An idle store publishes nothing on a tick, with an app in front", idleTickPublishesNothing),
        ("A power reading keeps the cached story of a finished day", powerReadingKeepsFinishedDay)
    ]

    private static func idleTickPublishesNothing() -> [String] {
        MainActor.assumeIsolated {
            let clock = TestClock(SelfTest.base)
            guard let fixture = makeStore(clock) else { return ["Could not create isolated preferences"] }
            defer { fixture.cleanUp() }
            // A session that has ended leaves the engine's own clock counting
            // from its start; nothing on screen reads it while idle.
            fixture.engine.start(workType: .deepWork, intent: "Done")
            clock.advance(600)
            _ = fixture.engine.stop()
            fixture.store.catchUpWithEngine()
            // An app in front is an open stretch that grows every second.
            fixture.tracker.appActivated(bundleID: "com.example.editor", name: "Editor")
            clock.advance(60)
            fixture.store.updateTimeDrivenFigures()

            var problems: [String] = []
            var publications = 0
            let observer = fixture.store.objectWillChange.sink { _ in publications += 1 }
            defer { observer.cancel() }
            for _ in 0..<5 {
                clock.advance(1)
                fixture.store.updateTimeDrivenFigures()
            }
            expect(publications == 0,
                   "five idle ticks published \(publications) times; each wakes every observer", &problems)
            expect(fixture.store.elapsed == 0,
                   "an idle store published \(fixture.store.elapsed)s as the session clock", &problems)
            return problems
        }
    }

    private static func powerReadingKeepsFinishedDay() -> [String] {
        MainActor.assumeIsolated {
            let clock = TestClock(SelfTest.base)
            let monitor = SessionMetadataChecks.FakePowerMonitor(sample: PowerObservation(
                timestamp: clock.value, source: .battery, percentage: 80, charging: .notCharging))
            guard let fixture = makeStore(clock, powerMonitor: monitor) else {
                return ["Could not create isolated preferences"]
            }
            defer { fixture.cleanUp() }
            let calendar = Calendar.current
            guard let yesterday = calendar.date(byAdding: .day, value: -1,
                                                to: calendar.startOfDay(for: clock.value)) else {
                return ["Could not build the day before"]
            }
            let start = yesterday.addingTimeInterval(10 * 3_600)
            fixture.engine.archive.append(SessionRecord(name: "Finished", workType: .deepWork,
                start: start, end: start.addingTimeInterval(3_600), workSeconds: 3_600))
            _ = fixture.store.storyDayProjection(on: yesterday)
            let cached = fixture.store.storyProjectionCache.count

            var problems: [String] = []
            expect(cached >= 1, "a finished day's story was not cached when built", &problems)
            monitor.handler?(PowerObservation(timestamp: clock.value, source: .external,
                                              percentage: 90, charging: .charging))
            expect(fixture.store.storyProjectionCache.count == cached,
                   "a power reading emptied the cache: \(cached) stories before, "
                   + "\(fixture.store.storyProjectionCache.count) after", &problems)
            return problems
        }
    }

    private static func makeStore(_ clock: TestClock, powerMonitor: PowerSourceMonitoring? = nil)
        -> (store: SessionStore, engine: SessionEngine, tracker: AppUsageTracker,
            cleanUp: () -> Void)? {
        let directory = SelfTest.scratchDirectory()
        let suiteName = "com.prabesh.daybook.quiet-store.\(UUID().uuidString)"
        guard let defaults = MemoryDefaults.suite(named: suiteName) else { return nil }
        defaults.removePersistentDomain(forName: suiteName)
        let engine = SessionEngine(store: PersistenceStore(defaults: defaults),
                                   archive: SessionArchive(directory: directory, now: { clock.value }),
                                   ownBundleID: "com.example.quiet", schedulesDwell: false,
                                   now: { clock.value })
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.quiet",
                                      idle: .disabled, now: { clock.value })
        let store = SessionStore(engine: engine, schedulesTicker: false,
                                 powerMonitor: powerMonitor, now: { clock.value })
        store.attach(tracker: tracker, usage: usage)
        return (store, engine, tracker, {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suiteName)
        })
    }
}
