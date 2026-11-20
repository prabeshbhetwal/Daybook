import Foundation

/// Phase C, fix round 5: a proposal whose id the person's categories hold is offered as that category, a Use whose
/// filing does not land takes back the category it kept (or, the label file refusing, leaves the label kept), the site kind needs the site signal on now, an Undo leaves
/// a label archived when a category of the person's has its name, the launch counts a crashed Keep's records, and
/// confirming the category a record never said the source of makes it the person's.
enum AIFinalRoundChecks: CheckSuite {
    private typealias Rig = CategoryAssistantRig
    private typealias Spec = CategoryAssistantRig.Spec

    static let tests: [(String, () -> [String])] = [
        ("A twin session is offered the category another session's Use kept from the same proposal", twinOffersTheKeptCategory),
        ("A Use whose filing is refused keeps no new category and leaves the offer", refusedUseKeepsNothing),
        ("The site kind does not reach the model while the site signal awaits Accessibility", siteKindNeedsTrust),
        ("Undo leaves a label archived when a category of the person's now has its name", undoLeavesATakenNameArchived),
        ("The launch counts the records of a Keep whose label file was not written", launchSettleCounts),
        ("Confirming the category of an automatic record that never said its source makes it the person's", confirmingAnUnsaidSource),
        ("A refused Use whose label file cannot be put back leaves the label kept and offers it", refusedRollbackKeepsTheLabel),
    ]

    /// What the label file is blocked by once Keep has saved, and how to free it.
    private final class Block { var unblock: (() -> Void)? }

    private static func refusedRollbackKeepsTheLabel() -> [String] {
        let journal = SplitRestructureChecks.Journal()
        return Rig.withRig([Spec(seed: 1), Spec(seed: 1)], journal: { journal.save() },
                           reply: { _, _ in Rig.answer("new", "Films") }) { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            rig.mode.assigns = true
            rig.ask(0)
            rig.mode.assigns = false
            rig.f.clock.advance(60)
            rig.ask(1)
            guard case .label(let id)? = rig.assistant.suggestions[rig.records[1].id] else {
                return problems.append("the label was not suggested: \(rig.assistant.suggestions)")
            }
            // Keep's own save goes through; every one after it is refused.
            let block = Block()
            let observer = NotificationCenter.default.addObserver(
                forName: AILabelStore.didSave, object: rig.assistant.labels, queue: nil) { _ in
                MainActor.assumeIsolated { if block.unblock == nil { block.unblock = AILaunchChecks.blockLabelFile(rig) } }
            }
            defer { NotificationCenter.default.removeObserver(observer); block.unblock?() }
            journal.failFirstSave()
            expect(!rig.use(rig.session(1)), "a refused filing reported success", &problems)
            expect(block.unblock != nil, "the label file was not blocked after Keep's save", &problems)
            expect(WorkType.startable.contains(WorkType(rawValue: id)) && !rig.assistant.labels.book.labels.contains { $0.id == id },
                   "a label the file could not take back is not the person's category", &problems)
            let shown = rig.f.store.aiReport(for: rig.session(1)).suggestion
            expect(shown == .pick(WorkType(rawValue: id)), "the kept label is not offered as a pick: \(String(describing: shown))", &problems)
            expect(rig.f.store.correctionError != nil, "a refused Use showed no error", &problems)
        }
    }

    private static func twinOffersTheKeptCategory() -> [String] {
        Rig.withRig([Spec(seed: 1), Spec(seed: 1)], reply: { _, _ in Rig.answer("new", "Films") }) { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            rig.ask(0)
            rig.ask(1)
            guard case .proposed(let id, _)? = rig.assistant.suggestions[rig.records[1].id] else {
                return problems.append("the twin was not offered the proposal: \(rig.assistant.suggestions)")
            }
            expect(rig.use(rig.session(0)), "Use on the first session was refused: \(rig.f.store.correctionError ?? "no reason")", &problems)
            // Undo takes back the filing and what it taught, not the category Use kept: the twin may be asked about again.
            expect(rig.f.store.undoLastCorrection(), "Undo of the Use was refused", &problems)
            let shown = rig.f.store.aiReport(for: rig.session(1)).suggestion
            expect(shown == .pick(WorkType(rawValue: id)),
                   "the twin was not offered the category kept from its proposal: \(String(describing: shown))", &problems)
        }
    }

    private static func refusedUseKeepsNothing() -> [String] {
        let journal = SplitRestructureChecks.Journal()
        return Rig.withRig(journal: { journal.save() }, reply: { _, _ in Rig.answer("new", "Films") }) { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            rig.ask()
            let offered = rig.f.store.aiReport(for: rig.session()).suggestion
            guard offered == .newCategory(name: "Films") else { return problems.append("Films was not offered: \(String(describing: offered))") }
            journal.failFirstSave()
            expect(!rig.use(rig.session()), "a refused filing reported success", &problems)
            expect(!rig.f.persistence.workTypeDefinitions.contains { $0.name == "Films" },
                   "a refused Use left a Films category: \(rig.f.persistence.workTypeDefinitions.map(\.name))", &problems)
            let after = rig.f.store.aiReport(for: rig.session()).suggestion
            expect(after == offered, "the offer did not stay after a refused Use: \(String(describing: after))", &problems)
            expect(rig.f.store.correctionError != nil, "a refused Use showed no error", &problems)
            expect(rig.stored() == rig.record, "a refused Use changed the record: \(String(describing: rig.stored()))", &problems)
        }
    }

    private static func siteKindNeedsTrust() -> [String] {
        func spec(_ seed: Int) -> Spec {
            var spec = Spec(seed: seed)
            spec.fingerprint = ActivityFingerprint(shares: AIFixture.fingerprint(seed).shares, topApps: ["app.\(seed)", ""],
                                                   siteKind: "video")
            return spec
        }
        return Rig.withRig([spec(1), spec(2)], reply: { _, _ in Rig.answer("none") }) { rig, problems in
            let suite = "fc-selftest-ai-site-trust-\(UUID().uuidString)"
            guard let defaults = MemoryDefaults.suite(named: suite) else { return problems.append("no preferences suite") }
            defer { MemoryDefaults.remove(named: suite) }
            final class Trust { var on = false }
            let trust = Trust()
            SiteSignalSettings(defaults: defaults).turnOn(apps: [SiteSignalChecks.chrome])
            rig.f.store.installSiteSignal(defaults: defaults, gateOn: { true }, trusted: { trust.on })
            @MainActor func told(_ index: Int) -> Bool {
                rig.ask(index)
                return rig.calls.questions.last?.text.contains("Site kind") == true
            }
            expect(!told(0), "the site kind reached the model with Accessibility taken away", &problems)
            trust.on = true
            expect(told(1), "the site kind did not reach the model with the signal on", &problems)
        }
    }

    private static func undoLeavesATakenNameArchived() -> [String] {
        Rig.withRig(reply: { _, _ in Rig.answer("new", "Films") }) { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            rig.mode.assigns = true
            rig.ask()
            guard let label = rig.assistant.labels.book.labels.first else { return problems.append("no label was made") }
            expect(rig.f.store.removeAILabel(label.id), "Remove was refused", &problems)
            rig.f.persistence.workTypeDefinitions += [
                WorkTypeDefinition(id: "custom.selftest-films", name: "Films", symbolName: "film.fill", hue: .red)]
            expect(rig.f.store.undoLastCorrection(), "Undo of the Remove was refused", &problems)
            expect(rig.stored()?.workType.rawValue == label.id, "Undo did not put the session back under the label", &problems)
            let book = rig.reloaded().book
            expect(book.labels.first { $0.id == label.id }?.archived == true && book.removedNames.contains("Films"),
                   "Undo brought back a label whose name the person's category holds: \(book.labels.map(\.archived)) "
                   + "\(book.removedNames)", &problems)
            expect(!book.liveLabels(now: rig.f.clock.value).contains { $0.name == "Films" }, "a live Films label is left", &problems)
        }
    }

    private static func launchSettleCounts() -> [String] {
        Rig.withRig(reply: { _, _ in Rig.answer("new", "Films") }) { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            rig.mode.assigns = true
            rig.ask()
            guard let label = rig.assistant.labels.book.labels.first else { return problems.append("no label was made") }
            // What a Keep leaves when the category is written and the label file is not: both hold the id.
            var kept = label.hiddenDefinition
            kept.isUnkeptAILabel = false
            rig.f.persistence.workTypeDefinitions += [kept]
            let mode = rig.mode
            let fresh = CategoryAssistant(store: rig.f.store, labels: AILabelStore(directory: rig.directory), assigns: { mode.assigns })
            fresh.responder = { _ in Rig.answer("none") }
            rig.f.store.installCategoryAssistant(fresh)
            let chosen = rig.reloaded().book.tally.first { $0.recordID == rig.record.id }?.chosen
            expect(chosen == label.id, "the launch did not count the kept label's record: \(String(describing: chosen))", &problems)
        }
    }

    private static func confirmingAnUnsaidSource() -> [String] {
        var problems: [String] = []
        var record = SessionRecord(name: "Parser", workType: .deepWork, start: SelfTest.base,
                                   end: SelfTest.base.addingTimeInterval(1_800), workSeconds: 1_800, threadID: UUID(),
                                   isAuto: true, origin: .automatic, categorySource: nil)
        record.recategorise(to: .deepWork, confirming: true)
        expect(record.categorySource == .user,
               "confirming an automatic record's category left its source \(String(describing: record.categorySource))", &problems)
        return problems
    }
}
