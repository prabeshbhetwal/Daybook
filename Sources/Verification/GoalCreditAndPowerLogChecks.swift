import Foundation

/// A session still running past midnight fills the goal of the day it began,
/// as its logged work already does; and the power log never writes over a
/// file it could not read.
enum GoalCreditAndPowerLogChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A session still running past midnight fills the goal of the day it began",
         runningSessionCreditsTheDayItBegan),
        ("The power log never writes over a file it could not read", powerLogKeepsUnreadableFile),
    ]

    private static func runningSessionCreditsTheDayItBegan() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let calendar = Calendar.current
            let midnight = calendar.startOfDay(for: SelfTest.anchoredNow())
            let start = midnight.addingTimeInterval(-3_600)
            let clock = TestClock(start)
            let suite = "fc-selftest-goal-credit-\(UUID().uuidString)"
            guard let defaults = MemoryDefaults.suite(named: suite) else {
                return ["could not create isolated preferences suite"]
            }
            defer { MemoryDefaults.remove(named: suite) }
            let persistence = PersistenceStore(defaults: defaults)
            persistence.removeAll()
            let directory = SelfTest.scratchDirectory()
            let engine = SessionEngine(store: persistence,
                                       archive: SessionArchive(directory: directory, now: { clock.value }),
                                       ownBundleID: "com.example.self", schedulesDwell: false,
                                       now: { clock.value })
            let usage = AppUsageArchive(directory: directory, now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            let store = SessionStore(engine: engine, schedulesTicker: false, now: { clock.value })
            store.attach(tracker: tracker, usage: usage)

            // 23:00 start, a ten-minute pause at 23:20, still running at 00:30.
            engine.start(workType: .deepWork, intent: "Late night")
            clock.advance(20 * 60)
            engine.transition(on: .manualPause)
            clock.advance(10 * 60)
            engine.transition(on: .manualResume)
            clock.advance(60 * 60)
            // Hands on from 23:00 to 00:10, across midnight.
            usage.record(AppUsageSession(bundleID: "com.apple.dt.Xcode", appName: "Xcode",
                                         start: start, end: midnight.addingTimeInterval(10 * 60),
                                         endReason: .appSwitch))
            let yesterday = calendar.startOfDay(for: start)
            guard !calendar.isDate(yesterday, inSameDayAs: clock.value), engine.state != .idle else {
                return ["the fixture did not leave a session running into the next day"]
            }

            SelfTest.expectClose(store.focusedActiveSeconds(on: yesterday), 50 * 60,
                                 "the day it began credits its worked minutes before midnight", &problems)
            SelfTest.expectClose(store.focusedActiveSeconds(on: clock.value), 10 * 60,
                                 "today credits only its hands-on minutes after midnight", &problems)
            // The rail caches a past day; one the running session reaches into
            // must not keep that session's credit once it is gone.
            SelfTest.expectClose(store.storyRailDay(on: yesterday).goal.achieved, 50 * 60,
                                 "yesterday's rail goal while the session runs", &problems)
            engine.discard()
            SelfTest.expectClose(store.storyRailDay(on: yesterday).goal.achieved, 0,
                                 "yesterday's rail goal once the running session is discarded", &problems)
            return problems
        }
    }

    private static func powerLogKeepsUnreadableFile() -> [String] {
        var problems: [String] = []
        let payloads: [(String, Data)] = [
            ("an unreadable file", Data("not ambient power".utf8)),
            ("a newer version's file", Data(#"{"version":2,"observations":[]}"#.utf8)),
        ]
        let moment = SelfTest.anchoredNow()
        for (label, payload) in payloads {
            let directory = SelfTest.scratchDirectory()
            let file = directory.appendingPathComponent("ambient-power.json")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard (try? payload.write(to: file, options: .atomic)) != nil else {
                problems.append("could not write \(label)")
                continue
            }
            let log = AmbientPowerLog(directory: directory)
            let result = log.append(PowerObservation(timestamp: moment, source: .battery,
                                                     percentage: 60, charging: .notCharging),
                                    now: moment)
            expect(result != .saved, "appending over \(label) reported \(result)", &problems)
            expect(log.lastError != nil, "appending over \(label) cleared its error", &problems)
            let bytes = try? Data(contentsOf: file)
            expect(bytes == payload,
                   "appending over \(label) changed it to \(bytes.map { String(decoding: $0, as: UTF8.self) } ?? "nothing")",
                   &problems)
        }
        return problems
    }
}
