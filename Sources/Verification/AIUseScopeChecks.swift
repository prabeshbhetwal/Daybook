import Foundation

/// What the person's answers to the AI reach (Phase C review): Use files only the stretches it was offered for and
/// teaches what Change teaches, a new category is drawn from the stretch that proposed it, a Use that lands with
/// its journal save refused still finishes, the ticked category makes a stretch the person's, and the row's AI
/// mark belongs to the category the row shows.
enum AIUseScopeChecks: CheckSuite {
    private typealias Rig = CategoryAssistantRig
    private typealias Spec = CategoryAssistantRig.Spec

    static let tests: [(String, () -> [String])] = [
        ("Use files only the stretches it was offered for, teaches the choice, and Undo takes both back", useFilesItsStretches),
        ("A new category Use keeps is drawn from the stretch that proposed it", proposalDrawnFromItsStretch),
        ("Use that lands with its journal save refused withdraws the suggestion and counts the choice", landedUseFinishes),
        ("Choosing the ticked category makes an AI or app filing the person's, counted, and no answer replaces it", tickedChipIsThePersons),
        ("The row's AI mark follows the stretch whose category the row shows", markFollowsTheShownCategory),
    ]

    /// Two stretches of one session: the first clear (never asked about), the second as `second` says.
    private static func clearThen(_ second: Spec = Spec(seed: 2)) -> [Spec] {
        let thread = UUID()
        var clear = Spec(seed: 1), other = second
        clear.credited = [.coding: 1_700, .research: 100]
        clear.threadID = thread
        other.threadID = thread
        return [clear, other]
    }

    private static func useFilesItsStretches() -> [String] {
        Rig.withRig(clearThen(), reply: { _, _ in Rig.answer("2") }) { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            rig.ask(1)
            expect(rig.use(AIOfferChecks.joined(rig)), "Use was refused", &problems)
            expect(rig.stored(1)?.workType == .meetings && rig.stored(1)?.categorySource == .user,
                   "Use did not file the stretch it was offered for: \(String(describing: rig.stored(1)))", &problems)
            expect(rig.stored(0) == rig.records[0], "Use filed a stretch nothing was offered for: \(String(describing: rig.stored(0)))", &problems)
            @MainActor func learned() -> CategoryCorrection? {
                CorrectionsStore(directory: rig.directory, now: rig.f.clock.value).corrections.entries
                    .first { $0.fingerprint == AIFixture.fingerprint(2) }
            }
            expect(learned()?.chosen == WorkType.meetings.rawValue && learned()?.vetoed == [WorkType.deepWork.rawValue],
                   "Use did not teach the choice with the app's own vetoed: \(String(describing: learned()))", &problems)
            expect(rig.f.store.undoLastCorrection() && rig.stored(1) == rig.records[1],
                   "Undo did not put the stretch back: \(String(describing: rig.stored(1)))", &problems)
            expect(learned() == nil, "Undo left what Use taught: \(String(describing: learned()))", &problems)
        }
    }

    private static func proposalDrawnFromItsStretch() -> [String] {
        Rig.withRig(clearThen(), reply: { _, _ in Rig.answer("new", "Films") }) { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            rig.ask(1)
            expect(rig.use(AIOfferChecks.joined(rig)), "Use was refused", &problems)
            let kept = rig.f.persistence.workTypeDefinitions.first { $0.name == "Films" }
            let look = LabelLook.look(for: .media)
            expect(kept?.countsTowardFocus == false && kept?.symbolName == look.symbolName,
                   "the new category was drawn from a stretch it was not proposed for: \(String(describing: kept))", &problems)
        }
    }

    private static func landedUseFinishes() -> [String] {
        let journal = SplitRestructureChecks.Journal()
        return Rig.withRig(journal: { journal.save() }, reply: { _, _ in Rig.answer("2") }) { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            rig.ask()
            journal.failSecondSave()
            _ = rig.use(rig.session())
            expect(rig.stored()?.workType == .meetings && rig.stored()?.categorySource == .user,
                   "Use did not land with its journal save refused: \(String(describing: rig.stored()))", &problems)
            expect(rig.assistant.suggestions.isEmpty, "the suggestion Use took was still offered: \(rig.assistant.suggestions)", &problems)
            let text = rig.assistant.labels.book.tallyText()
            expect(text == "AI matched your last choice", "the landed choice was not counted a match: \(text)", &problems)
        }
    }

    private static func tickedChipIsThePersons() -> [String] {
        var problems = Rig.withRig(reply: { _, _ in Rig.answer("2") }) { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            rig.mode.assigns = true
            rig.ask()
            guard let picked = rig.stored(), picked.categorySource == .ai else { return problems.append("no pick was written") }
            expect(rig.f.store.setWorkType(picked.workType, for: rig.session()), "choosing the ticked category was refused", &problems)
            expect(rig.stored()?.workType == picked.workType && rig.stored()?.categorySource == .user,
                   "choosing the ticked category left it the AI's: \(String(describing: rig.stored()))", &problems)
            expect(!rig.f.store.rowMarks(for: rig.session()).aiMark, "the AI mark stayed on the person's choice", &problems)
            let text = rig.assistant.labels.book.tallyText()
            expect(text == "AI matched your last choice", "the choice was not counted: \(text)", &problems)
        }
        // The app's own filing, chosen by the person while the model thinks: the answer no longer replaces it.
        let hook = Rig.Hook()
        problems += Rig.withRig(reply: { _, _ in hook.run(); return Rig.answer("2") }) { rig, problems in
            hook.run = { _ = rig.f.store.setWorkType(.deepWork, for: rig.session()) }
            rig.mode.assigns = true
            rig.ask()
            expect(rig.stored()?.workType == .deepWork && rig.stored()?.categorySource == .user,
                   "the person's chosen category was replaced or not theirs: \(String(describing: rig.stored()))", &problems)
        }
        return problems
    }

    private static func markFollowsTheShownCategory() -> [String] {
        Rig.withRig(clearThen(), reply: { _, _ in Rig.answer("2") }) { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            rig.mode.assigns = true
            rig.ask(1)
            guard rig.stored(1)?.categorySource == .ai else { return problems.append("no pick was written") }
            let joined = AIOfferChecks.joined(rig)
            expect(joined.workType == .deepWork && !rig.f.store.rowMarks(for: joined).aiMark,
                   "the row marked \(joined.workType.displayName), which the app chose, as the AI's", &problems)
            expect(rig.f.store.rowMarks(for: rig.session(1)).aiMark, "the AI's own stretch lost its mark", &problems)
        }
    }
}
