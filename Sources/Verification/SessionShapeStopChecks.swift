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
    private static func away(_ segments: [TimelineSegment], _ events: [MachineEvent],
                             loggedSince: Date? = nil) -> String? {
        SessionShape.sentences(.init(segments: segments, workType: .deepWork, stretches: 1,
                                     worked: 7_200, machineEvents: events, eventLogStart: loggedSince))
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
        // System Settings quitting Daybook for a permission, then a restart
        // called off after Daybook quit: both dated at the stop.
        let others = away([use(0, 20, .systemLock), use(30, 40, .systemLock)],
                          [MachineEvent(kind: .quitByApp, at: at(20), detail: "System Settings"),
                           event(.restartCancelled, 40)])
        expect(others == "Along the way Daybook was quit by another app once and quit for a cancelled restart once.",
               "another app's quit and a cancelled restart read as such, got \(others ?? "nil")", &problems)
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
        var problems: [String] = []
        let text = cardText(logging: [event(.systemSleep, 20 + 0.5 / 60), event(.wake, 25)])
        expect(text.contains("Along the way the Mac slept once."),
               "the session card names the sleep in the day's log, got \(text)", &problems)
        return problems
    }

    /// The prose of a session card on `SelfTest.base`'s day, with `events` in
    /// the store's log: Xcode until a `.systemLock` stop (minute 20 unless
    /// given), then Safari 10 to 20 minutes after it.
    private static func cardText(logging events: [MachineEvent], from: Date? = nil,
                                 stop: Date? = nil) -> String {
        let start = from ?? at(0), stop = stop ?? at(20)
        let end = stop.addingTimeInterval(1_200)
        return MainActor.assumeIsolated {
            let clock = TestClock(stop.addingTimeInterval(6_000))
            let folder = SelfTest.scratchDirectory()
            let log = MachineEventLog(directory: folder)
            log.append(events)
            let usage = AppUsageArchive(directory: folder, now: { clock.value })
            _ = usage.record(AppUsageSession(bundleID: "com.apple.dt.Xcode", appName: "Xcode",
                                             start: start, end: stop, endReason: .systemLock))
            _ = usage.record(AppUsageSession(bundleID: "com.apple.Safari", appName: "Safari",
                                             start: stop.addingTimeInterval(600), end: end,
                                             endReason: .appSwitch))
            let store = SessionStore(engine: SelfTest.makeEngine(clock), now: { clock.value })
            store.attach(tracker: AppUsageTracker(archive: usage, ownBundleID: "fc.stop.test",
                                                  idle: .disabled, now: { clock.value }),
                         usage: usage)
            store.machineEventLog = log
            let session = DaySession(id: UUID(), threadID: UUID(), name: "Parser", workType: .deepWork,
                                     start: start, end: end, worked: end.timeIntervalSince(start), stretches: 1,
                                     spans: [DateInterval(start: start, end: end)], isRunning: false)
            return store.storySessionDetail(session, on: SelfTest.base).text ?? ""
        }
    }
}

/// Since the machine event log began, a lock leaves its own event. A stop
/// with none — Spotlight, Control Centre or the Dock coming forward,
/// recording turned off, Step away — is left out rather than called a lock.
enum SessionShapeUnexplainedStopChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A stop the event log has no event for is not called a lock",
         SessionShapeStopChecks.unexplainedStopsLeftOut),
        ("A session card knows when its machine event log began",
         SessionShapeStopChecks.cardReadsTheLogStart),
        ("A lock reported after the stop, before recording resumed, names it",
         SessionShapeStopChecks.lateLockNamed),
        ("A stop after a restart was announced belongs to it, counted once",
         SessionShapeStopChecks.runEndingNamed),
        ("A stop just before midnight is named by an event just after it",
         SessionShapeStopChecks.midnightEventReached),
    ]
}

extension SessionShapeStopChecks {
    fileprivate static func unexplainedStopsLeftOut() -> [String] {
        var problems: [String] = []
        let started = event(.daybookStarted, -60)
        let mixed = away([use(0, 20, .systemLock), use(30, 40, .systemLock), use(50, 60, .idle)],
                         [started, event(.systemSleep, 20)], loggedSince: started.at)
        expect(mixed == "Along the way input stopped once and the Mac slept once.",
               "a stop with no event since the log began is left out, got \(mixed ?? "nil")", &problems)
        let alone = away([use(0, 20, .systemLock)], [started], loggedSince: started.at)
        expect(alone == nil, "unexplained stops alone say nothing, got \(alone ?? "nil")", &problems)
        // The day the log began: a stop before its first event is still a lock.
        let firstDay = away([use(0, 20, .systemLock), use(30, 40, .systemLock)],
                            [event(.daybookStarted, 25)], loggedSince: at(25))
        expect(firstDay == "Along the way the Mac locked once.",
               "a stop from before the log is still a lock, got \(firstDay ?? "nil")", &problems)
        return problems
    }

    fileprivate static func cardReadsTheLogStart() -> [String] {
        var problems: [String] = []
        let text = cardText(logging: [event(.daybookStarted, -60)])
        expect(!text.contains("Along the way"),
               "the card leaves out a stop the log has no event for, got \(text)", &problems)
        return problems
    }

    fileprivate static func lateLockNamed() -> [String] {
        var problems: [String] = []
        let started = event(.daybookStarted, -60)
        // A screen saver with a 5 s password delay.
        let delayed = away([use(0, 20, .systemLock), use(30, 40, .appSwitch)],
                           [started, event(.lock, 20 + 5 / 60.0)], loggedSince: started.at)
        expect(delayed == "Along the way the Mac locked once.",
               "a lock 5 s after the stop names it, got \(delayed ?? "nil")", &problems)
        // The session's last stretch looks as far as its span's end.
        let last = away([use(0, 20, .systemLock)], [started, event(.lock, 21)], loggedSince: started.at)
        expect(last == "Along the way the Mac locked once.",
               "a lock after the last stop names it, got \(last ?? "nil")", &problems)
        // Once recording has begun again, a lock is not this stop's.
        let resumed = away([use(0, 20, .systemLock), use(30, 40, .appSwitch)],
                           [started, event(.lock, 35)], loggedSince: started.at)
        expect(resumed == nil, "a lock after recording resumed names nothing, got \(resumed ?? "nil")", &problems)
        return problems
    }

    fileprivate static func runEndingNamed() -> [String] {
        var problems: [String] = []
        let started = event(.daybookStarted, -60)
        // Announced at minute 20; Daybook recorded on until it quit 30 s later.
        let late = away([use(0, 20.5, .systemLock)], [started, event(.restart, 20)], loggedSince: started.at)
        expect(late == "Along the way the Mac restarted once.",
               "a stop after the announcement is the restart's, got \(late ?? "nil")", &problems)
        let both = away([use(0, 20, .systemLock), use(20.2, 20.5, .systemLock)],
                        [started, event(.restart, 20)], loggedSince: started.at)
        expect(both == "Along the way the Mac restarted once.",
               "one restart behind two stops counts once, got \(both ?? "nil")", &problems)
        // Once Daybook has started again, an earlier ending explains nothing.
        let relaunched = away([use(30, 40, .systemLock)],
                              [started, event(.quit, 10), event(.daybookStarted, 11)], loggedSince: started.at)
        expect(relaunched == nil, "an ending before a relaunch names nothing, got \(relaunched ?? "nil")", &problems)
        return problems
    }

    fileprivate static func midnightEventReached() -> [String] {
        var problems: [String] = []
        let midnight = Calendar.current.dateInterval(of: .day, for: SelfTest.base)?.end ?? at(900)
        let stop = midnight.addingTimeInterval(-0.5)
        let text = cardText(logging: [event(.daybookStarted, -60),
                                      MachineEvent(kind: .systemSleep, at: midnight.addingTimeInterval(0.3))],
                            from: stop.addingTimeInterval(-1_200), stop: stop)
        expect(text.contains("Along the way the Mac slept once."),
               "a sleep 0.3 s after midnight names the stop before it, got \(text)", &problems)
        return problems
    }
}
