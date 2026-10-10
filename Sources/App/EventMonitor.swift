import Cocoa

/// Owns every system subscription. Nothing here polls or infers state (C4) —
/// each notification is forwarded verbatim through a typed closure.
final class EventMonitor {

    var onScreenLocked: (() -> Void)?
    var onScreenUnlocked: (() -> Void)?
    var onSystemWillSleep: (() -> Void)?
    var onSystemDidWake: (() -> Void)?
    var onAppActivated: ((NSRunningApplication) -> Void)?
    var onWillPowerOff: (() -> Void)?
    /// Every notification above, named for the machine event log. Display
    /// sleep and system sleep share `onSystemWillSleep`; here they differ.
    /// Called after the closure above it, so writing the log never moves the
    /// moment the engine reads.
    var onMachineEvent: ((MachineEvent.Kind) -> Void)?

    private var workspaceTokens: [NSObjectProtocol] = []
    private var distributedTokens: [NSObjectProtocol] = []
    private var isRunning = false

    deinit {
        stop()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()

        // Screen lock / unlock — distributed notifications, not workspace ones.
        distributedTokens.append(
            distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"),
                                    object: nil, queue: .main) { [weak self] _ in
                self?.onScreenLocked?()
                self?.onMachineEvent?(.lock)
            })
        distributedTokens.append(
            distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"),
                                    object: nil, queue: .main) { [weak self] _ in
                self?.onScreenUnlocked?()
                self?.onMachineEvent?(.unlock)
            })

        // Sleep / wake — workspace notification centre (never NotificationCenter.default).
        let sleeps: [(Notification.Name, MachineEvent.Kind)] = [
            (NSWorkspace.willSleepNotification, .systemSleep),
            (NSWorkspace.screensDidSleepNotification, .displaySleep),
        ]
        for (name, kind) in sleeps {
            workspaceTokens.append(
                workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.onSystemWillSleep?()
                    self?.onMachineEvent?(kind)
                })
        }
        let wakes: [(Notification.Name, MachineEvent.Kind)] = [
            (NSWorkspace.didWakeNotification, .wake),
            (NSWorkspace.screensDidWakeNotification, .displayWake),
        ]
        for (name, kind) in wakes {
            workspaceTokens.append(
                workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.onSystemDidWake?()
                    self?.onMachineEvent?(kind)
                })
        }

        // Fast user switching behaves like a lock for our purposes.
        workspaceTokens.append(
            workspace.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification,
                                  object: nil, queue: .main) { [weak self] _ in
                self?.onScreenLocked?()
                self?.onMachineEvent?(.userSwitchedOut)
            })
        workspaceTokens.append(
            workspace.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification,
                                  object: nil, queue: .main) { [weak self] _ in
                self?.onScreenUnlocked?()
                self?.onMachineEvent?(.userSwitchedIn)
            })

        workspaceTokens.append(
            workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                  object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication else { return }
                self?.onAppActivated?(app)
            })

        workspaceTokens.append(
            workspace.addObserver(forName: NSWorkspace.willPowerOffNotification,
                                  object: nil, queue: .main) { [weak self] _ in
                self?.onWillPowerOff?()
                self?.onMachineEvent?(.powerOffUnknown)
            })
    }

    func stop() {
        let workspace = NSWorkspace.shared.notificationCenter
        for token in workspaceTokens { workspace.removeObserver(token) }
        workspaceTokens.removeAll()

        let distributed = DistributedNotificationCenter.default()
        for token in distributedTokens { distributed.removeObserver(token) }
        distributedTokens.removeAll()

        isRunning = false
    }
}
