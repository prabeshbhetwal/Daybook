import Foundation

/// Merge Into and Remove on an AI-made label (Phase C, ruling C13; Review Focus 4 and 5): every record that
/// carries it changes as one undo step, the name is never proposed again, and one Undo puts every record and
/// the label back exactly.
enum AILabelRetireChecks: CheckSuite {
    private typealias Rig = CategoryAssistantRig
    private typealias Spec = CategoryAssistantRig.Spec

    static let tests: [(String, () -> [String])] = [
        ("Merge Into over three sessions is one undo step that restores each record and the label", { retiresAsOneStep(remove: false) }),
        ("Remove over three sessions is one undo step that restores each record and the label", { retiresAsOneStep(remove: true) }),
        ("A merged label's name is never proposed again", { neverProposedAgain(remove: false) }),
        ("A removed label's name is never proposed again", { neverProposedAgain(remove: true) }),
        ("A session continued from a labelled one runs under a category of the person's, so Remove leaves it be", runsNoneUnderALabel),
        ("Remove refused with an away question open leaves the label, its name and its answers as they were", refusedBeforeTheLabelGoes),
        ("Remove that lands with its journal save refused clears an older action's Retry", landedClearsAnOlderRetry),
        ("Use on a label whose filing was refused once files the session when used again", useAfterARefusedFiling),
        ("Keep refuses a label already merged or removed", keepRefusesARetiredLabel),
        ("A category change that lands with its journal save refused is counted", countsALandedChange),
    ]

    @MainActor private static func labelled(_ rig: Rig.Rig, _ index: Int = 0) -> AILabel? {
        rig.f.store.installCategoryAssistant(rig.assistant)
        rig.mode.assigns = true
        rig.ask(index)
        return rig.assistant.labels.book.labels.first
    }

    private static func refusedBeforeTheLabelGoes() -> [String] {
        Rig.withRig(reply: { _, _ in Rig.answer("new", "Films") }) { rig, problems in
            guard let label = labelled(rig), let carried = rig.stored() else { problems.append("no label was made"); return }
            // A sleep that outlasts the session's patience leaves the away question open.
            rig.f.engine.start(workType: .learning, intent: "Pending")
            rig.f.clock.advance(20 * 60)
            rig.f.engine.transition(on: .awayBegan(trigger: .systemSleep))
            rig.f.clock.advance(20 * 60)
            rig.f.engine.transition(on: .awayEnded)
            guard rig.f.store.hasUnresolvedAwayDecision else { problems.append("the away question did not open"); return }
            let before = rig.reloaded().book
            expect(!rig.f.store.removeAILabel(label.id), "Remove went ahead with an away question open", &problems)
            let after = rig.reloaded().book
            expect(after == before, "a refused Remove changed the label file: archived \(after.labels.map(\.archived)), "
                   + "removed \(after.removedNames), answers \(after.answers.count) of \(before.answers.count)", &problems)
            expect(rig.stored() == carried, "a refused Remove changed the record: \(String(describing: rig.stored()))", &problems)
        }
    }

    private static func landedClearsAnOlderRetry() -> [String] {
        let journal = SplitRestructureChecks.Journal()
        return Rig.withRig([Spec(seed: 1), Spec(seed: 2)], journal: { journal.save() },
                           reply: { _, _ in Rig.answer("new", "Films") }) { rig, problems in
            guard let label = labelled(rig) else { problems.append("no label was made"); return }
            let store = rig.f.store, other = rig.records[1]
            // A cut of the other session refused before its write leaves its Retry shown.
            journal.failFirstSave()
            guard !store.splitSession(recordID: other.id, at: other.start.addingTimeInterval(900),
                                      tail: SplitTail(name: "Tail", workType: .deepWork, source: .builtIn, nameByApp: true)),
                  store.correctionRetry != nil else { problems.append("the cut was not refused with a Retry"); return }
            journal.failSecondSave()
            expect(store.removeAILabel(label.id) && rig.stored(0)?.workType == .unsorted,
                   "Remove did not land with its journal save refused: \(String(describing: rig.stored(0)))", &problems)
            expect(store.correctionError != nil && store.correctionRetry == nil,
                   "the refused save was not shown, or the cut's Retry stayed: \(String(describing: store.correctionRetry))", &problems)
            expect(store.canUndoCorrection == (!store.corrections.isEmpty || rig.f.engine.canUndoAwayDecision),
                   "Undo was offered as \(store.canUndoCorrection) with \(store.corrections.count) corrections", &problems)
        }
    }

    private static func useAfterARefusedFiling() -> [String] {
        let journal = SplitRestructureChecks.Journal()
        return Rig.withRig([Spec(seed: 1), Spec(seed: 1)], journal: { journal.save() },
                           reply: { _, _ in Rig.answer("new", "Films") }) { rig, problems in
            guard labelled(rig) != nil else { problems.append("no label was made"); return }
            rig.mode.assigns = false
            rig.f.clock.advance(60)
            rig.ask(1)
            guard case .label(let id)? = rig.assistant.suggestions[rig.records[1].id] else {
                problems.append("the label was not suggested: \(rig.assistant.suggestions)"); return
            }
            journal.failFirstSave()
            expect(!rig.use(rig.session(1)), "a refused filing reported success", &problems)
            // Round 5: a filing that does not land takes back the category Use kept for it.
            expect(!WorkType.startable.contains(WorkType(rawValue: id)) && rig.assistant.labels.book.labels.contains { $0.id == id },
                   "a refused filing left the label kept, or out of the label file", &problems)
            expect(rig.use(rig.session(1)), "Use again was refused", &problems)
            expect(rig.stored(1)?.workType.rawValue == id && rig.stored(1)?.categorySource == .user,
                   "Use again did not file the session: \(String(describing: rig.stored(1)))", &problems)
        }
    }

    private static func keepRefusesARetiredLabel() -> [String] {
        Rig.withRig(reply: { _, _ in Rig.answer("new", "Films") }) { rig, problems in
            guard let label = labelled(rig) else { problems.append("no label was made"); return }
            expect(rig.f.store.removeAILabel(label.id), "Remove was refused", &problems)
            expect(!rig.f.store.keepAILabel(label.id), "Keep brought a removed label back", &problems)
            expect(!rig.f.persistence.workTypeDefinitions.contains { $0.id == label.id }
                   && rig.reloaded().book.removedNames.contains("Films"),
                   "a removed label became the person's category: \(rig.f.persistence.workTypeDefinitions.map(\.id))", &problems)
        }
    }

    private static func countsALandedChange() -> [String] {
        let journal = SplitRestructureChecks.Journal()
        return Rig.withRig(journal: { journal.save() }, reply: { _, _ in Rig.answer("2") }) { rig, problems in
            _ = labelled(rig)
            guard let picked = rig.stored(), picked.categorySource == .ai else {
                problems.append("no pick was written: \(String(describing: rig.stored()))"); return
            }
            let other: WorkType = picked.workType == .admin ? .meetings : .admin
            journal.failSecondSave()
            _ = rig.f.store.setWorkType(other, for: rig.session())
            expect(rig.stored()?.workType == other, "the change did not land with its journal save refused", &problems)
            let text = rig.assistant.labels.book.tallyText()
            expect(text == "AI did not match your last choice", "a change that landed was not counted: \(text)", &problems)
        }
    }

    /// Why Merge Into and Remove change ended records only: no running stretch carries an unkept label.
    private static func runsNoneUnderALabel() -> [String] {
        Rig.withRig(reply: { _, _ in Rig.answer("new", "Films") }) { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            rig.mode.assigns = true
            rig.ask()
            guard let label = rig.assistant.labels.book.labels.first else { problems.append("no label was made"); return }
            // Continue starts the thread again under the category it had.
            expect(rig.f.store.replaceSession(workType: WorkType(rawValue: label.id), intent: "Films", threadID: rig.record.threadID),
                   "no session started", &problems)
            let running = rig.f.engine.activeWorkType
            expect(running.rawValue != label.id && WorkType.startable.contains(running),
                   "a session runs under the unkept label: \(running.rawValue)", &problems)
            expect(rig.f.store.removeAILabel(label.id) && rig.stored()?.workType == .unsorted,
                   "Remove did not file the ended session: \(String(describing: rig.stored()))", &problems)
        }
    }

    @MainActor private static func retire(_ rig: Rig.Rig, _ id: String, remove: Bool) -> Bool {
        remove ? rig.f.store.removeAILabel(id) : rig.f.store.mergeAILabel(id, into: .admin)
    }

    private static func retiresAsOneStep(remove: Bool) -> [String] {
        let target: WorkType = remove ? .unsorted : .admin
        return Rig.withRig([Spec(seed: 1), Spec(seed: 1), Spec(seed: 1)],
                           reply: { _, _ in Rig.answer("new", "Films") }) { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            rig.mode.assigns = true
            for index in 0..<3 { rig.ask(index); rig.f.clock.advance(60) }
            let carried = (0..<3).compactMap { rig.stored($0) }
            guard let label = rig.assistant.labels.book.labels.first, carried.count == 3,
                  carried.allSatisfy({ $0.workType.rawValue == label.id && $0.categorySource == .ai }) else {
                problems.append("the three sessions did not all carry one label: \(carried)"); return
            }
            let steps = rig.f.store.corrections.count
            expect(retire(rig, label.id, remove: remove), "the label could not be retired", &problems)
            expect((0..<3).allSatisfy { rig.stored($0)?.workType == target && rig.stored($0)?.categorySource == .user },
                   "not every record took \(target.rawValue) as the person's: \((0..<3).map { rig.stored($0) })", &problems)
            expect(rig.f.store.corrections.count == steps + 1,
                   "it was \(rig.f.store.corrections.count - steps) undo steps, not one", &problems)
            let book = rig.reloaded().book
            expect(book.removedNames.contains("Films") && book.liveLabels(now: rig.f.clock.value).isEmpty
                   && !book.answers.contains { $0.answer.id == label.id },
                   "the label was not retired, named removed and its answers forgotten: \(book.removedNames)", &problems)
            expect(!rig.f.persistence.workTypeDefinitions.contains { $0.id.hasPrefix("ai.") },
                   "an AI label reached the person's categories: \(rig.f.persistence.workTypeDefinitions.map(\.id))", &problems)
            let text = book.tallyText()
            expect(text == "AI matched 0 of your last 3 choices", "the choices were not counted: \(text)", &problems)

            expect(rig.f.store.undoLastCorrection(), "Undo was refused", &problems)
            let back = (0..<3).compactMap { rig.stored($0) }
            expect(back == carried, "one Undo did not put every record back exactly: \(back)", &problems)
            let restored = rig.reloaded().book
            expect(restored.liveLabels(now: rig.f.clock.value).map(\.id) == [label.id] && !restored.removedNames.contains("Films")
                   && WorkType(rawValue: label.id).displayName == "Films",
                   "Undo did not give the label back: \(restored.labels)", &problems)
        }
    }

    private static func neverProposedAgain(remove: Bool) -> [String] {
        Rig.withRig([Spec(seed: 1), Spec(seed: 2)], reply: { _, _ in Rig.answer("new", "films") }) { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            rig.mode.assigns = true
            rig.ask(0)
            guard let label = rig.assistant.labels.book.labels.first else { problems.append("no label was made"); return }
            expect(retire(rig, label.id, remove: remove), "the label could not be retired", &problems)
            // Past the daily limit, so only the name can stop a new one.
            rig.f.clock.advance(AILabelConstants.labelWindow + 1)
            rig.ask(1)
            expect(rig.calls.questions.count == 2, "the second session was not asked about", &problems)
            expect(rig.stored(1) == rig.records[1], "the retired name was written again: \(String(describing: rig.stored(1)))", &problems)
            let live = rig.assistant.labels.book.liveLabels(now: rig.f.clock.value)
            expect(live.isEmpty, "the retired name was made a label again: \(live.map(\.name))", &problems)
        }
    }
}
