import Foundation

enum SiteSignalConstants {
    /// Bumped whenever `consentText` changes, so a changed text asks again.
    static let consentVersion = 1
    static let consentText = "Daybook reads the address of the front browser tab, keeps only what kind of site it is, and discards the address immediately. It never reads page titles or page content."
    static let rememberDisclosure = "Daybook keeps the sites you give a kind, with that kind, on this Mac. Sites it knows as banking, health, government, sign-in or adult are never kept. Turning this off deletes the list."
    static let readTimeout: TimeInterval = 0.5
    /// A whole read gives up after this, so a browser answering each message just in time cannot hold the worker.
    static let readDeadline: TimeInterval = 1.0
    static let timeoutsBeforeSkipping = 2
    /// Safari, Safari Technology Preview, Chrome, Chrome Canary, Chromium, Firefox, Firefox Developer Edition,
    /// Arc, Dia, Edge, Brave, Opera, Vivaldi, Orion, Zen (bundle identifiers).
    static let knownBrowsers: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
        "com.google.Chrome", "com.google.Chrome.canary", "org.chromium.Chromium",
        "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition",
        "company.thebrowser.Browser", "company.thebrowser.dia",
        "com.microsoft.edgemac", "com.brave.Browser", "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi", "com.kagi.kagimacOS", "app.zen-browser.zen",
    ]
}

enum SiteSignalState: Equatable { case unavailable, off, awaitingPermission, on }

/// What one read of a browser gave. The address never leaves the reader's worker.
enum SiteAddressRead: Equatable { case address(String), failed, timedOut }

/// Reads the address of the front tab of the app with this pid, read-only.
protocol SiteAddressReading { func read(pid: pid_t, timeout: TimeInterval) -> SiteAddressRead }

/// All that leaves a read: the kind (nil for none), the app asked and when it was asked.
struct SiteReading: Equatable { let kind: SiteKind?; let app: String; let requestedAt: Date }

/// Consent, the confirmed apps and the remembered sites. Off by default; nothing
/// here stores an address.
final class SiteSignalSettings {
    /// Every key starts with this, and none goes into a backup: consent and the list stay on this Mac.
    static let keyPrefix = "fc.siteSignal."
    static let consentKey = "fc.siteSignal.consent"
    static let appsKey = "fc.siteSignal.apps"
    static let rememberKey = "fc.siteSignal.remember"
    static let sitesKey = "fc.siteSignal.sites"
    static let keys = [consentKey, appsKey, rememberKey, sitesKey]

    private let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    /// Only the whole number `turnOn` stores counts: not a Bool, a string or a fraction that reads as one.
    var isConsented: Bool {
        guard let stored = defaults.object(forKey: Self.consentKey) as? NSNumber,
              CFGetTypeID(stored) != CFBooleanGetTypeID(), !CFNumberIsFloatType(stored) else { return false }
        return stored.intValue == SiteSignalConstants.consentVersion
    }
    var apps: [String] { defaults.stringArray(forKey: Self.appsKey) ?? [] }
    var remembers: Bool { defaults.bool(forKey: Self.rememberKey) }

    var rememberedSites: [String: SiteKind] {
        (defaults.dictionary(forKey: Self.sitesKey) ?? [:])
            .compactMapValues { ($0 as? String).flatMap(SiteKind.init(rawValue:)) }
    }

    func turnOn(apps: [String]) {
        defaults.set(SiteSignalConstants.consentVersion, forKey: Self.consentKey)
        defaults.set(apps.filter { $0 != FocusConstants.bundleIdentifier }, forKey: Self.appsKey)
    }

    /// Keeps the confirmed apps so turning on again can preselect them.
    func turnOff() { defaults.removeObject(forKey: Self.consentKey) }

    func setRemembers(_ on: Bool) {
        defaults.set(on, forKey: Self.rememberKey)
        if !on { defaults.removeObject(forKey: Self.sitesKey) }
    }

    /// nil and nothing stored when the name is refused (invalid or sensitive) or remembering is off.
    @discardableResult func remember(_ typed: String, as kind: SiteKind) -> String? {
        guard remembers, let name = SiteAddress.normalisedSiteName(typed), !Self.isPublicSuffixShaped(name),
              !SiteKindTable.isSensitive(name) else { return nil }
        var sites = rememberedSites.mapValues(\.rawValue)
        sites[name] = kind.rawValue
        defaults.set(sites, forKey: Self.sitesKey)
        return name
    }

    /// `co.uk` or `com.au`: remembered, it would give a kind to every site under it, banks included.
    private static func isPublicSuffixShaped(_ name: String) -> Bool {
        let labels = name.split(separator: ".")
        return labels.count == 2 && labels[1].count == 2
            && ["co", "com", "net", "org", "gov", "edu", "ac", "or", "ne", "go", "id", "mil"].contains(String(labels[0]))
    }

    func forget(_ siteName: String) {
        var sites = rememberedSites.mapValues(\.rawValue)
        guard sites.removeValue(forKey: siteName) != nil else { return }
        defaults.set(sites, forKey: Self.sitesKey)
    }

    static func state(consented: Bool, gateOn: Bool, trusted: Bool) -> SiteSignalState {
        if !gateOn { return .unavailable }
        if !consented { return .off }
        return trusted ? .on : .awaitingPermission
    }

    /// Known browsers first, ticked; every other candidate unticked; Daybook itself left out.
    static func candidates(_ apps: [(bundleID: String, name: String)]) -> [(bundleID: String, name: String, ticked: Bool)] {
        let others = apps.filter { $0.bundleID != FocusConstants.bundleIdentifier }
        let browsers = others.filter { SiteSignalConstants.knownBrowsers.contains($0.bundleID) }
        let rest = others.filter { !SiteSignalConstants.knownBrowsers.contains($0.bundleID) }
        return browsers.map { ($0.bundleID, $0.name, true) } + rest.map { ($0.bundleID, $0.name, false) }
    }
}
