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
                              pid: ProcessInfo.processInfo.processIdentifier,
                              osVersion: evidence?.osVersion)
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

    /// What a quit Apple event said: the reason macOS gave, if any, and who
    /// sent it — a bundle identifier, or an executable's path for a process
    /// without one.
    struct QuitRequest: Equatable {
        var reason: OSType?
        var sender: String?
        var senderName: String?
    }

    /// Exits only the next launch can confirm: another app can call a log
    /// out, restart or shut down off after Daybook has quit for it, and an
    /// unnamed power-off may have been nothing at all. They wait in the marker.
    static let confirmedNextLaunch: Set<MachineEvent.Kind> = [.logOut, .restart, .shutDown, .powerOffUnknown]

    /// How this run is ending, from the quit's reason and sender. The first
    /// call decides, unless it could only say a power-off was announced; a
    /// later call may still name that one.
    func recordExit(_ quit: QuitRequest?) {
        guard var marker, marker.exit == nil || marker.exit == .powerOffUnknown else { return }
        // The quit for a log out, restart or shut down can come well after
        // macOS announced it, while other apps ask to save first. Recording
        // stopped at the announcement, so that is when the event is dated.
        let at = powerOffAnnounced ?? now()
        let exit: (kind: MachineEvent.Kind, detail: String?) = relaunchingForUpdate
            ? (.updateRelaunch, nil)
            : Self.exit(for: quit, powerOffAnnounced: powerOffAnnounced != nil)
        if !Self.confirmedNextLaunch.contains(exit.kind) {
            log.append([MachineEvent(kind: exit.kind, at: at, detail: exit.detail)])
        }
        marker.exit = exit.kind
        marker.heartbeat = at
        // `applicationWillTerminate` calls again with no event; what the quit
        // said stays.
        if let quit {
            marker.quitReason = quit.reason.map(Self.fourLetters)
            marker.quitSender = quit.sender
        }
        marker.save(in: directory)
        self.marker = marker
        timer?.invalidate()
        timer = nil
    }

    /// What a quit says about how the run ended.
    ///
    /// A reason macOS gave names a log out, restart or shut down. Without one,
    /// the sender decides. loginwindow quits apps only for macOS's own log
    /// out, restart or shut down, so its quit waits for the next launch to say
    /// which, however long the announcement came before it. The Dock's is the
    /// person's own Quit. Any other sender quit Daybook itself — System
    /// Settings applying a permission makes AppKit announce a power-off too,
    /// so the announcement alone names nothing. ⌘Q sends no event at all.
    static func exit(for quit: QuitRequest?,
                     powerOffAnnounced: Bool) -> (kind: MachineEvent.Kind, detail: String?) {
        switch quit?.reason {
        case OSType(kAERestart)?, OSType(kAEShowRestartDialog)?: return (.restart, nil)
        case OSType(kAEShutDown)?, OSType(kAEShowShutdownDialog)?: return (.shutDown, nil)
        case OSType(kAEReallyLogOut)?, OSType(kAELogOut)?: return (.logOut, nil)
        default: break
        }
        if let quit, let sender = quit.sender {
            if sender == "com.apple.loginwindow" || sender.hasSuffix("/loginwindow") {
                return (.powerOffUnknown, nil)
            }
            if sender != "com.apple.dock" { return (.quitByApp, displayName(of: quit)) }
        }
        return (powerOffAnnounced ? .powerOffUnknown : .quit, nil)
    }

    private static func displayName(of quit: QuitRequest) -> String {
        if let sender = quit.sender,
           sender == "com.apple.systempreferences" || sender.hasPrefix("com.apple.settings") {
            return "System Settings"
        }
        return quit.senderName ?? quit.sender.map { ($0 as NSString).lastPathComponent } ?? "another app"
    }

    private static func fourLetters(_ code: OSType) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// The quit Apple event being handled now: its reason and its sender. It
    /// is readable only while that event is current, inside
    /// `applicationShouldTerminate`; ⌘Q and the Quit button send none.
    static func currentQuit() -> QuitRequest? {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEQuitApplication) else { return nil }
        let reasonKey = AEKeyword(kAEQuitReason)
        let reason = (event.attributeDescriptor(forKeyword: reasonKey)
                      ?? event.paramDescriptor(forKeyword: reasonKey))?.typeCodeValue
        let pid = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value
        let app = pid.flatMap { NSRunningApplication(processIdentifier: $0) }
        return QuitRequest(reason: reason == 0 ? nil : reason,
                           sender: app?.bundleIdentifier ?? pid.flatMap(executablePath(of:)),
                           senderName: app?.localizedName)
    }

    private static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
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
