import Foundation

/// The site signal reads nothing without the gate, consent, trust and a confirmed
/// app, and a read gives only a kind. Fakes only: nothing here touches Accessibility.
enum SiteSignalChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Off by default, and consent is explicit", offByDefault),
        ("Nothing is read unless every gate allows it", everyGateMustAllow),
        ("A read gives only a kind", readGivesOnlyAKind),
        ("A browser that hangs is skipped after two timeouts", hangingBrowserSkipped),
        ("A slow read never holds up the caller", slowReadNeverBlocks),
        ("Turning the signal off drops a read in flight", offDropsReadInFlight),
        ("Only the newest request is read", onlyNewestRead),
        ("A changed consent text asks again", changedConsentAsksAgain),
        ("Remember sites keeps only what the person names, and forgets on off", rememberSites),
        ("The app list ticks known browsers only", appListTicksBrowsers),
    ]

    static let chrome = "com.google.Chrome"
    static let safari = "com.apple.Safari"
    static let chromePID: pid_t = 4242

    /// Answers every read with `answer` and notes each pid it was asked about.
    final class FakeReader: SiteAddressReading {
        var asked: [pid_t] = []
        var answer: SiteAddressRead = .failed
        func read(pid: pid_t, timeout: TimeInterval) -> SiteAddressRead {
            asked.append(pid)
            return answer
        }
    }

    /// A reader with every gate open for Chrome. `deferred` non-nil queues the
    /// worker's jobs, and `held` non-nil the deliveries, instead of running them inline.
    final class Rig {
        let suite: String
        let defaults: UserDefaults
        let settings: SiteSignalSettings
        let fake = FakeReader()
        var gate = true, trust = true
        var frontApps: [pid_t: String] = [chromePID: chrome]
        var deferred: [() -> Void]?
        var held: [() -> Void]?
        var delivered: [SiteReading] = []
        lazy var reader = SiteSignalReader(
            settings: settings, reader: fake,
            gateOn: { [unowned self] in self.gate }, trusted: { [unowned self] in self.trust },
            bundleID: { [unowned self] in self.frontApps[$0] },
            run: { [unowned self] work in
                if self.deferred != nil { self.deferred?.append(work) } else { work() }
            },
            deliver: { [unowned self] work in
                if self.held != nil { self.held?.append(work) } else { work() }
            },
            onReading: { [unowned self] in self.delivered.append($0) })

        init(_ name: String, consented: Bool = true) {
            suite = "fc-selftest-site-" + name
            MemoryDefaults.remove(named: suite)
            defaults = MemoryDefaults.suite(named: suite)!
            settings = SiteSignalSettings(defaults: defaults)
            if consented { settings.turnOn(apps: [chrome]) }
        }
        func close() { MemoryDefaults.remove(named: suite) }
        func request(at seconds: TimeInterval = 0) {
            reader.request(app: chrome, pid: chromePID, at: SelfTest.base.addingTimeInterval(seconds))
        }
        func runDeferred() {
            let work = deferred ?? []
            deferred = []
            work.forEach { $0() }
        }
    }

    private static func offByDefault() -> [String] {
        var problems: [String] = []
        let rig = Rig("off-by-default", consented: false)
        defer { rig.close() }
        expect(!rig.settings.isConsented, "a fresh suite is consented", &problems)
        expect(!rig.settings.remembers, "a fresh suite remembers sites", &problems)
        expect(rig.settings.apps.isEmpty, "a fresh suite lists apps", &problems)
        let cases: [(Bool, Bool, Bool, SiteSignalState)] = [
            (false, true, true, .off), (true, false, true, .unavailable),
            (true, true, false, .awaitingPermission), (true, true, true, .on),
            (false, false, true, .unavailable),
        ]
        for (consented, gateOn, trusted, wanted) in cases {
            let state = SiteSignalSettings.state(consented: consented, gateOn: gateOn, trusted: trusted)
            expect(state == wanted, "state(\(consented), \(gateOn), \(trusted)) is \(state), not \(wanted)", &problems)
        }
        return problems
    }

    private static func everyGateMustAllow() -> [String] {
        var problems: [String] = []
        let open = Rig("gates-open")
        defer { open.close() }
        open.fake.answer = .address("https://www.youtube.com/watch?v=x")
        open.request()
        expect(open.fake.asked == [chromePID] && open.delivered.count == 1,
               "with every gate open the rig reads once and delivers once", &problems)

        let blockers: [(String, (Rig) -> Void)] = [
            ("gate off", { $0.gate = false }),
            ("not consented", { $0.settings.turnOff() }),
            ("not trusted", { $0.trust = false }),
            ("app not in the list", { $0.settings.turnOn(apps: [safari]) }),
            ("pid is another app", { $0.frontApps[chromePID] = "com.apple.TextEdit" }),
        ]
        for (name, block) in blockers {
            let rig = Rig("gate-" + name.replacingOccurrences(of: " ", with: "-"))
            defer { rig.close() }
            rig.fake.answer = .address("https://www.youtube.com/watch?v=x")
            block(rig)
            rig.request()
            expect(rig.fake.asked.isEmpty, "\(name): the reader was asked about \(rig.fake.asked)", &problems)
            expect(rig.delivered.isEmpty, "\(name): \(rig.delivered.count) readings delivered", &problems)
        }
        return problems
    }

    private static func readGivesOnlyAKind() -> [String] {
        var problems: [String] = []
        let rig = Rig("only-a-kind")
        defer { rig.close() }
        rig.fake.answer = .address("https://www.youtube.com/watch?v=x")
        rig.request()
        expect(rig.delivered == [SiteReading(kind: .video, app: chrome, requestedAt: SelfTest.base)],
               "a video address gave \(rig.delivered)", &problems)
        let noKind: [SiteAddressRead] = [
            .failed, .address("about:blank"), .address("https://example.com"),
            .address("https://accounts.google.com/x"),
        ]
        for answer in noKind {
            rig.delivered = []
            rig.fake.answer = answer
            rig.request(at: 30)
            expect(rig.delivered == [SiteReading(kind: nil, app: chrome, requestedAt: SelfTest.base.addingTimeInterval(30))],
                   "\(answer) gave \(rig.delivered.map { String(describing: $0.kind) })", &problems)
        }
        return problems
    }

    private static func hangingBrowserSkipped() -> [String] {
        var problems: [String] = []
        let rig = Rig("hanging")
        defer { rig.close() }
        rig.fake.answer = .timedOut
        rig.request(at: 0)
        rig.request(at: 30)
        expect(rig.delivered.map(\.kind) == [nil, nil], "a timeout delivers no kind: \(rig.delivered)", &problems)
        rig.request(at: 60)
        expect(rig.fake.asked.count == 2, "after two timeouts the browser was asked \(rig.fake.asked.count) times", &problems)
        rig.reader.reset()
        rig.request(at: 90)
        expect(rig.fake.asked.count == 3, "after reset the browser was not asked again", &problems)
        return problems
    }

    private static func slowReadNeverBlocks() -> [String] {
        var problems: [String] = []
        let rig = Rig("slow-read")
        defer { rig.close() }
        rig.deferred = []
        rig.fake.answer = .address("https://www.youtube.com/")
        rig.request()
        expect(rig.fake.asked.isEmpty && rig.delivered.isEmpty, "request read or delivered before the worker ran", &problems)
        rig.runDeferred()
        expect(rig.fake.asked.count == 1 && rig.delivered.map(\.kind) == [.video],
               "the worker's read was not delivered: \(rig.delivered)", &problems)
        return problems
    }

    private static func offDropsReadInFlight() -> [String] {
        var problems: [String] = []
        let interruptions: [(String, (Rig) -> Void)] = [
            ("turned off", { $0.settings.turnOff() }),
            ("recording ended", { $0.reader.reset() }),
            ("trust withdrawn", { $0.trust = false }),
            ("app removed from the list", { $0.settings.turnOn(apps: [safari]) }),
            ("gate closed", { $0.gate = false }),
        ]
        for (name, interrupt) in interruptions {
            let rig = Rig("in-flight-" + name.replacingOccurrences(of: " ", with: "-"))
            defer { rig.close() }
            rig.deferred = []
            rig.fake.answer = .address("https://www.youtube.com/")
            rig.request()
            interrupt(rig)
            rig.runDeferred()
            expect(rig.fake.asked.isEmpty, "\(name): a queued read still asked the browser", &problems)
            expect(rig.delivered.isEmpty, "\(name): a read in flight was still delivered", &problems)
        }
        return problems
    }

    private static func onlyNewestRead() -> [String] {
        var problems: [String] = []
        let rig = Rig("newest")
        defer { rig.close() }
        rig.deferred = []
        rig.fake.answer = .address("https://www.youtube.com/")
        rig.request(at: 0)
        rig.request(at: 1)
        rig.request(at: 2)
        rig.runDeferred()
        expect(rig.fake.asked.count == 1, "three pending requests made \(rig.fake.asked.count) reads", &problems)
        expect(rig.delivered.map(\.requestedAt) == [SelfTest.base.addingTimeInterval(2)],
               "delivered \(rig.delivered.map(\.requestedAt)), not the last request only", &problems)
        return problems
    }

    private static func changedConsentAsksAgain() -> [String] {
        var problems: [String] = []
        let rig = Rig("consent-version", consented: false)
        defer { rig.close() }
        let malformed: [(String, Any)] = [("version 0", 0), ("true", true), ("\"1\"", "1"), ("1.9", 1.9)]
        for (name, value) in malformed {
            rig.defaults.set(value, forKey: "fc.siteSignal.consent")
            expect(!rig.settings.isConsented, "a stored consent of \(name) still counts", &problems)
        }
        rig.settings.turnOn(apps: [chrome])
        expect(rig.defaults.integer(forKey: "fc.siteSignal.consent") == SiteSignalConstants.consentVersion
               && rig.settings.isConsented, "turning on did not store the current consent version", &problems)
        rig.settings.turnOff()
        expect(!rig.settings.isConsented && rig.settings.apps == [chrome],
               "turning off kept consent or lost the confirmed apps", &problems)
        return problems
    }

    private static func rememberSites() -> [String] {
        var problems: [String] = []
        let rig = Rig("remember")
        defer { rig.close() }
        let settings = rig.settings
        expect(settings.remember("example.com", as: .documentation) == nil && settings.rememberedSites.isEmpty,
               "a site was kept with remembering off", &problems)
        settings.setRemembers(true)
        expect(settings.remember("example.com", as: .documentation) == "example.com"
               && settings.rememberedSites == ["example.com": .documentation],
               "example.com was not kept: \(settings.rememberedSites)", &problems)
        expect(settings.remember("paypal.com", as: .shopping) == nil, "a banking site was kept", &problems)
        expect(settings.remember("not a site", as: .shopping) == nil, "an invalid name was kept", &problems)
        expect(settings.rememberedSites.count == 1, "refused names were stored: \(settings.rememberedSites)", &problems)

        settings.remember("youtube.com", as: .documentation)
        rig.fake.answer = .address("https://www.youtube.com/watch?v=x")
        rig.request()
        expect(rig.delivered.map(\.kind) == [.documentation], "the remembered kind lost: \(rig.delivered)", &problems)

        let stored = SiteSignalSettings.keys.filter { rig.defaults.object(forKey: $0) != nil }
        let backedUp = PersistenceStore(defaults: rig.defaults).backupSnapshot.keys.filter { $0.hasPrefix("fc.siteSignal.") }
        expect(stored.count == 4 && backedUp.isEmpty, "stored \(stored), backed up \(backedUp.sorted())", &problems)
        settings.forget("youtube.com")
        expect(settings.rememberedSites == ["example.com": .documentation], "forget left youtube.com", &problems)
        settings.setRemembers(false)
        expect(settings.rememberedSites.isEmpty && rig.defaults.object(forKey: "fc.siteSignal.sites") == nil,
               "turning remembering off kept the list", &problems)
        settings.setRemembers(true)
        settings.remember("example.com", as: .documentation)
        PersistenceStore(defaults: rig.defaults).removeAll()
        expect(!settings.isConsented && settings.apps.isEmpty && !settings.remembers && settings.rememberedSites.isEmpty,
               "removeAll left the site signal's keys", &problems)
        return problems
    }

    private static func appListTicksBrowsers() -> [String] {
        var problems: [String] = []
        let candidates = SiteSignalSettings.candidates([
            ("com.apple.TextEdit", "TextEdit"), (safari, "Safari"), (FocusConstants.bundleIdentifier, "Daybook"),
        ])
        let shown = candidates.map { "\($0.bundleID) \($0.ticked)" }
        expect(shown == ["\(safari) true", "com.apple.TextEdit false"], "candidates were \(shown)", &problems)
        return problems
    }
}
