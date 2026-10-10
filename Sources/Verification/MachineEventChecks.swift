import AppKit

/// How a run of Daybook ended is worked out at the next launch, and every
/// machine event survives in its log: a clean exit adds only the starts, an
/// unclean one is named from the reports and the boot it left behind.
enum MachineEventChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("After a clean exit a launch records only its start, and the Mac's start after a reboot",
         cleanExits),
        ("A run that ended without a word is named: crash, force quit, power loss or panic",
         uncleanExits),
        ("A power-off that never reached the quit handler is still recorded",
         unfinishedPowerOff),
        ("The machine event log keeps every event across a relaunch and skips lines it cannot read",
         logSurvivesRelaunch),
        ("Crash and panic reports are found by name and dated by their files",
         reportsFound),
        ("The kernel names this boot and when it began",
         bootSessionRead),
        ("Each reason macOS gives for a quit names the exit; a plain quit names a quit",
         quitReasonsNamed),
        ("Each run tells the next launch how it ended, and an exit is recorded once",
         recorderRoundTrip),
    ]

    private static let launched = SelfTest.base
    private static let lastSeen = SelfTest.base.addingTimeInterval(3_600)
    private static let booted = SelfTest.base.addingTimeInterval(5_400)
    private static let now = SelfTest.base.addingTimeInterval(7_200)

    private static func marker(exit: MachineEvent.Kind?) -> RunMarker {
        RunMarker(bootSessionID: "boot-1", launchedAt: launched, heartbeat: lastSeen, exit: exit, pid: 100)
    }

    private static func launch(rebooted: Bool, crashes: [Date] = [], crashPID: Int32? = nil,
                               panics: [Date] = []) -> LaunchEvidence {
        LaunchEvidence(bootSessionID: rebooted ? "boot-2" : "boot-1",
                       bootTime: rebooted ? booted : launched.addingTimeInterval(-86_400),
                       crashReports: crashes.map { LaunchEvidence.CrashReport(date: $0, pid: crashPID) },
                       panicReports: panics, now: now)
    }

    private static func describe(_ events: [MachineEvent]) -> String {
        events.map { "\($0.kind.rawValue)@\(Int($0.at.timeIntervalSince(launched)))" }.joined(separator: ", ")
    }

    private static func cleanExits() -> [String] {
        var problems: [String] = []
        let started = MachineEvent(kind: .daybookStarted, at: now)
        let first = RunMarker.previousRun(nil, launch(rebooted: false))
        expect(first == [started], "a first run records only its start, got \(describe(first))", &problems)
        let quit = RunMarker.previousRun(marker(exit: .quit), launch(rebooted: false))
        expect(quit == [started], "a quit and relaunch adds only the start, got \(describe(quit))", &problems)
        // An old crash report from an earlier run is not this run's ending.
        let restart = RunMarker.previousRun(marker(exit: .restart),
                                            launch(rebooted: true, crashes: [launched.addingTimeInterval(60)]))
        expect(restart == [MachineEvent(kind: .restart, at: lastSeen), MachineEvent(kind: .macStarted, at: booted),
                           started],
               "a restart the boot confirms is recorded with the Mac's start, got \(describe(restart))", &problems)
        // Another app called the shut down off after Daybook had quit for it.
        let calledOff = RunMarker.previousRun(marker(exit: .shutDown), launch(rebooted: false))
        expect(calledOff == [MachineEvent(kind: .quit, at: lastSeen), started],
               "a shut down on the same boot was called off: Daybook quit, got \(describe(calledOff))", &problems)
        return problems
    }

    private static func uncleanExits() -> [String] {
        var problems: [String] = []
        let started = MachineEvent(kind: .daybookStarted, at: now)
        let report = lastSeen.addingTimeInterval(20)
        let crash = RunMarker.previousRun(marker(exit: nil), launch(rebooted: false, crashes: [report], crashPID: 100))
        expect(crash == [MachineEvent(kind: .crashed, at: lastSeen, latest: report), started],
               "a crash report about this run names a crash, got \(describe(crash))", &problems)
        let other = RunMarker.previousRun(marker(exit: nil), launch(rebooted: false, crashes: [report], crashPID: 200))
        expect(other.map(\.kind) == [.forceQuit, .daybookStarted],
               "another Daybook's crash is not this run's, got \(describe(other))", &problems)
        let earlier = launched.addingTimeInterval(-600)
        let killed = RunMarker.previousRun(marker(exit: nil), launch(rebooted: false, crashes: [earlier]))
        expect(killed == [MachineEvent(kind: .forceQuit, at: lastSeen, latest: now), started],
               "no report on the same boot names a force quit, got \(describe(killed))", &problems)
        let cut = RunMarker.previousRun(marker(exit: nil), launch(rebooted: true))
        expect(cut == [MachineEvent(kind: .powerLost, at: lastSeen, latest: booted),
                       MachineEvent(kind: .macStarted, at: booted), started],
               "a new boot with no report names lost power, got \(describe(cut))", &problems)
        let panic = RunMarker.previousRun(marker(exit: nil),
                                          launch(rebooted: true, panics: [booted.addingTimeInterval(30)]))
        expect(panic.first?.kind == .kernelPanic && panic.count == 3,
               "a panic report since the run names a panic, got \(describe(panic))", &problems)
        let crashThenOff = RunMarker.previousRun(marker(exit: nil), launch(rebooted: true, crashes: [report]))
        expect(crashThenOff.map(\.kind) == [.crashed, .macStarted, .daybookStarted],
               "a crash before a reboot stays a crash, got \(describe(crashThenOff))", &problems)
        return problems
    }

    private static func unfinishedPowerOff() -> [String] {
        var problems: [String] = []
        let events = RunMarker.previousRun(marker(exit: .powerOffUnknown), launch(rebooted: true))
        expect(events == [MachineEvent(kind: .powerOffUnknown, at: lastSeen),
                          MachineEvent(kind: .macStarted, at: booted),
                          MachineEvent(kind: .daybookStarted, at: now)],
               "a power-off with no quit after it is recorded once, got \(describe(events))", &problems)
        return problems
    }

    private static func logSurvivesRelaunch() -> [String] {
        var problems: [String] = []
        let folder = SelfTest.scratchDirectory()
        let sleep = MachineEvent(kind: .systemSleep, at: launched)
        let wake = MachineEvent(kind: .wake, at: lastSeen)
        expect(MachineEventLog(directory: folder).append([wake, sleep]), "the first events are written", &problems)
        // A newer build's kind, then a write cut short by a crash.
        let file = folder.appendingPathComponent(MachineEventLog.fileName)
        if let handle = try? FileHandle(forWritingTo: file) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data("{\"kind\":\"teleported\",\"at\":0}\n{\"kind\":\"lo".utf8))
            try? handle.close()
        }
        let reopened = MachineEventLog(directory: folder)
        expect(reopened.events == [sleep, wake],
               "the readable events come back in time order, got \(describe(reopened.events))", &problems)
        let lock = MachineEvent(kind: .lock, at: now)
        let lost = MachineEvent(kind: .powerLost, at: launched.addingTimeInterval(-60), latest: launched.addingTimeInterval(30))
        reopened.append([lock, lost])
        let third = MachineEventLog(directory: folder).events
        expect(third == [lost, sleep, wake, lock],
               "an append after a torn line is not lost with it, got \(describe(third))", &problems)
        let raw = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        expect(raw.contains("teleported"), "a line this build cannot read is left for one that can", &problems)
        let window = DateInterval(start: launched.addingTimeInterval(10), end: lastSeen)
        let overlapping = MachineEventLog(directory: folder).events(in: window)
        expect(overlapping == [lost],
               "an event found afterwards counts where its window reaches, got \(describe(overlapping))", &problems)
        return problems
    }

    private static func reportsFound() -> [String] {
        var problems: [String] = []
        let folder = SelfTest.scratchDirectory()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dates: [(String, Date)] = [
            ("Daybook-2026-10-06-095323.ips", lastSeen),
            ("Daybook_2026-10-10-004632_Mac.spin", now),
            ("Other-2026-10-06-095323.ips", now),
            ("panic-full-2026-10-07-230516.panic", booted),
        ]
        // The shape macOS writes: a one-line header, then the body with the pid.
        let body = "{\"app_name\":\"Daybook\",\"bug_type\":\"309\"}\n{\n  \"uptime\" : 35000,\n  \"pid\" : 48832,\n}"
        for (name, date) in dates {
            let url = folder.appendingPathComponent(name)
            try? Data(body.utf8).write(to: url)
            try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
        let crashes = LaunchEvidence.crashReports(in: folder)
        expect(crashes == [LaunchEvidence.CrashReport(date: lastSeen, pid: 48832)],
               "only Daybook's crash report counts, with its process, got \(crashes)", &problems)
        let panics = LaunchEvidence.reports(in: folder, prefix: "", pathExtension: "panic").map(\.date)
        expect(panics == [booted], "a panic report is found, got \(panics)", &problems)
        let missing = LaunchEvidence.reports(in: folder.appendingPathComponent("absent"),
                                             prefix: "", pathExtension: "panic")
        expect(missing.isEmpty, "a missing folder has no reports, got \(missing.count)", &problems)
        return problems
    }

    private static func quitReasonsNamed() -> [String] {
        var problems: [String] = []
        let cases: [(OSType?, Bool, MachineEvent.Kind)] = [
            (OSType(kAERestart), false, .restart), (OSType(kAEShowRestartDialog), false, .restart),
            (OSType(kAEShutDown), false, .shutDown), (OSType(kAEShowShutdownDialog), false, .shutDown),
            (OSType(kAEReallyLogOut), true, .logOut), (OSType(kAELogOut), false, .logOut),
            (nil, false, .quit), (nil, true, .powerOffUnknown),
        ]
        for (reason, announced, expected) in cases {
            let kind = MachineEventRecorder.exitKind(quitReason: reason, powerOffAnnounced: announced)
            expect(kind == expected, "reason \(String(describing: reason)) names \(expected), got \(kind)", &problems)
        }
        return problems
    }

    private static func recorderRoundTrip() -> [String] {
        var problems: [String] = []
        let folder = SelfTest.scratchDirectory()
        let clock = TestClock(launched)
        func evidence(_ boot: String) -> LaunchEvidence {
            LaunchEvidence(bootSessionID: boot, bootTime: clock.value.addingTimeInterval(-60),
                           crashReports: [], panicReports: [], now: clock.value)
        }
        func kinds() -> [MachineEvent.Kind] { MachineEventLog(directory: folder).events.map(\.kind) }
        // Runs that never quit stay alive until the check ends, as a running app would.
        var running: [MachineEventRecorder] = []
        func launch(_ boot: String) {
            let recorder = MachineEventRecorder(directory: folder, now: { clock.value })
            recorder.start(evidence: evidence(boot))
            running.append(recorder)
        }

        let first = MachineEventRecorder(directory: folder, now: { clock.value })
        first.start(evidence: evidence("boot-1"))
        clock.advance(60)
        first.record(.systemSleep)
        clock.advance(60)
        first.recordExit(quitReason: OSType(kAERestart))
        first.recordExit(quitReason: nil)
        expect(kinds() == [.daybookStarted, .systemSleep],
               "a restart waits for the next boot to confirm it, got \(kinds())", &problems)
        expect(RunMarker.load(from: folder)?.exit == .restart, "the marker says the run restarted", &problems)

        // Reopened on a new boot, which confirms the restart once; then it
        // never quits, and the next launch names that.
        clock.advance(600)
        launch("boot-2")
        expect(kinds() == [.daybookStarted, .systemSleep, .restart, .macStarted, .daybookStarted],
               "the new boot records the restart once, got \(kinds())", &problems)
        let stopped = clock.value
        clock.advance(300)
        launch("boot-2")
        let afterKill = MachineEventLog(directory: folder).events.suffix(2)
        expect(afterKill.map(\.kind) == [.forceQuit, .daybookStarted] && afterKill.first?.at == stopped,
               "a run that never quit is named from its last heartbeat, got \(kinds())", &problems)

        // A power-off another app called off: once the grace has passed, a
        // later quit is a plain quit.
        let fourth = MachineEventRecorder(directory: folder, now: { clock.value })
        fourth.start(evidence: evidence("boot-2"))
        fourth.record(.powerOffUnknown)
        clock.advance(MachineEventRecorder.powerOffGrace + 10)
        fourth.record(.lock)
        fourth.recordExit(quitReason: nil)
        expect(kinds().last == .quit && RunMarker.load(from: folder)?.exit == .quit,
               "a power-off called off ends as a quit, got \(kinds())", &problems)

        // macOS announces a power-off and Daybook ends before the quit names it.
        let fifth = MachineEventRecorder(directory: folder, now: { clock.value })
        fifth.start(evidence: evidence("boot-2"))
        let before = kinds().count
        fifth.record(.powerOffUnknown)
        fifth.recordExit(quitReason: nil)
        clock.advance(120)
        launch("boot-3")
        expect(Array(kinds().dropFirst(before)) == [.powerOffUnknown, .macStarted, .daybookStarted],
               "an unnamed power-off is recorded once, by the next launch, got \(kinds())", &problems)
        withExtendedLifetime(running) {}
        return problems
    }

    private static func bootSessionRead() -> [String] {
        guard let boot = BootSession.current() else { return ["the kernel did not name this boot"] }
        var problems: [String] = []
        expect(UUID(uuidString: boot.id) != nil, "the boot session is a UUID, got \(boot.id)", &problems)
        expect(boot.start < Date(), "the boot began in the past, got \(boot.start)", &problems)
        return problems
    }
}
