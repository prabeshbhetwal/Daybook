import Cocoa

/// Lifecycle and the ownership graph. Owns the engine, monitor, menu bar and
/// alert presenter; every cross-reference downward is a closure or `weak` (C5).
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let engine = SessionEngine()
    private let monitor = EventMonitor()
    private let alerts = AlertPresenter()
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menuBar = MenuBarController(engine: engine)
        self.menuBar = menuBar

        menuBar.onRenameRequested = { [weak self] in
            guard let self else { return }
            self.alerts.presentRename(currentName: self.engine.sessionName) { [weak self] name in
                self?.engine.sessionName = name
            }
        }

        engine.onStateChanged = { [weak menuBar] state in
            menuBar?.stateChanged(state)
        }
        engine.onNeedsDecision = { [weak self] away, lastApp in
            self?.presentDecision(away: away, lastApp: lastApp)
        }

        wireMonitor()
        monitor.start()

        // D14 — restore first, resolving any gap through the extended-break path.
        // This must precede seeding the frontmost app: from `.idle` a work-app
        // activation starts a fresh session, which persists over the very
        // snapshot we are about to read.
        if let snapshot = engine.store.loadState() {
            engine.restore(from: snapshot)
        }
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            engine.transition(on: .appActivated(bundleID: frontmost.bundleIdentifier,
                                                name: frontmost.localizedName ?? "Unknown"))
        }
        if engine.state == .idle {
            engine.transition(on: .launch)
        }
        menuBar.stateChanged(engine.state)
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.persist()
        monitor.stop()
        menuBar = nil
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - Wiring

    private func wireMonitor() {
        monitor.onScreenLocked = { [weak self] in
            self?.engine.transition(on: .awayBegan(trigger: .screenLock))
        }
        monitor.onSystemWillSleep = { [weak self] in
            self?.engine.transition(on: .awayBegan(trigger: .systemSleep))
        }
        monitor.onScreenUnlocked = { [weak self] in
            self?.engine.transition(on: .awayEnded)
        }
        monitor.onSystemDidWake = { [weak self] in
            self?.engine.transition(on: .awayEnded)
        }
        monitor.onAppActivated = { [weak self] app in
            self?.engine.transition(on: .appActivated(bundleID: app.bundleIdentifier,
                                                      name: app.localizedName ?? "Unknown"))
        }
        monitor.onWillPowerOff = { [weak self] in
            self?.engine.persist()
        }
    }

    private func presentDecision(away: TimeInterval, lastApp: String) {
        alerts.presentExtendedBreak(away: away,
                                    lastApp: lastApp,
                                    afterDelay: FocusConstants.alertPresentationDelay) {
            [weak self] decision in
            self?.engine.transition(on: .decision(decision))
        }
    }
}
