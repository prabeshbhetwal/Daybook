import Foundation
import SwiftUI

/// The Site signal panel and its consent sheet, through their model. Fakes only:
/// the trust check, the permission prompt and the opener are closures here, so
/// nothing in these checks asks macOS for Accessibility or opens System Settings.
enum SiteSignalSurfaceChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The site signal's switch says the state it is in", stateText),
        ("Without the gate the switch is disabled and stores nothing", gateOffStoresNothing),
        ("Turn On needs a ticked app, and asks for permission only when it is missing", turnOnNeedsAnApp),
        ("The consent sheet shows the consent text exactly", sheetShowsConsentText),
        ("Turning the site signal on again preselects the last confirmed apps", turnOnAgainPreselects),
        ("Trust is read again on request, and the settings link is Accessibility's", trustAndSettingsLink),
        ("Remember sites adds what is kept, refuses the rest, and removes by name", rememberedList),
        ("Switching Remember sites off asks before deleting a list", forgettingAsksFirst),
        ("Remember sites says it never keeps the sensitive sites it knows", disclosureNamesWhatItKnows),
    ]

    static let apps: [(bundleID: String, name: String)] = [
        ("com.example.reader", "Reader"), ("com.apple.Safari", "Safari"), ("com.google.Chrome", "Chrome"),
    ]

    final class Rig {
        let suite: String
        let defaults: UserDefaults
        let settings: SiteSignalSettings
        var trusted = false
        var prompts = 0
        var opened: [URL] = []
        private(set) var model: SiteSignalModel!

        init(_ name: String, gateOn: Bool = true) {
            suite = "fc-selftest-site-surface-\(name)-\(UUID().uuidString)"
            defaults = MemoryDefaults.suite(named: suite) ?? .standard
            settings = SiteSignalSettings(defaults: defaults)
            model = SiteSignalModel(settings: settings, gateOn: gateOn,
                                    isTrusted: { [unowned self] in self.trusted },
                                    promptForTrust: { [unowned self] in self.prompts += 1 },
                                    open: { [unowned self] in self.opened.append($0) },
                                    webLinkApps: { SiteSignalSurfaceChecks.apps })
        }

        var storedKeys: [String] {
            SiteSignalSettings.keys.filter { defaults.object(forKey: $0) != nil }
        }

        func close() { MemoryDefaults.remove(named: suite) }
    }

    private static func stateText() -> [String] {
        var problems: [String] = []
        let wanted: [(SiteSignalState, String)] = [
            (.off, "Off"), (.on, "On"), (.awaitingPermission, "Waiting for Accessibility permission"),
            (.unavailable, "Not yet available on this version of macOS"),
        ]
        for (state, text) in wanted {
            expect(SiteSignalModel.text(for: state) == text,
                   "\(state) reads \"\(SiteSignalModel.text(for: state))\", not \"\(text)\"", &problems)
        }
        let rig = Rig("state")
        defer { rig.close() }
        expect(rig.model.state == .off && !rig.model.isOn, "a fresh model is not off", &problems)
        rig.settings.turnOn(apps: ["com.apple.Safari"])
        rig.model.refreshTrust()
        expect(rig.model.state == .awaitingPermission && rig.model.isOn,
               "consent without trust is not awaiting permission", &problems)
        rig.trusted = true
        rig.model.refreshTrust()
        expect(rig.model.state == .on && rig.model.stateText == "On", "consent with trust is not on", &problems)
        expect(rig.model.tiers(onDeviceAI: false).map(\.on) == [true, false, true],
               "with the signal on, what Daybook can see reads \(rig.model.tiers(onDeviceAI: false))", &problems)
        rig.model.isOn = false
        expect(rig.model.tiers(onDeviceAI: true).map(\.on) == [true, true, false],
               "with the signal off, what Daybook can see reads \(rig.model.tiers(onDeviceAI: true))", &problems)
        expect(SettingsPrivacyDisclosure.current.storageDetail.contains(
            "never reads page titles or page content"), "the privacy disclosure leaves out the site signal", &problems)
        expect(rig.model.state == .off && !rig.settings.isConsented, "switching off left consent stored", &problems)
        return problems
    }

    private static func gateOffStoresNothing() -> [String] {
        var problems: [String] = []
        let rig = Rig("gate-off", gateOn: false)
        defer { rig.close() }
        expect(rig.model.state == .unavailable, "without the gate the state is \(rig.model.state)", &problems)
        expect(!rig.model.canChangeSwitch, "without the gate the switch is enabled", &problems)
        expect(!rig.model.canChangeRemembers, "without the gate Remember sites is enabled", &problems)
        rig.model.isOn = true
        expect(rig.model.appChoice == nil, "without the gate the consent sheet opened", &problems)
        rig.model.changeApps()
        rig.model.confirmApps()
        rig.model.remembers = true
        expect(rig.storedKeys.isEmpty, "without the gate a toggle stored \(rig.storedKeys)", &problems)
        expect(rig.prompts == 0, "without the gate the permission prompt was asked for", &problems)

        // Consent stored while a gate line passed, then a macOS without one: it can still be withdrawn.
        let stored = Rig("gate-off-consented", gateOn: false)
        defer { stored.close() }
        stored.settings.turnOn(apps: ["com.apple.Safari"])
        expect(stored.model.canChangeSwitch && stored.model.isOn,
               "without the gate stored consent cannot be withdrawn", &problems)
        expect(!stored.model.canChangeApps, "without the gate Change Apps is offered", &problems)
        stored.model.isOn = false
        expect(!stored.settings.isConsented, "without the gate switching off kept consent", &problems)
        stored.model.isOn = true
        expect(stored.model.appChoice == nil && !stored.settings.isConsented && !stored.model.canChangeSwitch,
               "without the gate the signal could be switched on again", &problems)
        return problems
    }

    private static func turnOnNeedsAnApp() -> [String] {
        var problems: [String] = []
        let rig = Rig("turn-on")
        defer { rig.close() }
        rig.model.isOn = true
        guard let choice = rig.model.appChoice else { return ["switching on opened no consent sheet"] }
        expect(!rig.settings.isConsented, "opening the sheet stored consent", &problems)
        expect(choice.purpose == .turnOn, "switching on opened the sheet for \(choice.purpose)", &problems)
        expect(choice.candidates.map(\.bundleID) == ["com.apple.Safari", "com.google.Chrome", "com.example.reader"]
               && choice.candidates.map(\.ticked) == [true, true, false],
               "the sheet lists \(choice.candidates)", &problems)
        for app in choice.candidates where app.ticked { rig.model.setTicked(app.bundleID, false) }
        expect(!rig.model.canConfirm, "Turn On is enabled with no app ticked", &problems)
        rig.model.confirmApps()
        expect(!rig.settings.isConsented && rig.model.appChoice != nil, "Turn On worked with no app ticked", &problems)
        rig.model.setTicked("com.google.Chrome", true)
        expect(rig.model.canConfirm, "Turn On is disabled with an app ticked", &problems)
        rig.model.confirmApps()
        expect(rig.settings.isConsented && rig.settings.apps == ["com.google.Chrome"],
               "Turn On stored \(rig.settings.apps), consented \(rig.settings.isConsented)", &problems)
        expect(rig.model.appChoice == nil, "the sheet stayed open after Turn On", &problems)
        expect(rig.prompts == 1, "Turn On without trust prompted \(rig.prompts) times, not once", &problems)
        expect(rig.model.state == .awaitingPermission, "after Turn On the state is \(rig.model.state)", &problems)

        let trusted = Rig("turn-on-trusted")
        defer { trusted.close() }
        trusted.trusted = true
        trusted.model.isOn = true
        trusted.model.confirmApps()
        expect(trusted.prompts == 0, "Turn On with trust asked for permission again", &problems)
        expect(trusted.model.state == .on, "Turn On with trust left the state \(trusted.model.state)", &problems)

        let cancelled = Rig("turn-on-cancel")
        defer { cancelled.close() }
        cancelled.model.isOn = true
        cancelled.model.cancelAppChoice()
        expect(cancelled.model.appChoice == nil && cancelled.storedKeys.isEmpty && cancelled.prompts == 0,
               "Cancel stored \(cancelled.storedKeys) or prompted", &problems)
        return problems
    }

    private static func sheetShowsConsentText() -> [String] {
        MainActor.assumeIsolated {
            let rig = Rig("sheet")
            defer { rig.close() }
            rig.model.isOn = true
            var drawn = ""
            dump(SiteSignalConsentSheet(model: rig.model).body, to: &drawn)
            var problems: [String] = []
            expect(drawn.contains(SiteSignalConstants.consentText), "the sheet does not show the consent text", &problems)
            expect(drawn.contains("Turn on the site signal"), "the sheet is not titled \"Turn on the site signal\"",
                   &problems)
            return problems
        }
    }

    private static func turnOnAgainPreselects() -> [String] {
        var problems: [String] = []
        let rig = Rig("again")
        defer { rig.close() }
        rig.settings.turnOn(apps: ["com.example.reader"])
        rig.model.isOn = false
        rig.model.isOn = true
        let ticked = rig.model.appChoice?.candidates.filter(\.ticked).map(\.bundleID)
        expect(ticked == ["com.example.reader"], "turning on again ticked \(ticked ?? [])", &problems)
        rig.model.cancelAppChoice()
        rig.settings.turnOn(apps: ["com.apple.Safari"])
        rig.model.refreshTrust()
        rig.model.changeApps()
        expect(rig.model.appChoice?.purpose == .changeApps, "Change Apps opened no list", &problems)
        rig.model.setTicked("com.google.Chrome", true)
        rig.model.confirmApps()
        expect(Set(rig.settings.apps) == ["com.apple.Safari", "com.google.Chrome"] && rig.prompts == 0,
               "Change Apps stored \(rig.settings.apps) and prompted \(rig.prompts) times", &problems)
        return problems
    }

    private static func trustAndSettingsLink() -> [String] {
        var problems: [String] = []
        let rig = Rig("trust")
        defer { rig.close() }
        rig.settings.turnOn(apps: ["com.apple.Safari"])
        rig.model.refreshTrust()
        expect(rig.model.state == .awaitingPermission, "untrusted, the state is \(rig.model.state)", &problems)
        rig.trusted = true
        expect(rig.model.state == .awaitingPermission, "trust was read without being asked to", &problems)
        rig.model.refreshTrust()
        expect(rig.model.state == .on, "a re-read did not see the grant", &problems)
        rig.model.openAccessibilitySettings()
        expect(rig.opened.map(\.absoluteString)
               == ["x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"],
               "the settings link opened \(rig.opened)", &problems)
        return problems
    }

    private static func rememberedList() -> [String] {
        var problems: [String] = []
        let rig = Rig("remember")
        defer { rig.close() }
        expect(rig.model.canChangeRemembers && !rig.model.remembers, "Remember sites is not off and changeable",
               &problems)
        rig.model.remembers = true
        rig.model.newSite = "https://Docs.Example.com/guide"
        rig.model.newSiteKind = .documentation
        rig.model.addSite()
        expect(rig.model.rememberedSites.map(\.name) == ["docs.example.com"]
               && rig.model.rememberedSites.first?.kind == .documentation && rig.model.newSite.isEmpty
               && !rig.model.refused, "adding a site gave \(rig.model.rememberedSites)", &problems)
        rig.model.newSite = "login.example.com"
        rig.model.addSite()
        expect(rig.model.refused && rig.model.rememberedSites.count == 1, "a sign-in site was kept", &problems)
        expect(SiteSignalModel.refusal == "Daybook does not keep this site", "the refusal reads otherwise", &problems)
        rig.model.newSite = "login.example.co"
        expect(!rig.model.refused, "editing the field kept the refusal", &problems)
        rig.model.forget("docs.example.com")
        expect(rig.model.rememberedSites.isEmpty && rig.settings.rememberedSites.isEmpty,
               "Remove left \(rig.model.rememberedSites)", &problems)
        rig.model.newSite = "video.example.com"
        rig.model.addSite()
        rig.model.remembers = false
        rig.model.confirmForgetSites()
        expect(rig.settings.rememberedSites.isEmpty && rig.model.rememberedSites.isEmpty,
               "turning Remember sites off kept the list", &problems)
        return problems
    }

    private static func forgettingAsksFirst() -> [String] {
        var problems: [String] = []
        let rig = Rig("forget")
        defer { rig.close() }
        rig.model.remembers = true
        rig.model.remembers = false
        expect(!rig.model.remembers && rig.model.pendingForgetCount == nil,
               "an empty list asked before switching off", &problems)
        rig.model.remembers = true
        for site in ["docs.example.com", "video.example.com"] {
            rig.model.newSite = site
            rig.model.addSite()
        }
        rig.model.remembers = false
        expect(rig.model.pendingForgetCount == 2 && rig.model.remembers && rig.settings.rememberedSites.count == 2,
               "switching off deleted without asking", &problems)
        expect(SiteSignalModel.forgetTitle(2) == "Delete 2 Remembered Sites?"
               && SiteSignalModel.forgetTitle(1) == "Delete 1 Remembered Site?",
               "the question reads \(SiteSignalModel.forgetTitle(1)) / \(SiteSignalModel.forgetTitle(2))", &problems)
        rig.model.cancelForgetSites()
        expect(rig.model.pendingForgetCount == nil && rig.model.remembers && rig.settings.rememberedSites.count == 2,
               "Cancel did not keep the list and the switch on", &problems)
        rig.model.remembers = false
        rig.model.confirmForgetSites()
        expect(rig.model.pendingForgetCount == nil && !rig.model.remembers && rig.settings.rememberedSites.isEmpty,
               "Delete did not empty the list and switch off", &problems)
        rig.model.confirmForgetSites()
        expect(!rig.model.remembers, "Delete with nothing asked changed Remember sites", &problems)
        return problems
    }

    /// Refusal covers the sites Daybook knows (its table and rules), so the copy claims no more.
    private static func disclosureNamesWhatItKnows() -> [String] {
        var problems: [String] = []
        let wanted = "Daybook keeps the sites you give a kind, with that kind, on this Mac. Sites it knows as banking, "
            + "health, government, sign-in or adult are never kept. Turning this off deletes the list."
        expect(SiteSignalConstants.rememberDisclosure == wanted, "Remember sites says something else", &problems)
        expect(SettingsPrivacyDisclosure.current.storageDetail.contains(
            "never one Daybook knows as banking, health, government, sign-in or adult"),
               "the privacy disclosure does not limit its claim to the sites Daybook knows", &problems)
        return problems
    }
}
