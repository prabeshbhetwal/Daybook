import AppKit

/// Writes down, as they happen, the machine events that stop or resume
/// recording, and at launch how the previous run ended. Owns the event log,
/// this run's marker and the heartbeat that keeps the marker's last-seen time
/// fresh.
///
/// The heartbeat is its own minute timer, not `SessionStore`'s ticker: that
/// one rests while nobody is at the Mac, and a power cut then would be dated
/// to whenever it last ran.
final class MachineEventRecorder {
    static let heartbeatInterval: TimeInterval = 60
    /// A power-off macOS announced and never followed with a quit was called
    /// off — another app refused to quit — once this long has passed.
    static let powerOffGrace: TimeInterval = 120

    let log: MachineEventLog
    private let directory: URL
    private let now: () -> Date
    private var marker: RunMarker?
    private var timer: Timer?
    private var powerOffAnnounced: Date?
    private var relaunchingForUpdate = false

    init(directory: URL = SessionArchive.defaultDirectory, now: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.now = now
        log = MachineEventLog(directory: directory)
    }

    /// Records how the previous run ended and marks this one as running.
    ///
    /// The previous run is named only once this run's marker has replaced
    /// its own: a launch that could not save would leave it for the next
    /// launch to read and name again. `evidence` is nil only when the kernel
    /// would not name this boot; then nothing about the last run is known.
    func start(evidence: LaunchEvidence?) {
        guard marker == nil else { return }
        let launched = evidence?.now ?? now()
        let previous = RunMarker.load(from: directory)
        let fresh = RunMarker(bootSessionID: evidence?.bootSessionID ?? "", launchedAt: launched,
                              heartbeat: launched, exit: nil,
                              pid: ProcessInfo.processInfo.processIdentifier)
        marker = fresh
        if fresh.save(in: directory), let evidence {
            log.append(RunMarker.previousRun(previous, evidence))
        } else {
            log.append([MachineEvent(kind: .daybookStarted, at: launched)])
        }
        let timer = Timer(timeInterval: Self.heartbeatInterval, repeats: true) { [weak self] _ in self?.beat() }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// An event seen as it happened.
    func record(_ kind: MachineEvent.Kind) {
        guard kind != .powerOffUnknown else {
            // Kept in the marker, not the log: the quit that follows names the
            // reason, and only if none comes does the next launch record this.
            guard marker?.exit == nil else { return }
            powerOffAnnounced = now()
            marker?.exit = .powerOffUnknown
            beat()
            return
        }
        log.append([MachineEvent(kind: kind, at: now())])
        beat()
    }

    /// Sparkle is about to quit Daybook to install an update and reopen it.
    func markUpdateRelaunch() { relaunchingForUpdate = true }

    /// How this run is ending, from the reason macOS gave for quitting it.
    /// The first call decides; a later one changes nothing.
    func recordExit(quitReason: OSType?) {
        guard var marker, marker.exit == nil || marker.exit == .powerOffUnknown else { return }
        // The quit for a log out, restart or shut down can come well after
        // macOS announced it, while other apps ask to save first. Recording
        // stopped at the announcement, so that is when the event is dated.
        let at = powerOffAnnounced ?? now()
        let kind = relaunchingForUpdate
            ? .updateRelaunch
            : Self.exitKind(quitReason: quitReason, powerOffAnnounced: powerOffAnnounced != nil)
        // Another app can still call a restart or shut down off after Daybook
        // has quit for it, so these and an unnamed power-off wait in the
        // marker for the next launch, which sees whether the Mac restarted.
        if ![.restart, .shutDown, .powerOffUnknown].contains(kind) {
            log.append([MachineEvent(kind: kind, at: at)])
        }
        marker.exit = kind
        marker.heartbeat = at
        marker.save(in: directory)
        self.marker = marker
        timer?.invalidate()
        timer = nil
    }

    /// The kind of exit a quit reason names. ⌘Q and the Quit button give none.
    static func exitKind(quitReason: OSType?, powerOffAnnounced: Bool) -> MachineEvent.Kind {
        switch quitReason {
        case OSType(kAERestart)?, OSType(kAEShowRestartDialog)?: return .restart
        case OSType(kAEShutDown)?, OSType(kAEShowShutdownDialog)?: return .shutDown
        case OSType(kAEReallyLogOut)?, OSType(kAELogOut)?: return .logOut
        default: return powerOffAnnounced ? .powerOffUnknown : .quit
        }
    }

    /// The reason attached to the quit Apple event being handled now. macOS
    /// attaches one when it logs out, restarts or shuts down; it is readable
    /// only while that event is current, inside `applicationShouldTerminate`.
    static func currentQuitReason() -> OSType? {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEQuitApplication) else { return nil }
        let keyword = AEKeyword(kAEQuitReason)
        return (event.attributeDescriptor(forKeyword: keyword)
                ?? event.paramDescriptor(forKeyword: keyword))?.typeCodeValue
    }

    private func beat() {
        guard var marker else { return }
        marker.heartbeat = now()
        if marker.exit == .powerOffUnknown, let announced = powerOffAnnounced,
           marker.heartbeat.timeIntervalSince(announced) > Self.powerOffGrace {
            marker.exit = nil
            powerOffAnnounced = nil
        }
        marker.save(in: directory)
        self.marker = marker
    }
}
