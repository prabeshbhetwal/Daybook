import Foundation

/// The label file at a launch and around a Keep (Phase C review): shadow mode's offers come back when the
/// assistant is installed and when on-device AI is turned on later, a Keep the label file cannot take keeps
/// nothing, a label the person's categories already hold leaves the file, and cached answers past their time go.
enum AILaunchChecks: CheckSuite {
    private typealias Rig = CategoryAssistantRig

    static let tests: [(String, () -> [String])] = [
        ("An idle relaunch brings shadow mode's offers back as the assistant is installed", offersReturnAtInstall),
        ("Offers come back when on-device AI is turned on, or assigning off, after a launch without them", offersReturnWhenTurnedOn),
        ("Keep with the label file unwritable keeps nothing and says why", keepNeedsTheLabelFile),
        ("A label the person's categories already hold reads as kept and leaves the label file at launch", keptLabelLeavesTheFile),
        ("A cached answer unused past its time is pruned whenever the label file is written", staleAnswersArePruned),
    ]

    /// A relaunch: a fresh assistant over the rig's label file, its model a stand-in that answers none.
    @MainActor private static func relaunched(_ rig: Rig.Rig) -> CategoryAssistant {
        let mode = rig.mode
        let fresh = CategoryAssistant(store: rig.f.store, labels: AILabelStore(directory: rig.directory), assigns: { mode.assigns })
        fresh.responder = { _ in Rig.answer("none") }
        return fresh
    }

    /// Puts a folder where the label file goes, so its saves fail and nothing else in the data folder does.
    /// The closure takes the folder away again.
    @MainActor static func blockLabelFile(_ rig: CategoryAssistantRig.Rig) -> (() -> Void)? {
        let manager = FileManager.default, file = rig.directory.appendingPathComponent(AILabelStore.fileName)
        try? manager.removeItem(at: file)
        guard (try? manager.createDirectory(at: file.appendingPathComponent("held"), withIntermediateDirectories: true)) != nil
        else { return nil }
        return { try? manager.removeItem(at: file) }
    }

    private static func offersReturnAtInstall() -> [String] {
        Rig.withRig(reply: { _, _ in Rig.answer("2") }) { rig, problems in
            rig.ask()
            guard rig.assistant.suggestions[rig.record.id] != nil else { return problems.append("nothing was offered") }
            let fresh = relaunched(rig)
            rig.f.store.installCategoryAssistant(fresh)
            expect(fresh.suggestions[rig.record.id] == .pick(WorkType.meetings.rawValue),
                   "an idle relaunch did not bring the offer back before any sweep: \(fresh.suggestions)", &problems)
        }
    }

    private static func offersReturnWhenTurnedOn() -> [String] {
        // Launched with assigning on, then assigning turned off: shadow mode's offers come back.
        let assigning = Rig.withRig(reply: { _, _ in Rig.answer("2") }) { rig, problems in
            rig.ask()
            rig.mode.assigns = true
            let fresh = relaunched(rig)
            rig.f.store.installCategoryAssistant(fresh)
            rig.f.store.refresh()
            expect(fresh.suggestions.isEmpty, "an offer came back with assigning on: \(fresh.suggestions)", &problems)
            rig.mode.assigns = false
            rig.f.store.refresh()
            expect(fresh.suggestions[rig.record.id] == .pick(WorkType.meetings.rawValue),
                   "turning assigning off did not bring the offer back: \(fresh.suggestions)", &problems)
        }
        return assigning + Rig.withRig(reply: { _, _ in Rig.answer("2") }) { rig, problems in
            rig.ask()
            guard rig.assistant.suggestions[rig.record.id] != nil else { return problems.append("nothing was offered") }
            rig.f.persistence.useAppleIntelligence = false
            let fresh = relaunched(rig)
            rig.f.store.installCategoryAssistant(fresh)
            // The launch's first pass and a refresh, both with on-device AI off.
            rig.f.store.writeActivitySnapshots()
            rig.f.store.refresh()
            expect(fresh.suggestions.isEmpty, "an offer came back with on-device AI off: \(fresh.suggestions)", &problems)
            rig.f.persistence.useAppleIntelligence = true
            rig.f.store.refresh()
            expect(fresh.suggestions[rig.record.id] == .pick(WorkType.meetings.rawValue),
                   "turning on-device AI on did not bring the offer back: \(fresh.suggestions)", &problems)
        }
    }

    private static func keepNeedsTheLabelFile() -> [String] {
        Rig.withRig(reply: { _, _ in Rig.answer("new", "Films") }) { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            rig.mode.assigns = true
            rig.ask()
            guard let label = rig.assistant.labels.book.labels.first else { return problems.append("no label was made") }
            guard let unblock = blockLabelFile(rig) else { return problems.append("the label file could not be held") }
            defer { unblock() }
            expect(!rig.f.store.keepAILabel(label.id), "Keep reported success with the label file unwritable", &problems)
            expect(!rig.f.persistence.workTypeDefinitions.contains { $0.id == label.id },
                   "the label joined the person's categories though its file kept it", &problems)
            expect(rig.f.store.correctionError != nil, "the refused save was not shown", &problems)
        }
    }

    private static func keptLabelLeavesTheFile() -> [String] {
        Rig.withRig(reply: { _, _ in Rig.answer("new", "Films") }) { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            rig.mode.assigns = true
            rig.ask()
            guard let label = rig.assistant.labels.book.labels.first else { return problems.append("no label was made") }
            // What a Keep leaves when the category is written and the label file is not: both hold the id.
            var kept = label.hiddenDefinition
            kept.isUnkeptAILabel = false
            rig.f.persistence.workTypeDefinitions += [kept]
            let filing = rig.f.store.aiReport(for: rig.session()).filing
            expect(filing == .pick(kept.workType), "a label the person kept was offered as an AI label: \(String(describing: filing))", &problems)
            rig.f.store.installCategoryAssistant(relaunched(rig))
            expect(!rig.reloaded().book.labels.contains { $0.id == label.id },
                   "the kept label was left in the label file at launch", &problems)
            expect(rig.f.persistence.workTypeDefinitions.contains { $0.id == label.id }, "the person's category was lost", &problems)
        }
    }

    private static func staleAnswersArePruned() -> [String] {
        var problems: [String] = []
        var book = AILabelBook()
        let offered = [WorkType.deepWork.rawValue], expiry = AILabelConstants.answerExpiry
        book.recordAnswer(.pick(offered[0]), recordID: UUID(), fingerprint: AIFixture.fingerprint(1), offered: offered,
                          now: AIFixture.base)
        book.recordAnswer(.pick(offered[0]), recordID: UUID(), fingerprint: AIFixture.fingerprint(2), offered: offered,
                          now: AIFixture.base.addingTimeInterval(expiry))
        book.archiveStale(now: AIFixture.base.addingTimeInterval(expiry + 1))
        expect(book.answers.map(\.fingerprint) == [AIFixture.fingerprint(2)],
               "an answer unused past its time was kept, or one in time dropped: \(book.answers.count)", &problems)
        return problems
    }
}
