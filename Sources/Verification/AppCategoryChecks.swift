import Combine
import Foundation

/// App categories as the story shows and corrects them: grouping and the
/// summary line, where a category came from, the plain names, and a
/// correction reaching activity totals and coming back out with Undo.
enum AppCategoryChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A card groups apps by category, largest first, with one Everything else last", groupsFoldIntoOneTail),
        ("The category summary says Mostly only past half, and names a pair only past 80%", summaryBoundaries),
        ("An app's category source follows the same precedence as its category", sourcePrecedence),
        ("Plain category names leave stored raw values untouched", namesKeepRawValues),
        ("Changing an app's category moves its time in activity totals, and Undo moves it back", correctionReachesTotals),
        ("An app's category matches its bundle identifier in any letter case, and one app keeps one choice",
         bundleCaseMatches),
        ("An old session whose detail has expired follows a category changed since its summary was kept",
         staleSummaryFollowsCorrection),
        ("An open Settings list redraws when a card changes an app's category", settingsFollowsCards),
    ]

    private static func settingsFollowsCards() -> [String] {
        var problems: [String] = []
        let suite = "fc-selftest-app-category-settings-\(UUID().uuidString)"
        guard let defaults = MemoryDefaults.suite(named: suite) else { return ["could not create isolated defaults"] }
        defer { MemoryDefaults.remove(named: suite) }
        let model = SettingsModel(store: PersistenceStore(defaults: defaults), isTrackingEnabled: false,
                                  onChange: {}, onTrackingChanged: { _ in })
        var fired = 0
        let watch = model.objectWillChange.sink { fired += 1 }
        NotificationCenter.default.post(name: SessionStore.appPurposesDidChange, object: nil)
        watch.cancel()
        expect(fired > 0, "Settings did not hear the card's change", &problems)
        return problems
    }

    private static func bundleCaseMatches() -> [String] {
        var problems: [String] = []
        // Settings lists apps lowercased; recorded use keeps the app's own case.
        let saved = PurposeMap.settingOverride(.design, for: "com.apple.terminal", in: ["com.apple.Terminal": "media"])
        expect(saved == ["com.apple.terminal": "design"], "one app holds one choice, got \(saved)", &problems)
        let recorded = PurposeMap.purpose(for: "com.apple.Terminal", activity: .active, overrides: saved)
        expect(recorded == .design, "recorded use follows a choice saved lowercased, got \(recorded)", &problems)
        let listed = PurposeMap.source(for: "com.apple.terminal", overrides: [:])
        expect(listed == .builtIn, "a lowercased identifier still finds its built-in rule, got \(listed)", &problems)
        expect(PurposeMap.isAmbiguous("company.thebrowser.DIA"), "a browser is a browser in any case", &problems)
        let cleared = PurposeMap.settingOverride(nil, for: "com.apple.Terminal", in: saved)
        expect(cleared == ["com.apple.terminal": ""], "clearing leaves one empty mark, got \(cleared)", &problems)
        expect(PurposeMap.purpose(for: "com.apple.Terminal", activity: .active, overrides: cleared) == .coding,
               "a cleared choice reads as Daybook's own", &problems)
        expect(PurposeMap.source(for: "com.apple.Terminal", overrides: cleared) == .builtIn,
               "a cleared choice is not the person's", &problems)
        return problems
    }

    private static func staleSummaryFollowsCorrection() -> [String] {
        var spec = CategoryAssistantRig.Spec()
        spec.credited = [.coding: 1_800]
        let start = SelfTest.base
        let usage = [AppUsageSession(bundleID: "com.apple.Terminal", appName: "Terminal", start: start,
                                     end: start.addingTimeInterval(1_800), endReason: .appSwitch)]
        // The rig keeps a summary for the session and records no beats, as for a session past their retention.
        return CategoryAssistantRig.withRig([spec], usage: usage) { rig, problems in
            let before = rig.f.store.sessionActivity(for: rig.session())?.credited ?? [:]
            expect((before["coding"] ?? 0) > 1_700, "the kept summary reads coding first, got \(before)", &problems)
            rig.f.store.setAppPurpose(.design, for: "com.apple.Terminal")
            let after = rig.f.store.sessionActivity(for: rig.session())?.credited ?? [:]
            expect((after["design"] ?? 0) > 1_700 && (after["coding"] ?? 0) < 1,
                   "Terminal's half hour moved to design, got \(after)", &problems)
            // Back to Daybook's choice: the summary made under Design is stale too.
            rig.f.store.setAppPurpose(nil, for: "com.apple.Terminal")
            let back = rig.f.store.sessionActivity(for: rig.session())?.credited ?? [:]
            expect((back["coding"] ?? 0) > 1_700, "Terminal's half hour is coding again, got \(back)", &problems)
        } + untouchedSummaryKeepsCredit()
    }

    /// A browser-only session keeps its kept research credit when an app it never used changes category:
    /// rebuilt from app use alone, a browser would earn nothing.
    private static func untouchedSummaryKeepsCredit() -> [String] {
        var spec = CategoryAssistantRig.Spec()
        spec.credited = [.research: 1_800]
        let start = SelfTest.base
        let usage = [AppUsageSession(bundleID: "com.apple.Safari", appName: "Safari", start: start,
                                     end: start.addingTimeInterval(1_800), endReason: .appSwitch)]
        return CategoryAssistantRig.withRig([spec], usage: usage) { rig, problems in
            rig.f.store.setAppPurpose(.design, for: "com.apple.Terminal")
            let after = rig.f.store.sessionActivity(for: rig.session())?.credited ?? [:]
            expect((after["research"] ?? 0) > 1_700, "the Safari session kept its research, got \(after)", &problems)
        }
    }

    private static func rank(_ id: String, _ minutes: Double) -> AppRank {
        AppRank(bundleID: id, appName: id, total: minutes * 60, share: 0, longest: 0)
    }

    private static let purposes: [String: AppPurpose] = [
        "c": .coding, "w": .writingAI, "d": .design, "m": .communication, "r": .research, "u": .utility
    ]

    private static func groupsFoldIntoOneTail() -> [String] {
        var problems: [String] = []
        let purpose: (String) -> AppPurpose = { purposes[String($0.prefix(1))] ?? .utility }
        let few = AppPurposeGroups.groups([rank("u1", 50), rank("w1", 10), rank("w2", 30), rank("c1", 20)],
                                          purpose: purpose)
        expect(few.map(\.purpose) == [.writingAI, .coding, .utility],
               "utility goes last even when largest, got \(few.map(\.purpose))", &problems)
        expect(few.first?.apps.map(\.bundleID) == ["w2", "w1"],
               "apps sort largest first, got \(few.first?.apps.map(\.bundleID) ?? [])", &problems)
        let many = AppPurposeGroups.groups([rank("c1", 40), rank("w1", 30), rank("d1", 20), rank("m1", 10),
                                            rank("r1", 5), rank("u1", 1)], purpose: purpose)
        expect(many.count == AppPurposeGroups.maximumGroups,
               "groups stop at \(AppPurposeGroups.maximumGroups), got \(many.count)", &problems)
        expect(many.filter { $0.purpose == .utility }.count == 1 && many.last?.purpose == .utility,
               "one Everything else, last, got \(many.map(\.purpose))", &problems)
        expect(Set(many.last?.apps.map(\.bundleID) ?? []) == ["m1", "r1", "u1"],
               "the smallest groups fold into Everything else, got \(many.last?.apps.map(\.bundleID) ?? [])",
               &problems)
        let fourNamed = AppPurposeGroups.groups([rank("c1", 4), rank("w1", 3), rank("d1", 2), rank("m1", 1)],
                                                purpose: purpose)
        expect(fourNamed.map(\.purpose) == [.coding, .writingAI, .design, .communication],
               "four named groups and no tail stay as they are, got \(fourNamed.map(\.purpose))", &problems)
        return problems
    }

    private static func summaryBoundaries() -> [String] {
        var problems: [String] = []
        func summary(_ apps: [AppRank]) -> String? {
            AppPurposeGroups.summary(AppPurposeGroups.groups(apps) { purposes[String($0.prefix(1))] ?? .utility })
        }
        let half = summary([rank("w", 30), rank("c", 30)])
        expect(half == "Coding and Writing & AI", "an even split names both, got \(half ?? "nil")", &problems)
        let most = summary([rank("w", 31), rank("c", 29)])
        expect(most == "Mostly Writing & AI", "past half reads Mostly, got \(most ?? "nil")", &problems)
        let mix = summary([rank("w", 40), rank("c", 35), rank("d", 25)])
        expect(mix == "A mix of 3 kinds of work", "a three-way split reads as a mix, got \(mix ?? "nil")", &problems)
        let one = summary([rank("c", 10)])
        expect(one == "All Coding", "one category reads All, got \(one ?? "nil")", &problems)
        let tail = summary([rank("u", 50), rank("c", 10)])
        expect(tail == nil, "nothing is said when Everything else leads, got \(tail ?? "nil")", &problems)
        return problems
    }

    private static func sourcePrecedence() -> [String] {
        var problems: [String] = []
        let overrides = ["com.apple.Terminal": "design"]
        let cases: [(String, PurposeSource)] = [
            ("com.apple.Terminal", .yours), ("com.apple.dt.Xcode", .builtIn),
            ("company.thebrowser.dia", .behaviour), ("com.example.unknown", .unknown)
        ]
        for (id, expected) in cases {
            let got = PurposeMap.source(for: id, overrides: overrides)
            expect(got == expected, "\(id) comes from \(expected), got \(got)", &problems)
        }
        expect(PurposeMap.shownPurpose(for: "com.apple.Terminal", overrides: overrides) == .design,
               "an override is the shown category", &problems)
        expect(PurposeMap.shownPurpose(for: "company.thebrowser.dia", overrides: [:]) == .writingAI,
               "a browser shows what it counts as in active use", &problems)
        return problems
    }

    private static func namesKeepRawValues() -> [String] {
        var problems: [String] = []
        let names = AppPurpose.allCases.map(\.displayName)
        expect(names == ["Coding", "Writing & AI", "Design", "Chat & email", "Browsing & research",
                         "Entertainment", "Everything else"], "the plain names, got \(names)", &problems)
        expect(AppPurpose.allCases.map(\.rawValue)
               == ["coding", "writingAI", "design", "communication", "research", "media", "utility"],
               "raw values are what stored overrides and goals decode", &problems)
        expect(Set(AppPurpose.allCases.map(\.hue)).count == AppPurpose.allCases.count,
               "every category has its own colour", &problems)
        return problems
    }

    private static func correctionReachesTotals() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let calendar = Calendar.current
            let start = SelfTest.anchoredNow()
            let clock = TestClock(start)
            let suite = "fc-selftest-app-category-\(UUID().uuidString)"
            guard let defaults = MemoryDefaults.suite(named: suite) else { return ["could not create isolated defaults"] }
            defer { MemoryDefaults.remove(named: suite) }
            let persistence = PersistenceStore(defaults: defaults)
            persistence.removeAll()
            let directory = SelfTest.scratchDirectory()
            let engine = SessionEngine(store: persistence,
                                       archive: SessionArchive(directory: directory, now: { clock.value }),
                                       ownBundleID: "com.example.self", schedulesDwell: false, now: { clock.value })
            let usage = AppUsageArchive(directory: directory, now: { clock.value })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "com.example.self",
                                          idle: .disabled, now: { clock.value })
            let store = SessionStore(engine: engine, schedulesTicker: false, now: { clock.value })
            store.attach(tracker: tracker, usage: usage)

            engine.start(workType: .deepWork, intent: "Writing")
            usage.record(AppUsageSession(bundleID: "com.anthropic.claudefordesktop", appName: "Claude", start: start,
                                         end: start.addingTimeInterval(30 * 60), endReason: .appSwitch))
            clock.advance(30 * 60)
            guard calendar.isDate(start, inSameDayAs: clock.value) else { return ["the fixture crossed midnight"] }
            let before = store.focusByPurpose(on: start)["coding"] ?? 0

            let previous = store.setAppPurpose(.coding, for: "com.anthropic.claudefordesktop")
            expect(previous == nil, "no earlier choice to undo, got \(String(describing: previous))", &problems)
            expect(store.appPurpose("com.anthropic.claudefordesktop") == .coding, "Claude now shows as Coding", &problems)
            let after = store.focusByPurpose(on: start)["coding"] ?? 0
            expect(after - before > 25 * 60, "Claude's half hour now counts as coding, got \(after - before)s", &problems)

            store.setAppPurpose(previous, for: "com.anthropic.claudefordesktop")
            let undone = store.focusByPurpose(on: start)["coding"] ?? 0
            expect(abs(undone - before) < 1, "Undo returns coding to \(before)s, got \(undone)s", &problems)
            expect(PurposeMap.override(for: "com.anthropic.claudefordesktop", in: persistence.purposeOverrides) == nil,
                   "Undo leaves no choice behind, got \(persistence.purposeOverrides)", &problems)
            return problems
        }
    }
}
