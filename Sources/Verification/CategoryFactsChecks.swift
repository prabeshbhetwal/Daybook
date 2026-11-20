import Foundation

/// What the model is told and what it may answer (Phase C, rulings C5, C6, C27): the question holds the
/// session's activities, depth, app names and the person's category names and nothing that could identify
/// the work, at most 20 categories are offered, and a proposal that names a category that exists but was not
/// offered is none rather than a second category of that name.
enum CategoryFactsChecks: CheckSuite {
    private typealias Rig = CategoryAssistantRig
    private typealias Spec = CategoryAssistantRig.Spec

    static let tests: [(String, () -> [String])] = [
        ("The question holds no session name, note, window title, address or bundle identifier", questionHoldsOnlyTheFacts),
        ("At most 20 categories are offered, and a proposal naming one beyond them is none", offersTwenty),
        ("A proposal named Break, Unsorted or after a retired category is none, however the person set them", unofferedNamesAreNone),
    ]

    private static func questionHoldsOnlyTheFacts() -> [String] {
        var spec = Spec()
        spec.name = "Quokka secret name"
        // Apps by bundle identifier: one the usage record names, one it has never heard of, and one it holds
        // under its bundle identifier (the tracker's fallback for an app with no localised name, C27).
        spec.fingerprint = ActivityFingerprint(shares: [2, 0, 0, 0, 0, 3, 0],
                                               topApps: ["com.example.nameless", "com.example.wombat", "com.example.quokkamystery"],
                                               siteKind: "video")
        // Media leads by a hair, so the evidence is unclear and the model is asked; research is under half a minute.
        spec.credited = [.media: 1_100, .coding: 900, .research: 12]
        let usage = [NameSuggestionStoreChecks.app("Wombat", SelfTest.base, 600),
                     AppUsageSession(bundleID: "com.example.nameless", appName: "com.example.nameless",
                                     start: SelfTest.base, end: SelfTest.base.addingTimeInterval(600))]
        return Rig.withRig([spec], usage: usage, reply: { _, _ in Rig.answer("none") }) { rig, problems in
            _ = rig.f.metadata.saveNote("Quokka note text", for: rig.record.id)
            // An address the person told Daybook the kind of: nothing the question is built from reads it.
            let suite = "fc-selftest-facts-\(UUID().uuidString)"
            guard let defaults = MemoryDefaults.suite(named: suite) else { return problems.append("no preferences suite") }
            defer { MemoryDefaults.remove(named: suite) }
            let sites = SiteSignalSettings(defaults: defaults)
            sites.setRemembers(true)
            _ = sites.remember("quokka-bank.example", as: .video)
            // The site kind is told only while the signal's gate is open and the person agreed to it (C5).
            sites.turnOn(apps: [SiteSignalChecks.chrome])
            rig.f.store.installSiteSignal(defaults: defaults, gateOn: { true }, trusted: { true })
            rig.ask()
            guard let text = rig.calls.questions.first?.text else { return problems.append("the session was not asked about") }
            expect(!text.localizedCaseInsensitiveContains("quokka") && !text.contains("com.example"),
                   "something that identifies the work or an app identifier reached the model: \(text)", &problems)
            expect(text.contains("- Media: 18 min") && text.contains("- Coding: 15 min") && !text.contains("Research"),
                   "the activities were not in whole minutes from the shape, the smallest dropped: \(text)", &problems)
            expect(text.contains("Depth: deep") && text.contains("Apps: Wombat") && text.contains("Site kind: video"),
                   "the depth, the app's display name or the site kind was missing: \(text)", &problems)
            expect(text.contains("1. Deep work") && text.contains("2. Meetings"), "the categories were not numbered: \(text)", &problems)
        }
    }

    private static func offersTwenty() -> [String] {
        let letters = Array("ABCDEFGHIJKLMNOPQR")
        return Rig.withRig([Spec(seed: 1), Spec(seed: 2)], reply: { count, _ in
            // The 21st category, by name, and then by number.
            count == 1 ? Rig.answer("new", "Topic Q") : Rig.answer("21")
        }, prepare: { f in
            f.persistence.workTypeDefinitions = letters.map {
                WorkTypeDefinition(id: "custom.topic.\($0)", name: "Topic \($0)", symbolName: "star", hue: .blue)
            }
        }) { rig, problems in
            rig.mode.assigns = true
            rig.ask(0)
            let text = rig.calls.questions.first?.text ?? ""
            expect(text.contains("20. Topic P") && !text.contains("21. "),
                   "the list was not cut at 20 categories: \(text)", &problems)
            expect(rig.assistant.labels.book.labels.isEmpty && rig.stored(0) == rig.records[0],
                   "a category beyond the 20th was made again as a label", &problems)
            rig.ask(1)
            expect(rig.stored(1) == rig.records[1], "a number past the list was written: \(String(describing: rig.stored(1)))", &problems)
        }
    }

    private static func unofferedNamesAreNone() -> [String] {
        let proposals = [1: "Break", 2: "Unsorted", 3: "Poetry"]
        return Rig.withRig([Spec(seed: 1), Spec(seed: 2), Spec(seed: 3)],
                           reply: { count, _ in Rig.answer("new", proposals[count] ?? "") },
                           prepare: { f in
            f.persistence.workTypeDefinitions = [
                WorkTypeDefinition(id: "custom.poetry", name: "Poetry", symbolName: "star", hue: .blue, isRetired: true),
            ]
        }) { rig, problems in
            rig.mode.assigns = true
            for index in 0..<3 { rig.ask(index) }
            expect(rig.calls.questions.count == 3, "not every proposal was put: \(rig.calls.questions.count)", &problems)
            expect(rig.assistant.labels.book.labels.isEmpty, "a label was made named after a category that exists: \(rig.assistant.labels.book.labels)", &problems)
            expect((0..<3).allSatisfy { rig.stored($0) == rig.records[$0] }, "a record was written for such a proposal", &problems)
            expect(rig.assistant.labels.book.answers.allSatisfy { $0.answer == .none }, "such a proposal was not none: \(rig.assistant.labels.book.answers)", &problems)
        }
    }
}
