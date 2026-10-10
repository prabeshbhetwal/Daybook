import Foundation

/// A quit's sender decides before its reason. System Settings' Quit & Reopen
/// arrives from its privacy extension with macOS's own log-out reason ('rlgo'),
/// and the build before this rule kept it as a log out; a marker it left is
/// read at the next launch as System Settings' quit. (The live sender cases
/// are in `MachineEventExitChecks`.)
enum MachineEventSenderChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A marker that kept another app's quit as a log out reads as that app's quit",
         otherAppMarkerSettled),
    ]

    private static let launched = SelfTest.base
    private static let lastSeen = SelfTest.base.addingTimeInterval(3_600)
    private static let now = SelfTest.base.addingTimeInterval(7_200)

    /// The marker the 10 October evening build left when System Settings quit
    /// it: exit "logOut", reason "rlgo", sent by its privacy extension.
    private static func otherAppMarkerSettled() -> [String] {
        var problems: [String] = []
        func previous(_ exit: MachineEvent.Kind, from sender: String) -> [MachineEvent] {
            let saved = RunMarker(bootSessionID: "boot-1", launchedAt: launched, heartbeat: lastSeen, exit: exit,
                                  pid: 100, quitReason: "rlgo", quitSender: sender)
            let launch = LaunchEvidence(bootSessionID: "boot-1", bootTime: launched, crashReports: [],
                                        panicReports: [], now: now, consoleLogin: launched.addingTimeInterval(-60))
            return RunMarker.previousRun(saved, launch)
        }
        let settings = previous(.logOut, from: "com.apple.settings.PrivacySecurity.extension")
        expect(settings.map(\.title) == ["Daybook quit by System Settings", "Daybook opened"]
               && settings.first?.at == lastSeen,
               "System Settings' quit kept as a log out reads as its own, got \(settings.map(\.title))", &problems)
        let script = previous(.powerOffUnknown, from: "/usr/bin/osascript")
        expect(script.first?.title == "Daybook quit by osascript",
               "a script's quit reads as the script's, got \(script.map(\.title))", &problems)
        let macOS = previous(.logOut, from: "com.apple.loginwindow")
        expect(macOS.map(\.kind) == [.logOutCancelled, .daybookStarted],
               "loginwindow's log out is still confirmed by the session, got \(macOS.map(\.kind))", &problems)
        return problems
    }
}
