import AppKit
import Combine
import Sparkle

/// What Settings needs from an updater. The running app's is Sparkle; the
/// snapshot harness draws the Updates page with a stand-in, so the page's
/// controls are seen without the network.
protocol UpdateControlling: ObservableObject where ObjectWillChangePublisher == ObservableObjectPublisher {
    var canCheckForUpdates: Bool { get }
    var lastCheck: Date? { get }
    var automaticallyChecks: Bool { get set }
    var frequency: UpdateFrequency { get set }
    var installMode: UpdateInstallMode { get set }
    func checkForUpdates()
}

/// The app's updater: Sparkle, reading the release feed on GitHub and
/// installing only updates signed with the key in `SUPublicEDKey`. Created
/// once, by the running app; fixtures and the self-test never start it, so
/// they never reach the network.
final class AppUpdater: NSObject, UpdateControlling, SPUUpdaterDelegate {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var lastCheck: Date?
    /// Whether a relaunch now would lose something; the countdown waits.
    var isBusy: () -> Bool = { false }

    /// What `isBusy` asks in the running app: a note, the away question or a
    /// naming in the window, or a rule or category form.
    static func wouldLoseWork(store: SessionStore, settings: SettingsModel) -> Bool {
        store.holdsUnsavedWork || settings.holdsOpenForm
    }
    /// Runs just before Sparkle quits the app to reopen the new version.
    var onRelaunch: () -> Void = {}
    private var controller: SPUStandardUpdaterController?
    private var canCheckObservation: NSKeyValueObservation?
    private let countdown = UpdateCountdownPanel()
    /// An update downloaded and put off with Later. Taking over the install
    /// stalls Sparkle's schedule until the app quits, so the app offers it
    /// again itself: from Check for Updates, and after `reofferDelay`.
    private var pending: (version: String, install: () -> Void)?
    private var reoffer: DispatchWorkItem?
    static let reofferDelay: TimeInterval = 4 * 3_600

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
    /// behind whatever is. An update already waiting is offered again rather
    /// than looked for.
    func checkForUpdates() {
        if let pending {
            offer(version: pending.version, install: pending.install)
            return
        }
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

    private func offer(version: String, install: @escaping () -> Void) {
        reoffer?.cancel()
        pending = (version, install)
        countdown.show(version: version, isBusy: isBusy, install: { [weak self] in
            self?.pending = nil
            install()
        }, later: { [weak self] in
            self?.scheduleReoffer()
        })
    }

    private func scheduleReoffer() {
        let work = DispatchWorkItem { [weak self] in
            guard let self, let pending = self.pending else { return }
            self.offer(version: pending.version, install: pending.install)
        }
        reoffer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.reofferDelay, execute: work)
    }

    private func noteCheck(_ updater: SPUUpdater) {
        DispatchQueue.main.async { [weak self] in self?.lastCheck = updater.lastUpdateCheckDate ?? Date() }
    }

    // MARK: SPUUpdaterDelegate

    /// A quietly downloaded update is ready. Sparkle would wait for the next
    /// quit; the reader asked for it sooner, with a countdown they can put
    /// off. Put off, it is offered again, and still installs at the next quit.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        let version = item.displayVersionString
        DispatchQueue.main.async { [weak self] in self?.offer(version: version, install: immediateInstallHandler) }
        return true
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) { noteCheck(updater) }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) { noteCheck(updater) }
    func updaterWillRelaunchApplication(_ updater: SPUUpdater) { onRelaunch() }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        noteCheck(updater)
    }
}
