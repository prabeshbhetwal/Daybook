import Foundation

/// An answer that arrives after the person changed something (Phase C review, ruling C24): a reply is used only
/// against the category list it was asked with, its name is checked against the categories as they stand when it
/// arrives, a switch turned meanwhile drops the write, a cached proposal never takes the id of a category the
/// person kept, and the site kind reaches the model only while the site signal's gate and consent allow it.
enum AILateAnswerChecks: CheckSuite {
    private typealias Rig = CategoryAssistantRig
    private typealias Spec = CategoryAssistantRig.Spec

    static let tests: [(String, () -> [String])] = [
        ("A late answer is dropped when the category list changed while the model thought", listChangedDrops),
        ("A name the person made or kept while the model thought is a pick of it, not a new label", nameMadeMeanwhile),
        ("An answer that finds assigning switched on meanwhile is not written", assigningSwitchedOnMeanwhile),
        ("A cached proposal whose id a kept category holds is never made a label again", keptIDIsNeverALabel),
        ("The site kind reaches the model only while the site signal's gate and consent allow it", siteKindNeedsConsent),
    ]

    /// Eighteen categories of the person's beside the built-ins: one made or kept after them is past the
    /// twentieth, so the list the model is asked with does not change.
    static let topics = Array("ABCDEFGHIJKLMNOPQR").map {
        WorkTypeDefinition(id: "custom.topic.\($0)", name: "Topic \($0)", symbolName: "star", hue: .blue)
    }

    private static func listChangedDrops() -> [String] {
        let hook = Rig.Hook()
        return Rig.withRig(reply: { _, _ in hook.run(); return Rig.answer("2") }) { rig, problems in
            // Meetings, the second category offered, is retired while the model thinks.
            hook.run = {
                var meetings = WorkTypeCatalog.shared.definition(for: .meetings)
                meetings.isRetired = true
                rig.f.persistence.workTypeDefinitions = [meetings]
            }
            rig.mode.assigns = true
            rig.ask()
            expect(rig.stored() == rig.record, "an answer to the old list was written: \(String(describing: rig.stored()))", &problems)
            expect(rig.reloaded().book.answers.isEmpty && rig.assistant.suggestions.isEmpty,
                   "an answer to the old list was cached or offered: \(rig.assistant.suggestions)", &problems)
        }
    }

    private static func nameMadeMeanwhile() -> [String] {
        let hook = Rig.Hook()
        let cinema = WorkTypeDefinition(id: "custom.selftest-cinema", name: "Cinema", symbolName: "film.fill", hue: .red)
        var films = cinema
        films.name = "Films"
        // Renamed: the same ids, so the list as asked is the list now, and "Films" is the person's.
        var problems = Rig.withRig(reply: { _, _ in hook.run(); return Rig.answer("new", "Films") },
                                   prepare: { $0.persistence.workTypeDefinitions = [cinema] }) { rig, problems in
            hook.run = { rig.f.persistence.workTypeDefinitions = [films] }
            rig.mode.assigns = true
            rig.ask()
            expect(rig.assistant.labels.book.labels.isEmpty,
                   "a second Films was made: \(rig.assistant.labels.book.labels.map(\.name))", &problems)
            expect(rig.stored()?.workType == films.workType,
                   "the session was not filed under the person's Films: \(String(describing: rig.stored()))", &problems)
        }
        // Made past the twentieth: not offered, so the name is none (C29), and never a second Films.
        let made = WorkTypeDefinition(id: "custom.selftest-films", name: "Films", symbolName: "film.fill", hue: .red)
        problems += Rig.withRig(reply: { _, _ in hook.run(); return Rig.answer("new", "Films") },
                                prepare: { $0.persistence.workTypeDefinitions = topics }) { rig, problems in
            hook.run = { rig.f.persistence.workTypeDefinitions = topics + [made] }
            rig.mode.assigns = true
            rig.ask()
            expect(rig.assistant.labels.book.labels.isEmpty,
                   "a second Films was made beside the person's: \(rig.assistant.labels.book.labels.map(\.name))", &problems)
            expect(rig.stored() == rig.record, "the session was filed under a second Films: \(String(describing: rig.stored()))", &problems)
        }
        return problems
    }

    private static func assigningSwitchedOnMeanwhile() -> [String] {
        let hook = Rig.Hook()
        return Rig.withRig(reply: { _, _ in hook.run(); return Rig.answer("2") }) { rig, problems in
            hook.run = { rig.mode.assigns = true }
            rig.ask()
            expect(rig.stored() == rig.record,
                   "an answer asked in shadow mode was written once assigning was on: \(String(describing: rig.stored()))", &problems)
        }
    }

    private static func keptIDIsNeverALabel() -> [String] {
        Rig.withRig([Spec(seed: 1), Spec(seed: 1)], reply: { _, _ in Rig.answer("new", "Films") },
                    prepare: { $0.persistence.workTypeDefinitions = topics }) { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            rig.mode.assigns = true
            rig.ask(0)
            guard let label = rig.assistant.labels.book.labels.first else { return problems.append("no label was made") }
            expect(rig.f.store.keepAILabel(label.id, as: "Movies"), "Rename was refused", &problems)
            // The same kind of session ends a day later, past the daily limit: the cached proposal still names
            // the id Movies now has.
            rig.f.clock.advance(AILabelConstants.labelWindow + 60)
            rig.ask(1)
            expect(!rig.assistant.labels.book.labels.contains { $0.id == label.id },
                   "the person's Movies was made an AI label again: \(rig.assistant.labels.book.labels.map(\.name))", &problems)
            expect(rig.f.persistence.workTypeDefinitions.first { $0.id == label.id }?.name == "Movies",
                   "the person's Movies changed", &problems)
        }
    }

    private static func siteKindNeedsConsent() -> [String] {
        func spec(_ seed: Int, _ kind: String) -> Spec {
            var spec = Spec(seed: seed)
            spec.fingerprint = ActivityFingerprint(shares: AIFixture.fingerprint(seed).shares, topApps: ["app.\(seed)", ""],
                                                   siteKind: kind)
            return spec
        }
        let specs = [spec(1, "video"), spec(2, "video"), spec(3, "video"), spec(4, "gossip")]
        return Rig.withRig(specs, reply: { _, _ in Rig.answer("none") }) { rig, problems in
            let suite = "fc-selftest-ai-site-\(UUID().uuidString)"
            guard let defaults = MemoryDefaults.suite(named: suite) else { return problems.append("no preferences suite") }
            defer { MemoryDefaults.remove(named: suite) }
            final class Gate { var open = true }
            let gate = Gate()
            rig.f.store.installSiteSignal(defaults: defaults, gateOn: { gate.open }, trusted: { true })
            @MainActor func told(_ index: Int) -> Bool {
                rig.ask(index)
                return rig.calls.questions.last?.text.contains("Site kind") == true
            }
            expect(!told(0), "the site kind reached the model without the person's consent", &problems)
            SiteSignalSettings(defaults: defaults).turnOn(apps: [SiteSignalChecks.chrome])
            gate.open = false
            expect(!told(1), "the site kind reached the model with the site signal's gate shut", &problems)
            gate.open = true
            expect(told(2), "the site kind did not reach the model with the gate open and consent given", &problems)
            expect(!told(3), "a site kind Daybook does not know reached the model", &problems)
            expect(rig.calls.questions.count == 4, "not every session was asked about: \(rig.calls.questions.count)", &problems)
        }
    }
}
