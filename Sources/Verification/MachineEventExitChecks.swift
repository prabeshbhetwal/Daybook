import AppKit

/// An exit is named from evidence, never from macOS's power-off notice alone:
/// who sent the quit, the reason macOS gave, whether the Mac booted again, when
/// the login session began and which macOS it came back on. On 10 October
/// System Settings quit Daybook to apply Input Monitoring and the day read
/// "Shut down, restarted or logged out".
enum MachineEventExitChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A quit another app sends is named for it, even with a power-off announced",
         quitByAnotherApp),
        ("A log out, restart or shut down that never happened reads as cancelled",
         cancelledExits),
        ("A power-off nobody named is settled by the boot and the login session",
         unnamedPowerOffSettled),
        ("A Mac back on another macOS records the update",
         macOSUpdateRecorded),
        ("Old entries for an unnamed power-off read by what followed them",
         oldEntriesSettled),
        ("The login records and the macOS version are read from this Mac",
         systemFactsRead),
    ]

    private static let launched = SelfTest.base
    private static let lastSeen = SelfTest.base.addingTimeInterval(3_600)
    private static let booted = SelfTest.base.addingTimeInterval(5_400)
    private static let now = SelfTest.base.addingTimeInterval(7_200)
    private static let settings = MachineEventRecorder.QuitRequest(
        reason: nil, sender: "com.apple.systempreferences", senderName: "System Settings")

    private static func marker(_ exit: MachineEvent.Kind?, os: String? = nil) -> RunMarker {
        RunMarker(bootSessionID: "boot-1", launchedAt: launched, heartbeat: lastSeen, exit: exit,
                  pid: 100, osVersion: os)
    }

    private static func launch(rebooted: Bool, login: Date? = nil, os: String = "") -> LaunchEvidence {
        LaunchEvidence(bootSessionID: rebooted ? "boot-2" : "boot-1", bootTime: rebooted ? booted : launched,
                       crashReports: [], panicReports: [], now: now, osVersion: os, consoleLogin: login)
    }

    private static func kinds(_ events: [MachineEvent]) -> [MachineEvent.Kind] { events.map(\.kind) }

    private static func quitByAnotherApp() -> [String] {
        var problems: [String] = []
        typealias Quit = MachineEventRecorder.QuitRequest
        let cases: [(Quit, Bool, MachineEvent.Kind, String?)] = [
            (settings, true, .quitByApp, "System Settings"),
            (Quit(sender: "com.apple.settings.PrivacySecurity.extension"), true, .quitByApp, "System Settings"),
            (Quit(sender: "/usr/bin/osascript"), false, .quitByApp, "osascript"),
            (Quit(sender: "com.apple.dock", senderName: "Dock"), false, .quit, nil),
            (Quit(sender: "com.apple.loginwindow"), true, .powerOffUnknown, nil),
            // A restart held up past the grace: loginwindow's quit still waits.
            (Quit(sender: "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow"),
             false, .powerOffUnknown, nil),
            (Quit(reason: OSType(kAERestart), sender: "com.apple.systempreferences"), false, .restart, nil),
        ]
        for (quit, announced, kind, detail) in cases {
            let exit = MachineEventRecorder.exit(for: quit, powerOffAnnounced: announced)
            expect(exit.kind == kind && exit.detail == detail,
                   "\(quit.sender ?? "-") names \(kind) \(detail ?? ""), got \(exit.kind) \(exit.detail ?? "")",
                   &problems)
        }
        // The 10 October quit, end to end: AppKit announces a power-off, then
        // System Settings' quit arrives with no reason.
        let folder = SelfTest.scratchDirectory()
        let clock = TestClock(launched)
        let recorder = MachineEventRecorder(directory: folder, now: { clock.value })
        recorder.start(evidence: LaunchEvidence(bootSessionID: "boot-1", bootTime: launched, crashReports: [],
                                                panicReports: [], now: launched))
        clock.advance(60)
        recorder.record(.powerOffUnknown)
        recorder.recordExit(settings)
        let last = MachineEventLog(directory: folder).events.last
        expect(last?.title == "Daybook quit by System Settings",
               "the quit is named for System Settings as it happens, got \(last?.title ?? "nothing")", &problems)
        let saved = RunMarker.load(from: folder)
        expect(saved?.exit == .quitByApp && saved?.quitSender == "com.apple.systempreferences",
               "the marker keeps what the quit said, got \(String(describing: saved))", &problems)
        let next = MachineEventRecorder(directory: folder, now: { clock.value })
        clock.advance(40)
        next.start(evidence: LaunchEvidence(bootSessionID: "boot-1", bootTime: launched, crashReports: [],
                                            panicReports: [], now: clock.value))
        let reopened = kinds(MachineEventLog(directory: folder).events)
        expect(reopened == [.daybookStarted, .quitByApp, .daybookStarted],
               "reopening adds no power-off, got \(reopened)", &problems)
        withExtendedLifetime(next) {}

        // loginwindow quits with a reason no rule names; terminating then
        // calls again with no event. What the quit said must survive both.
        let traced = SelfTest.scratchDirectory()
        let tracing = MachineEventRecorder(directory: traced, now: { clock.value })
        tracing.start(evidence: LaunchEvidence(bootSessionID: "boot-1", bootTime: launched, crashReports: [],
                                             panicReports: [], now: clock.value))
        tracing.record(.powerOffUnknown)
        tracing.recordExit(Quit(reason: 0x7175_6961, sender: "com.apple.loginwindow")) // "quia"
        tracing.recordExit(nil)
        let trace = RunMarker.load(from: traced)
        expect(trace?.exit == .powerOffUnknown && trace?.quitReason == "quia"
               && trace?.quitSender == "com.apple.loginwindow",
               "the marker keeps the first quit's reason and sender, got \(String(describing: trace))", &problems)
        return problems
    }

    private static func cancelledExits() -> [String] {
        var problems: [String] = []
        let before = launched.addingTimeInterval(-60)
        let after = lastSeen.addingTimeInterval(30)
        let cases: [(MachineEvent.Kind, Date?, MachineEvent.Kind)] = [
            (.restart, nil, .restartCancelled), (.shutDown, nil, .shutDownCancelled),
            (.logOut, before, .logOutCancelled), (.logOut, after, .logOut),
            // No login records: nothing says the log out was cancelled.
            (.logOut, nil, .quit),
        ]
        for (exit, login, expected) in cases {
            let events = RunMarker.previousRun(marker(exit), launch(rebooted: false, login: login))
            expect(kinds(events) == [expected, .daybookStarted],
                   "\(exit) on the same boot, login \(String(describing: login)), reads \(expected), got \(kinds(events))",
                   &problems)
        }
        // A run that never learned its boot cannot say a restart was cancelled.
        let unknownBoot = RunMarker(bootSessionID: "", launchedAt: launched, heartbeat: lastSeen, exit: .restart)
        let unknown = RunMarker.previousRun(unknownBoot, launch(rebooted: false))
        expect(kinds(unknown) == [.quit, .daybookStarted],
               "an unknown boot claims no cancelled restart, got \(kinds(unknown))", &problems)
        return problems
    }

    private static func unnamedPowerOffSettled() -> [String] {
        var problems: [String] = []
        let loggedBackIn = RunMarker.previousRun(marker(.powerOffUnknown),
                                                 launch(rebooted: false, login: lastSeen.addingTimeInterval(30)))
        expect(kinds(loggedBackIn) == [.logOut, .daybookStarted],
               "a new login session after it means a log out, got \(kinds(loggedBackIn))", &problems)
        let nothing = RunMarker.previousRun(marker(.powerOffUnknown),
                                            launch(rebooted: false, login: launched.addingTimeInterval(-60)))
        expect(kinds(nothing) == [.quit, .daybookStarted],
               "the same boot and session means only Daybook quit, got \(kinds(nothing))", &problems)
        return problems
    }

    private static func macOSUpdateRecorded() -> [String] {
        var problems: [String] = []
        let updated = RunMarker.previousRun(marker(.restart, os: "27.2 (26B5091g)"),
                                            launch(rebooted: true, os: "27.2 (26B5101f)"))
        expect(kinds(updated) == [.restart, .macOSUpdated, .macStarted, .daybookStarted]
               && updated[1].title == "macOS updated to 27.2 (26B5101f)" && updated[1].at == booted,
               "a boot on a new build records the update at boot, got \(updated.map(\.title))", &problems)
        let same = RunMarker.previousRun(marker(.restart, os: "27.2 (26B5101f)"),
                                         launch(rebooted: true, os: "27.2 (26B5101f)"))
        expect(!kinds(same).contains(.macOSUpdated), "the same build records no update, got \(kinds(same))", &problems)
        let unknown = RunMarker.previousRun(marker(.restart), launch(rebooted: true, os: "27.2 (26B5101f)"))
        expect(!kinds(unknown).contains(.macOSUpdated),
               "a marker without a version claims no update, got \(kinds(unknown))", &problems)
        let gap = DateInterval(start: lastSeen, end: now)
        let reason = StoryChronology.gapReason(for: gap, usage: [], events: updated)
        expect(reason.title == "Mac updating macOS", "the hole reads as the update, got \(reason.title)", &problems)
        return problems
    }

    private static func oldEntriesSettled() -> [String] {
        var problems: [String] = []
        // The 10 October entries as the first build wrote them.
        let folder = SelfTest.scratchDirectory()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let reference = launched.timeIntervalSinceReferenceDate
        let lines = [("daybookStarted", 0), ("powerOffUnknown", 60), ("daybookStarted", 100),
                     ("powerOffUnknown", 200), ("macStarted", 300), ("daybookStarted", 320)]
            .map { "{\"kind\":\"\($0.0)\",\"at\":\(reference + Double($0.1))}\n" }.joined()
        try? Data(lines.utf8).write(to: folder.appendingPathComponent(MachineEventLog.fileName))
        let read = MachineEventLog(directory: folder).events.map(\.title)
        expect(read == ["Daybook opened", "Daybook quit", "Daybook opened",
                        "Mac restarted or shut down", "Mac started up", "Daybook opened"],
               "old entries read by what followed them, got \(read)", &problems)
        let raw = (try? String(contentsOf: folder.appendingPathComponent(MachineEventLog.fileName),
                               encoding: .utf8)) ?? ""
        expect(raw == lines, "the file keeps what was written", &problems)
        return problems
    }

    private static func systemFactsRead() -> [String] {
        var problems: [String] = []
        expect(SystemFacts.consoleLogin(of: "fc-selftest-nobody") == nil,
               "a user with no session has no login time", &problems)
        if let login = SystemFacts.consoleLogin() {
            expect(login < Date(), "this session began in the past, got \(login)", &problems)
        }
        let version = SystemFacts.osVersion
        expect(version.contains("(") && version.first?.isNumber == true,
               "the macOS version names its build, got \(version)", &problems)
        return problems
    }
}
