import Foundation
import SwiftUI
import Combine
import AppKit

extension SelfTest {
    /// The open tail is real hands-on evidence before the next checkpoint. It
    /// must advance both the goal and tracked scalar each tick, while the latter
    /// counts only the tail intersecting the current local day.
    static func testLiveUsageFeedsGoalAndClipsMidnight() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: anchoredNow())

        do {
            let clock = TestClock(dayStart.addingTimeInterval(10 * 3_600))
            let directory = scratchDirectory()
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard
            let persistence = PersistenceStore(defaults: defaults)
            persistence.removeAll()
            let engine = SessionEngine(store: persistence,
                                       archive: SessionArchive(directory: directory,
                                                               now: { clock.value }),
                                       ownBundleID: "com.example.self", schedulesDwell: false,
                                       now: { clock.value })
            engine.start(workType: .deepWork, intent: "Live work")
            let usage = AppUsageArchive(directory: directory, now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            tracker.appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode")
            let store = SessionStore(engine: engine, now: { clock.value })
            store.attach(tracker: tracker, usage: usage)
            clock.advance(90)
            store.updateTimeDrivenFigures()

            expect(usage.sessions.isEmpty,
                   "the between-checkpoint test retains a wholly live tail", &problems)
            expectClose(tracker.unpersistedSession()?.seconds ?? -1, 90,
                        "the tracker exposes the exact unpersisted live session", &problems)
            expectClose(store.goal.achieved, 90,
                        "live hands-on time advances focused-active goal progress", &problems)
            expectClose(store.trackedToday, 90,
                        "live tracked time advances between checkpoints", &problems)
        }

        do {
            let start = dayStart.addingTimeInterval(23 * 3_600 + 59 * 60)
            let clock = TestClock(start)
            let directory = scratchDirectory()
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard
            let persistence = PersistenceStore(defaults: defaults)
            persistence.removeAll()
            let engine = SessionEngine(store: persistence,
                                       archive: SessionArchive(directory: directory,
                                                               now: { clock.value }),
                                       ownBundleID: "com.example.self", schedulesDwell: false,
                                       now: { clock.value })
            engine.start(workType: .deepWork, intent: "Midnight work")
            let usage = AppUsageArchive(directory: directory, now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            tracker.appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode")
            let store = SessionStore(engine: engine, now: { clock.value })
            store.attach(tracker: tracker, usage: usage)
            clock.advance(2 * 60)
            store.updateTimeDrivenFigures()

            expectClose(tracker.unpersistedSession()?.seconds ?? -1, 2 * 60,
                        "the exposed live session keeps its full cross-midnight interval", &problems)
            expectClose(tracker.unpersistedSeconds(on: clock.value, calendar: calendar), 60,
                        "the tracker clips the live scalar to the new local day", &problems)
            expectClose(store.trackedToday, 60,
                        "today's tracked scalar excludes yesterday's live minute", &problems)
            expectClose(store.goal.achieved, 60,
                        "today's goal intersects only the post-midnight live minute", &problems)
        }
        return problems
    }

    /// The historical median is deliberately cached, but the existing ticker
    /// must advance that cache at local minute boundaries even when no archive,
    /// state or window event triggers a full refresh.
    static func testHistoricalPaceRefreshesOnMinuteBoundary() -> [String] {
        var problems: [String] = []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: anchoredNow())
        let current = today.addingTimeInterval(10 * 3_600)
        let clock = TestClock(calendar.date(byAdding: .day, value: -20, to: current) ?? base)
        let directory = scratchDirectory()
        let archive = SessionArchive(directory: directory, now: { clock.value })
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        clock.value = current

        for offset in 1...3 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return problems + ["could not make historical pace day \(offset)"]
            }
            let start = day.addingTimeInterval(9 * 3_600)
            let end = day.addingTimeInterval(10 * 3_600 + 10 * 60)
            archive.append(SessionRecord(name: "Pace", workType: .deepWork,
                                         start: start, end: end,
                                         workSeconds: end.timeIntervalSince(start)))
            usage.record(AppUsageSession(bundleID: "com.apple.dt.Xcode", appName: "Xcode",
                                         start: start, end: end))
        }

        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let persistence = PersistenceStore(defaults: defaults)
        persistence.removeAll()
        let engine = SessionEngine(store: persistence, archive: archive,
                                   ownBundleID: "com.example.self", schedulesDwell: false,
                                   now: { clock.value })
        let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                      isEnabled: false, idle: .disabled,
                                      now: { clock.value })
        let store = SessionStore(engine: engine, now: { clock.value })
        store.attach(tracker: tracker, usage: usage)
        expectClose(store.goal.typicalByNow ?? -1, 60 * 60,
                    "the initial 10:00 pace median", &problems)

        clock.advance(60)
        store.updateTimeDrivenFigures()
        expectClose(store.goal.typicalByNow ?? -1, 61 * 60,
                    "the existing ticker path refreshes pace at 10:01", &problems)
        clock.advance(30)
        store.updateTimeDrivenFigures()
        expectClose(store.goal.typicalByNow ?? -1, 61 * 60,
                    "the expensive median remains cached inside the same minute", &problems)
        return problems
    }

    /// Shared by tests 54 and 55: a score with only the fields the
    /// detector reads, so a test never depends on the scorer's arithmetic.
    static func makeFocusScore(_ value: Double,
                                        purpose: AppPurpose = .coding,
                                        explanation: String = "test") -> FocusScore {
        let signals = FocusSignals(focusedShare: value, mediaShare: 0, activity: .active,
                                   switchesPerMinute: 0, attended: 60,
                                   dominantPurpose: purpose, dominantApp: "com.test.app",
                                   dominantAppName: "Test")
        return FocusScore(value: value, signals: signals, explanation: explanation)
    }
}
