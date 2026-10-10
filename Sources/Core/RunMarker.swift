import Foundation

/// What a running Daybook keeps on disk about itself, so the next launch can
/// tell how it ended.
///
/// Written at launch, by a heartbeat while it runs, at each machine event and
/// once more as it quits. A run that quits cleanly leaves `exit` saying why. One
/// that crashed, was force quit or lost power never got the chance: `exit` is
/// still nil, and `heartbeat` is the last moment it was known to be running.
/// Nothing else marks a clean exit — the single-instance lock is released on
/// any death — so without this a crash and a quit look the same.
struct RunMarker: Codable, Equatable {
    static let fileName = "run-state.json"

    let bootSessionID: String
    let launchedAt: Date
    var heartbeat: Date
    var exit: MachineEvent.Kind?
    /// Matched against a crash report's, so a crash of some other Daybook —
    /// a test build, a second copy — is not taken for this run's.
    var pid: Int32?
    /// macOS when this run began; a boot on another one followed an update.
    var osVersion: String?
    /// What the quit said, kept as written so a surprising exit can be traced:
    /// the reason's four letters, and who sent it.
    var quitReason: String?
    var quitSender: String?

    /// Nil when there is none or it does not read — a first run, or one a
    /// newer build wrote — and the launch then knows nothing of the last run.
    static func load(from directory: URL) -> RunMarker? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(fileName)) else { return nil }
        return try? JSONDecoder().decode(RunMarker.self, from: data)
    }

    @discardableResult
    func save(in directory: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(self)
                .write(to: directory.appendingPathComponent(Self.fileName), options: .atomic)
            return true
        } catch {
            Diagnostics.log("failed to save the run marker: \(error)")
            return false
        }
    }

    /// The events a launch records about the run before it: how that run
    /// ended, when the run left no word of it or its word needed confirming;
    /// a macOS update and the Mac's start, if it has started since; and this
    /// launch.
    ///
    /// A log out, restart or shut down macOS asked Daybook to quit for can
    /// still be called off by another app after Daybook has gone. What the
    /// launch finds confirms it: a new boot for a restart or shut down, a
    /// login session that began after Daybook quit for a log out. A power-off
    /// macOS announced without naming one is settled the same way — the Mac
    /// went down, you logged out, or neither happened and only Daybook quit.
    /// Nothing is guessed from how long anything took: an update, a FileVault
    /// unlock or an app that holds up a restart can each take any time.
    ///
    /// A run ends without a word in four ways, told apart by what is left:
    /// - A crash leaves a crash report about this run's process, written
    ///   after it began. It is checked first, since a Mac restarted later
    ///   does not undo it.
    /// - Otherwise a new boot means the Mac went down while Daybook ran
    ///   without asking it to quit: a panic, if a panic report was written
    ///   since, else power lost — the cord, a flat battery, the power button.
    /// - On the same boot with no report, something stopped Daybook outright:
    ///   Force Quit, `kill`, or macOS ending it.
    static func previousRun(_ marker: RunMarker?, _ launch: LaunchEvidence) -> [MachineEvent] {
        var events: [MachineEvent] = []
        if let marker {
            // A run the kernel would not name its boot to leaves the boot
            // unknown; it is not taken as a restart.
            let rebooted = !marker.bootSessionID.isEmpty && marker.bootSessionID != launch.bootSessionID
            let lastSeen = marker.heartbeat
            let loggedBackIn = launch.consoleLogin.map { $0 > lastSeen } ?? false
            // "Cancelled" is a claim too: it needs the boot or the login
            // session known. Without them only the quit is certain.
            let bootKnown = !marker.bootSessionID.isEmpty
            // Another app's quit kept as the exit its reason named, as the
            // build before the sender rule did: System Settings' Quit &
            // Reopen carries macOS's own log-out reason.
            let otherApp = marker.quitSender.flatMap { QuitSender.appName($0) }
            switch marker.exit {
            case let exit? where otherApp != nil && [.restart, .shutDown, .logOut, .powerOffUnknown].contains(exit):
                events.append(MachineEvent(kind: .quitByApp, at: lastSeen, detail: otherApp))
            case .restart?:
                let kind: MachineEvent.Kind = rebooted ? .restart : bootKnown ? .restartCancelled : .quit
                events.append(MachineEvent(kind: kind, at: lastSeen))
            case .shutDown?:
                let kind: MachineEvent.Kind = rebooted ? .shutDown : bootKnown ? .shutDownCancelled : .quit
                events.append(MachineEvent(kind: kind, at: lastSeen))
            case .logOut?:
                let kind: MachineEvent.Kind = rebooted || loggedBackIn ? .logOut
                    : launch.consoleLogin == nil ? .quit : .logOutCancelled
                events.append(MachineEvent(kind: kind, at: lastSeen))
            case .powerOffUnknown?:
                let kind: MachineEvent.Kind = rebooted ? .restartOrShutDown : loggedBackIn ? .logOut : .quit
                events.append(MachineEvent(kind: kind, at: lastSeen))
            case .some:
                break // Recorded as it happened.
            case nil:
                let windowEnd = rebooted ? launch.bootTime : launch.now
                if let report = launch.crashReports.first(where: { report in
                    report.date >= marker.launchedAt && report.date <= windowEnd
                        && (report.pid == nil || marker.pid == nil || report.pid == marker.pid)
                }) {
                    events.append(MachineEvent(kind: .crashed, at: lastSeen,
                                               latest: max(lastSeen, report.date)))
                } else if rebooted {
                    let panicked = launch.panicReports.contains { $0 >= lastSeen && $0 <= launch.now }
                    events.append(MachineEvent(kind: panicked ? .kernelPanic : .powerLost,
                                               at: lastSeen, latest: max(lastSeen, launch.bootTime)))
                } else {
                    events.append(MachineEvent(kind: .forceQuit, at: lastSeen,
                                               latest: max(lastSeen, launch.now)))
                }
            }
            if rebooted {
                if let before = marker.osVersion, !before.isEmpty, !launch.osVersion.isEmpty,
                   before != launch.osVersion {
                    events.append(MachineEvent(kind: .macOSUpdated, at: launch.bootTime, detail: launch.osVersion))
                }
                events.append(MachineEvent(kind: .macStarted, at: launch.bootTime))
            }
        }
        events.append(MachineEvent(kind: .daybookStarted, at: launch.now))
        return events
    }
}

/// Who sent a quit, as the run marker keeps it: a bundle identifier, or an
/// executable's path for a process without one.
enum QuitSender {
    /// loginwindow quits apps only for macOS's own log out, restart or shut down.
    static func isMacOS(_ sender: String) -> Bool {
        sender == "com.apple.loginwindow" || sender.hasSuffix("/loginwindow")
    }

    /// The name to show for another app that quit Daybook; nil for macOS's
    /// own quits and the Dock's, which is the person's own Quit. System
    /// Settings sends its Quit & Reopen from a privacy extension.
    static func appName(_ sender: String, named name: String? = nil) -> String? {
        guard !isMacOS(sender), sender != "com.apple.dock" else { return nil }
        if sender == "com.apple.systempreferences" || sender.hasPrefix("com.apple.settings") {
            return "System Settings"
        }
        return name ?? (sender.hasPrefix("/") ? (sender as NSString).lastPathComponent : sender)
    }
}
