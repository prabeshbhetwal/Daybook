import Foundation

/// What the security review of the site signal found: a refused read stops the carry of a kind, a public
/// suffix is not a site, Save Apps never grants consent, a list Remember sites does not keep is not read,
/// and the consent text cannot change without its version. Fakes only.
enum SiteSignalSecurityChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A request says whether it asked", requestSaysWhetherItAsked),
        ("Once a read is refused no site kind is written any more", refusalStopsTheCarry),
        ("A public suffix cannot be remembered as a site", publicSuffixRefused),
        ("Save Apps never grants consent again", saveAppsNeedsConsent),
        ("A remembered list that Remember sites does not keep is not read", unkeptListIgnored),
        ("The consent text is the one its version names", consentTextPinned),
    ]

    private typealias Wiring = SiteSignalWiringChecks.Wiring
    private static let chrome = SiteSignalChecks.chrome

    /// Every consent text that shipped, by version. Change the text and `consentVersion` together, add the
    /// new pair here, and never edit an old one: a person agreed to that text.
    private static let shippedConsentTexts: [Int: String] = [
        1: "Daybook reads the address of the front browser tab, keeps only what kind of site it is, and discards the address immediately. It never reads page titles or page content.",
    ]

    private static func requestSaysWhetherItAsked() -> [String] {
        var problems: [String] = []
        let rig = SiteSignalChecks.Rig("asks-or-not")
        defer { rig.close() }
        func asks() -> Bool { rig.reader.request(app: chrome, pid: SiteSignalChecks.chromePID, at: SelfTest.base) }
        expect(asks(), "a request every gate allows asks", &problems)
        rig.gate = false
        expect(!asks(), "with the gate off it does not", &problems)
        rig.gate = true; rig.trust = false
        expect(!asks(), "without trust it does not", &problems)
        rig.trust = true; rig.settings.turnOff()
        expect(!asks(), "with the signal off it does not", &problems)
        rig.settings.turnOn(apps: [])
        expect(!asks(), "for a browser that is not ticked it does not", &problems)
        rig.settings.turnOn(apps: [chrome])
        rig.fake.answer = .timedOut
        expect(asks() && asks(), "two timeouts are asked for", &problems)
        expect(!asks(), "and the breaker then refuses", &problems)
        return problems
    }

    private static func refusalStopsTheCarry() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let refusals: [(String, (Wiring) -> Void)] = [
                ("the signal turned off", { $0.settings.turnOff() }),
                ("the browser unticked", { $0.settings.turnOn(apps: []) }),
                ("Accessibility removed", { $0.trust = false }),
                ("the gate off", { $0.gate = false }),
                ("the breaker tripped", { w in
                    // Two timeouts answered while an editor is in front are dropped by the recorder, so the
                    // kind noted after them is what the next edge must clear.
                    let now = w.r.clock.value
                    w.r.activate(SiteSignalWiringChecks.editor)
                    w.fake.answer = .timedOut
                    for _ in 0..<2 { w.r.evidence.siteReader?.request(app: chrome, pid: SiteSignalChecks.chromePID, at: now) }
                    w.r.activate(chrome)
                    w.r.store.noteSiteReading(SiteReading(kind: .video, app: chrome, requestedAt: now), at: now)
                }),
            ]
            for (name, refuse) in refusals {
                guard let w = SiteSignalWiringChecks.wired() else { return problems + ["could not create isolated preferences"] }
                defer { w.close() }
                w.fake.answer = SiteSignalWiringChecks.video
                w.r.run(3)
                w.r.activate(chrome)
                w.r.run(42)
                refuse(w)
                w.r.run(76)
                let beats = w.r.beats
                expect(beats.count == 4 && beats[1].slices.contains { $0.site == .video },
                       "\(name): the kind was carried until then, got \(beats.map(\.slices))", &problems)
                expect(beats.dropFirst(2).flatMap(\.slices).allSatisfy { $0.site == nil },
                       "\(name): a beat after it carries a site, got \(beats.dropFirst(2).map(\.slices))", &problems)
            }
            return problems
        }
    }

    private static func publicSuffixRefused() -> [String] {
        var problems: [String] = []
        let suite = "fc-selftest-site-suffix-" + UUID().uuidString
        guard let defaults = MemoryDefaults.suite(named: suite) else { return ["could not create isolated preferences"] }
        defer { MemoryDefaults.remove(named: suite) }
        let settings = SiteSignalSettings(defaults: defaults)
        settings.setRemembers(true)
        for name in ["co.uk", "com.au", "org.nz", "ne.jp", "or.jp", "ac.uk", "id.au", "go.jp", "edu.au", "com"] {
            expect(settings.remember(name, as: .shopping) == nil, "\(name) is not a site, yet it was remembered", &problems)
        }
        for name in ["example.com", "bbc.co.uk", "shop.com.au"] {
            expect(settings.remember(name, as: .shopping) == name, "\(name) is a site and is remembered", &problems)
        }
        return problems
    }

    private static func saveAppsNeedsConsent() -> [String] {
        var problems: [String] = []
        let rig = SiteSignalSurfaceChecks.Rig("save-apps-consent")
        defer { rig.close() }
        rig.settings.turnOn(apps: ["com.apple.Safari"])
        rig.model.changeApps()
        rig.model.setTicked(chrome, true)
        rig.model.confirmApps()
        expect(rig.settings.isConsented && rig.settings.apps.contains(chrome), "with consent stored Save Apps stores the apps", &problems)
        rig.model.changeApps()
        rig.settings.turnOff()
        rig.model.setTicked("com.apple.Safari", false)
        rig.model.confirmApps()
        expect(!rig.settings.isConsented, "consent withdrawn while the sheet was open is not given again", &problems)
        expect(rig.settings.apps.contains("com.apple.Safari"), "and Save Apps stored nothing, got \(rig.settings.apps)", &problems)
        return problems
    }

    private static func unkeptListIgnored() -> [String] {
        var problems: [String] = []
        let rig = SiteSignalChecks.Rig("unkept-list")
        defer { rig.close() }
        // Written by hand: Remember sites is off, so nothing here was ever kept.
        rig.defaults.set(["example.org": SiteKind.shopping.rawValue], forKey: SiteSignalSettings.sitesKey)
        rig.fake.answer = .address("https://www.example.org/")
        rig.request()
        expect(rig.delivered.last?.kind == nil, "a list Remember sites does not keep gave \(String(describing: rig.delivered.last?.kind))", &problems)
        rig.settings.setRemembers(true)
        rig.request(at: 1)
        expect(rig.delivered.last?.kind == .shopping, "and a kept one is read, got \(String(describing: rig.delivered.last?.kind))", &problems)
        return problems
    }

    private static func consentTextPinned() -> [String] {
        var problems: [String] = []
        expect(shippedConsentTexts[SiteSignalConstants.consentVersion] == SiteSignalConstants.consentText,
               "the consent text no longer matches version \(SiteSignalConstants.consentVersion): change the text and consentVersion together, so everyone is asked again, and add the new pair here", &problems)
        return problems
    }
}
