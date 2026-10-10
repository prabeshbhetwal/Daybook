import Foundation

/// The tracker ends a stretch `.systemLock` on a lock, a sleep, a dark
/// display and a quit alike. A session's "Along the way" sentence names each
/// by the machine event logged at that moment, and a day from before the log
/// existed reads exactly as it did.
enum SessionShapeStopChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A session's sleeps read as sleeps, not as the Mac locking", sleepsNamed),
        ("A session with no machine events keeps the sentence it always had", noEventsUnchanged),
        ("Only an event seen live within 2 s names a stop", onlyLiveNearbyEvents),
        ("A session card names its stops from the day's machine event log", sessionCardReadsTheLog),
    ]

    private static func at(_ minutes: Double) -> Date { SelfTest.base.addingTimeInterval(minutes * 60) }

    private static func use(_ from: Double, _ to: Double, _ end: UsageEndReason) -> TimelineSegment {
        TimelineSegment(id: UUID(), bundleID: "com.apple.dt.Xcode", appName: "Xcode",
                        start: at(from), end: at(to), colorIndex: 0, endReason: end)
    }

    private static func event(_ kind: MachineEvent.Kind, _ minutes: Double,
                              until: Double? = nil) -> MachineEvent {
        MachineEvent(kind: kind, at: at(minutes), latest: until.map { at($0) })
    }

    /// The session's "Along the way" sentence, or nil when it has none.
    private static func away(_ segments: [TimelineSegment], _ events: [MachineEvent]) -> String? {
        SessionShape.sentences(.init(segments: segments, workType: .deepWork, stretches: 1,
                                     worked: 7_200, machineEvents: events))
            .first { $0.hasPrefix("Along the way") }
    }

    private static func sleepsNamed() -> [String] {
        var problems: [String] = []
        let segments = [use(0, 20, .systemLock), use(30, 50, .systemLock),
                        use(60, 80, .systemLock), use(90, 100, .idle)]
        let events = [
            // The monitor logs an event just after the tracker stops.
            event(.systemSleep, 20 + 0.5 / 60), event(.wake, 25),
            event(.lock, 50 - 1 / 60.0), event(.unlock, 55),
            // Closing the lid: sleep, dark display and lock at once is a sleep.
            event(.displaySleep, 80), event(.lock, 80 + 1 / 60.0), event(.systemSleep, 80 + 1 / 60.0),
        ]
        let text = away(segments, events)
        expect(text == "Along the way input stopped once and the Mac slept 2 times and locked once.",
               "two sleeps and a lock read as such, got \(text ?? "nil")", &problems)

        let quit = away([use(0, 20, .systemLock)], [event(.quit, 20 - 0.5 / 60)])
        expect(quit == "Along the way Daybook quit once.",
               "a quit reads as a quit, got \(quit ?? "nil")", &problems)
        let dark = away([use(0, 20, .systemLock), use(30, 40, .systemLock)],
                        [event(.displaySleep, 20), event(.restart, 40)])
        // Most telling first.
        expect(dark == "Along the way the Mac restarted once and the display turned off once.",
               "a dark display and a restart read as such, got \(dark ?? "nil")", &problems)
        return problems
    }

    private static func noEventsUnchanged() -> [String] {
        var problems: [String] = []
        let both = away([use(0, 20, .systemLock), use(30, 50, .idle), use(60, 80, .systemLock)], [])
        expect(both == "Along the way input stopped once and the Mac locked 2 times.",
               "a day before the log reads as it always did, got \(both ?? "nil")", &problems)
        let one = away([use(0, 20, .systemLock), use(30, 50, .appSwitch)], [])
        expect(one == "Along the way the Mac locked once.",
               "one stop with no events is still a lock, got \(one ?? "nil")", &problems)
        let none = away([use(0, 20, .appSwitch), use(30, 50, .stillOpen)], [])
        expect(none == nil, "no stops say nothing, got \(none ?? "nil")", &problems)
        return problems
    }

    private static func onlyLiveNearbyEvents() -> [String] {
        var problems: [String] = []
        // A sleep 5 s after the stop did not cause it.
        let late = away([use(0, 20, .systemLock)], [event(.systemSleep, 20 + 5 / 60.0)])
        expect(late == "Along the way the Mac locked once.",
               "an event 5 s away names nothing, got \(late ?? "nil")", &problems)
        // Every live event sets the heartbeat, so a power cut found at the
        // next launch is dated from the sleep. It happened later, asleep.
        let cut = away([use(0, 20, .systemLock)], [event(.systemSleep, 20), event(.powerLost, 20, until: 300)])
        expect(cut == "Along the way the Mac slept once.",
               "an event found afterwards names nothing, got \(cut ?? "nil")", &problems)
        return problems
    }

    /// The card's prose is built in the App layer, which must hand the day's
    /// log to `SessionShape`.
    private static func sessionCardReadsTheLog() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let clock = TestClock(at(120))
            let folder = SelfTest.scratchDirectory()
            let log = MachineEventLog(directory: folder)
            log.append([event(.systemSleep, 20 + 0.5 / 60), event(.wake, 25)])
            let usage = AppUsageArchive(directory: folder, now: { clock.value })
            _ = usage.record(AppUsageSession(bundleID: "com.apple.dt.Xcode", appName: "Xcode",
                                             start: at(0), end: at(20), endReason: .systemLock))
            _ = usage.record(AppUsageSession(bundleID: "com.apple.Safari", appName: "Safari",
                                             start: at(30), end: at(40), endReason: .appSwitch))
            let store = SessionStore(engine: SelfTest.makeEngine(clock), now: { clock.value })
            store.attach(tracker: AppUsageTracker(archive: usage, ownBundleID: "fc.stop.test",
                                                  idle: .disabled, now: { clock.value }),
                         usage: usage)
            store.machineEventLog = log
            let session = DaySession(id: UUID(), threadID: UUID(), name: "Parser", workType: .deepWork,
                                     start: at(0), end: at(40), worked: 2_400, stretches: 1,
                                     spans: [DateInterval(start: at(0), end: at(40))], isRunning: false)
            let text = store.storySessionDetail(session, on: SelfTest.base).text ?? ""
            expect(text.contains("Along the way the Mac slept once."),
                   "the session card names the sleep in the day's log, got \(text)", &problems)
            return problems
        }
    }
}
