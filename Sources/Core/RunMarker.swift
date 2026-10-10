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
    /// ended, when the run left no word of it or its word needed the boot to
    /// confirm it; when the Mac started, if it has started since; and this
    /// launch.
    ///
    /// A restart or a shut down can still be called off by another app after
    /// Daybook has quit for it. A new boot says it went ahead; the same boot
    /// says it was called off, and Daybook had simply quit.
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
            switch marker.exit {
            case .powerOffUnknown?:
                // Recorded when macOS announced it; the quit that would have
                // named the reason never came.
                events.append(MachineEvent(kind: .powerOffUnknown, at: lastSeen))
            case let named? where named == .restart || named == .shutDown:
                events.append(MachineEvent(kind: rebooted ? named : .quit, at: lastSeen))
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
            if rebooted { events.append(MachineEvent(kind: .macStarted, at: launch.bootTime)) }
        }
        events.append(MachineEvent(kind: .daybookStarted, at: launch.now))
        return events
    }
}
