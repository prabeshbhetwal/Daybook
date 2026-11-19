import AppKit
import ApplicationServices
import Foundation

/// The Site signal panel's model: consent, the confirmed apps and the remembered
/// sites, written to the same preferences the reader reads (`SiteSignalSettings`),
/// so a change reaches the next read. Nothing here sees an address. The trust
/// check, the permission prompt and the opener are handed in, so checks never
/// reach Accessibility or System Settings.
final class SiteSignalModel: ObservableObject {
    enum Purpose {
        case turnOn, changeApps

        var title: String { self == .turnOn ? "Turn on the site signal" : "Change Apps" }
        var confirmTitle: String { self == .turnOn ? "Turn On" : "Save Apps" }
    }

    struct Candidate: Identifiable, Equatable {
        let bundleID: String
        let name: String
        var ticked: Bool
        var id: String { bundleID }
    }

    /// The consent sheet's list while it is open.
    struct AppChoice: Equatable {
        let purpose: Purpose
        var candidates: [Candidate]
    }

    struct RememberedSite: Identifiable, Equatable {
        let name: String
        let kind: SiteKind
        var id: String { name }
    }

    static let refusal = "Daybook does not keep this site"
    static let accessibilitySettings =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    /// One that can do nothing, for Settings drawn outside the running app: the
    /// gate is off, as it is on every Mac until a probe report opens it, and its
    /// preferences are this process's own.
    static let unavailable = SiteSignalModel(
        settings: SiteSignalSettings(defaults: MemoryDefaults.suite(named: "fc-site-signal-unavailable")!),
        gateOn: false, isTrusted: { false }, promptForTrust: {}, open: { _ in }, webLinkApps: { [] })

    /// The app's own: the gate for this macOS, the real trust check and prompt,
    /// and `defaults`, which must be the preferences the reader was installed with.
    static func live(defaults: UserDefaults) -> SiteSignalModel {
        let macOSMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        return SiteSignalModel(
            settings: SiteSignalSettings(defaults: defaults),
            gateOn: SignalGate.isOn(.siteKind, macOSMajor: macOSMajor),
            isTrusted: { AXIsProcessTrusted() },
            // Only after the person chose Turn On in the consent sheet.
            promptForTrust: {
                _ = AXIsProcessTrustedWithOptions(
                    [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            },
            open: { NSWorkspace.shared.open($0) },
            webLinkApps: WebLinkApps.current)
    }

    private let settings: SiteSignalSettings
    private let gateOn: Bool
    private let isTrusted: () -> Bool
    private let promptForTrust: () -> Void
    private let open: (URL) -> Void
    private let webLinkApps: () -> [(bundleID: String, name: String)]

    /// Read when the panel appears, when the app becomes active and after Turn On; never on a timer.
    @Published private(set) var trusted: Bool
    @Published private(set) var appChoice: AppChoice?
    @Published var newSite = "" { didSet { if newSite != oldValue { refused = false } } }
    @Published var newSiteKind: SiteKind = .documentation
    @Published private(set) var refused = false
    /// The sites switching Remember sites off would delete, while that question is open.
    @Published private(set) var pendingForgetCount: Int?

    init(settings: SiteSignalSettings, gateOn: Bool, isTrusted: @escaping () -> Bool,
         promptForTrust: @escaping () -> Void, open: @escaping (URL) -> Void,
         webLinkApps: @escaping () -> [(bundleID: String, name: String)]) {
        self.settings = settings
        self.gateOn = gateOn
        self.isTrusted = isTrusted
        self.promptForTrust = promptForTrust
        self.open = open
        self.webLinkApps = webLinkApps
        trusted = isTrusted()
    }

    static func text(for state: SiteSignalState) -> String {
        switch state {
        case .off: return "Off"
        case .on: return "On"
        case .awaitingPermission: return "Waiting for Accessibility permission"
        case .unavailable: return "Not yet available on this version of macOS"
        }
    }

    var state: SiteSignalState {
        SiteSignalSettings.state(consented: settings.isConsented, gateOn: gateOn, trusted: trusted)
    }
    var stateText: String { Self.text(for: state) }
    /// Stored consent can always be withdrawn, even on a macOS whose gate is off.
    var canChangeSwitch: Bool { gateOn || settings.isConsented }
    var canChangeApps: Bool { gateOn && settings.isConsented }

    /// On while consent is stored. Turning on only opens the consent sheet, and
    /// only with the gate open; nothing is stored before Turn On. Turning off
    /// takes effect at once (R12).
    var isOn: Bool {
        get { settings.isConsented }
        set {
            guard newValue != isOn else { return }
            if !newValue {
                change { settings.turnOff() }
            } else if gateOn {
                present(.turnOn)
            }
        }
    }

    func changeApps() {
        guard canChangeApps else { return }
        present(.changeApps)
    }

    /// Known browsers ticked, or the last confirmed apps when there are some.
    private func present(_ purpose: Purpose) {
        let last = Set(settings.apps)
        let candidates = SiteSignalSettings.candidates(webLinkApps()).map {
            Candidate(bundleID: $0.bundleID, name: $0.name,
                      ticked: last.isEmpty ? $0.ticked : last.contains($0.bundleID))
        }
        appChoice = AppChoice(purpose: purpose, candidates: candidates)
    }

    func setTicked(_ bundleID: String, _ ticked: Bool) {
        guard let index = appChoice?.candidates.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        appChoice?.candidates[index].ticked = ticked
    }

    var canConfirm: Bool { appChoice?.candidates.contains(where: \.ticked) == true }

    func confirmApps() {
        // Save Apps changes a list; only Turn On gives consent, so withdrawn consent is not given again.
        guard gateOn, canConfirm, let choice = appChoice, choice.purpose == .turnOn || settings.isConsented else { return }
        change { settings.turnOn(apps: choice.candidates.filter(\.ticked).map(\.bundleID)) }
        appChoice = nil
        refreshTrust()
        if choice.purpose == .turnOn, !trusted { promptForTrust() }
    }

    func cancelAppChoice() { appChoice = nil }

    func refreshTrust() {
        let now = isTrusted()
        if now != trusted { trusted = now }
    }

    func openAccessibilitySettings() { open(Self.accessibilitySettings) }

    /// Without the gate a list can only be switched off, which deletes it.
    var canChangeRemembers: Bool { gateOn || settings.remembers }

    /// Switching off deletes the list, so a list with sites in it asks first (`pendingForgetCount`).
    var remembers: Bool {
        get { settings.remembers }
        set {
            guard canChangeRemembers, newValue != remembers else { return }
            let count = settings.rememberedSites.count
            if !newValue, count > 0 {
                pendingForgetCount = count
                return
            }
            change { settings.setRemembers(newValue) }
        }
    }

    var rememberedSites: [RememberedSite] {
        settings.rememberedSites.map { RememberedSite(name: $0.key, kind: $0.value) }.sorted { $0.name < $1.name }
    }

    var canAdd: Bool { gateOn && !newSite.trimmingCharacters(in: .whitespaces).isEmpty }

    func addSite() {
        guard canAdd else { return }
        objectWillChange.send()
        if settings.remember(newSite, as: newSiteKind) != nil { newSite = "" } else { refused = true }
    }

    func forget(_ siteName: String) { change { settings.forget(siteName) } }

    static func forgetTitle(_ count: Int) -> String {
        count == 1 ? "Delete 1 Remembered Site?" : "Delete \(count) Remembered Sites?"
    }

    /// Delete was chosen: the list goes and Remember sites switches off.
    func confirmForgetSites() {
        guard pendingForgetCount != nil else { return }
        pendingForgetCount = nil
        change { settings.setRemembers(false) }
    }

    func cancelForgetSites() { pendingForgetCount = nil }

    /// Spec section 9's tiers on this Mac. The model line says only whether on-device AI is on (R19).
    func tiers(onDeviceAI: Bool) -> [(title: String, on: Bool)] {
        [("Hands-on work, quiet, and video or calls where an app holds the screen", true),
         ("On-device AI", onDeviceAI),
         ("The kind of site in the front browser tab", state == .on)]
    }

    private func change(_ body: () -> Void) {
        objectWillChange.send()
        body()
    }
}

extension SettingsPrivacyDisclosure {
    /// The site signal in the words of its consent sheet, for the Privacy disclosure.
    static let siteSignalDetail = " The site signal is off unless you turn it on; it then reads the address of"
        + " the front tab in the apps you confirm, keeps only the kind of site, discards the address, never"
        + " reads page titles or page content, and keeps a site's name only when you add it under Remember sites,"
        + " never one Daybook knows as banking, health, government, sign-in or adult."
}
