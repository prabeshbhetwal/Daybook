import Cocoa

/// Owns the `NSStatusItem`, the menu, and the one permitted cosmetic timer (D3).
final class MenuBarController: NSObject, NSMenuDelegate {

    var onRenameRequested: (() -> Void)?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private weak var engine: SessionEngine?
    private var titleTimer: Timer?

    init(engine: SessionEngine) {
        self.engine = engine
        super.init()

        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        statusItem.button?.imagePosition = .noImage

        rebuildMenu()
        refreshTitle()
    }

    deinit {
        titleTimer?.invalidate()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - State plumbing

    func stateChanged(_ state: SessionState) {
        if state.isRunning {
            startTitleTimer()
        } else {
            stopTitleTimer()
        }
        refreshTitle()
    }

    // MARK: - Title (D3, D15, D16)

    private func startTitleTimer() {
        guard titleTimer == nil else { return }
        let timer = Timer(timeInterval: FocusConstants.titleRefreshInterval,
                          repeats: true) { [weak self] _ in
            self?.refreshTitle()
        }
        timer.tolerance = FocusConstants.titleRefreshTolerance
        RunLoop.main.add(timer, forMode: .common)
        titleTimer = timer
    }

    private func stopTitleTimer() {
        titleTimer?.invalidate()
        titleTimer = nil
    }

    /// Purely cosmetic: reads no state machine input and drives no transition.
    private func refreshTitle() {
        guard let engine else { return }
        let paused = !engine.state.isRunning && engine.state != .idle
        var text = MenuBarController.format(engine.elapsed)
        if !engine.sessionName.isEmpty {
            text = "\(engine.sessionName) · \(text)"
        }
        if paused {
            text = "⏸ \(text)"
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize,
                                                    weight: .regular),
            .foregroundColor: paused ? NSColor.secondaryLabelColor : NSColor.labelColor
        ]
        statusItem.button?.attributedTitle = NSAttributedString(string: text,
                                                               attributes: attributes)
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        refreshTitle()
        rebuildMenu()
    }

    // MARK: - Menu construction

    private func rebuildMenu() {
        guard let engine else { return }
        menu.removeAllItems()

        let name = engine.sessionName.isEmpty ? "Untitled" : engine.sessionName
        menu.addItem(action(title: "Session: \u{201C}\(name)\u{201D}",
                            selector: #selector(renameSession),
                            key: "n"))
        menu.addItem(info("Status: \(engine.state.displayName) · "
                          + MenuBarController.format(engine.elapsed)))
        let category = engine.categories.category(for: engine.currentAppBundleID)
        menu.addItem(info("Active: \(engine.currentAppName) — \(category.displayName)"))

        menu.addItem(.separator())

        // `.awaitingUserDecision` also offers Resume, so a suppressed or dismissed
        // alert can never leave the session with no way back.
        let offersResume = !engine.state.isRunning && engine.state != .idle
        let pauseTitle = offersResume ? "Resume Session" : "Pause Session"
        menu.addItem(action(title: pauseTitle, selector: #selector(togglePause), key: "p"))
        menu.addItem(overrideItem(for: engine))
        menu.addItem(settingsItem(for: engine))

        menu.addItem(.separator())

        menu.addItem(info("Sessions today: \(engine.sessionsToday)"))
        menu.addItem(action(title: "Reset Session", selector: #selector(resetSession), key: "r"))
        menu.addItem(action(title: "Quit FocusContinuity", selector: #selector(quit), key: "q"))
    }

    private func overrideItem(for engine: SessionEngine) -> NSMenuItem {
        let item = NSMenuItem(title: "Override \u{201C}\(engine.currentAppName)\u{201D} as…",
                              action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let current = engine.categories.category(for: engine.currentAppBundleID)
        let hasBundleID = engine.currentAppBundleID != nil

        for category in AppCategory.allCases {
            let sub = NSMenuItem(title: category.displayName,
                                 action: #selector(setOverride(_:)),
                                 keyEquivalent: "")
            sub.target = self
            sub.representedObject = category.rawValue
            sub.state = category == current ? .on : .off
            sub.isEnabled = hasBundleID
            submenu.addItem(sub)
        }
        item.submenu = submenu
        item.isEnabled = hasBundleID
        return item
    }

    private func settingsItem(for engine: SessionEngine) -> NSMenuItem {
        let thresholds = NSMenu()
        thresholds.autoenablesItems = false
        for option in FocusConstants.thresholdOptions {
            let minutes = Int(option / 60)
            let sub = NSMenuItem(title: "\(minutes)m",
                                 action: #selector(setThreshold(_:)),
                                 keyEquivalent: "")
            sub.target = self
            sub.representedObject = option
            sub.state = abs(option - engine.breakThreshold) < 1 ? .on : .off
            thresholds.addItem(sub)
        }

        let thresholdItem = NSMenuItem(title: "Break Threshold", action: nil, keyEquivalent: "")
        thresholdItem.submenu = thresholds

        let settingsMenu = NSMenu()
        settingsMenu.autoenablesItems = false
        settingsMenu.addItem(thresholdItem)

        let item = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        item.submenu = settingsMenu
        return item
    }

    private func action(title: String, selector: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        item.isEnabled = true
        return item
    }

    private func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - Actions

    @objc private func renameSession() {
        onRenameRequested?()
    }

    @objc private func togglePause() {
        guard let engine else { return }
        let offersResume = !engine.state.isRunning && engine.state != .idle
        engine.transition(on: offersResume ? .manualResume : .manualPause)
    }

    @objc private func setOverride(_ sender: NSMenuItem) {
        guard let engine,
              let raw = sender.representedObject as? String,
              let category = AppCategory(rawValue: raw),
              let bundleID = engine.currentAppBundleID else { return }
        engine.applyOverride(category, to: bundleID)
    }

    @objc private func setThreshold(_ sender: NSMenuItem) {
        guard let engine, let value = sender.representedObject as? TimeInterval else { return }
        engine.breakThreshold = value
    }

    @objc private func resetSession() {
        engine?.transition(on: .resetSession)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
