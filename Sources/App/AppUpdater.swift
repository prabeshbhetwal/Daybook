import AppKit
import Combine
import Sparkle

/// The app's updater: Sparkle, reading the release feed on GitHub and
/// installing only updates signed with the key in `SUPublicEDKey`. Created
/// once, by the running app; fixtures and the self-test never start it, so
/// they never reach the network.
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var lastCheck: Date?
    private var controller: SPUStandardUpdaterController?
    private var canCheckObservation: NSKeyValueObservation?
    private let countdown = UpdateCountdownPanel()

    override init() {
        super.init()
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self,
                                                      userDriverDelegate: nil)
        self.controller = controller
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) {
            [weak self] updater, _ in
            DispatchQueue.main.async { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
        lastCheck = controller.updater.lastUpdateCheckDate
    }

    /// A menu bar app is often not in front, and Sparkle's window would open
    /// behind whatever is.
    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { objectWillChange.send(); controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    var frequency: UpdateFrequency {
        get { controller.map { UpdateFrequency.nearest(to: $0.updater.updateCheckInterval) } ?? .weekly }
        set { objectWillChange.send(); controller?.updater.updateCheckInterval = newValue.interval }
    }

    var installMode: UpdateInstallMode {
        get { controller?.updater.automaticallyDownloadsUpdates == true ? .automatic : .askFirst }
        set { objectWillChange.send(); controller?.updater.automaticallyDownloadsUpdates = newValue == .automatic }
    }

    // MARK: SPUUpdaterDelegate

    /// A quietly downloaded update is ready. Sparkle would wait for the next
    /// quit; the reader asked for it now, with a countdown they can cancel.
    /// Cancelled, Sparkle still installs it when the app next quits.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        DispatchQueue.main.async { [countdown] in
            countdown.show(version: item.displayVersionString, install: immediateInstallHandler)
        }
        return true
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        DispatchQueue.main.async { [weak self] in self?.lastCheck = updater.lastUpdateCheckDate }
    }
}
