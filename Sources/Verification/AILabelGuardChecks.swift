import Foundation

/// Keeping an AI label and Use hold to the person's own rules (Phase C whole-branch review, M1, L1 and L2): a
/// kept name passes the category editor's rule, Use is compared with the answer it took, and a Use that filing
/// would refuse keeps no category first.
enum AILabelGuardChecks: CheckSuite {
    private typealias Rig = CategoryAssistantRig

    static let tests: [(String, () -> [String])] = [
        ("Rename refuses Break, Unsorted and a name over 24 characters, each with the reason shown", renameFollowsTheEditor),
        ("Use on a proposal a category took since is counted a match with that category", useCountsTheAnswerItTook),
        ("Use with an away question open keeps no category and files nothing", useRefusedKeepsNothing),
        ("Use on two stretches compares the person's choice with each stretch's own answer", useKeepsEachStretchsAnswer),
    ]

    private static func renameFollowsTheEditor() -> [String] {
        Rig.withRig(reply: { _, _ in Rig.answer("new", "Films") }) { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            rig.mode.assigns = true
            rig.ask()
            guard let label = rig.assistant.labels.book.labels.first else { problems.append("no label was made"); return }
            let long = String(repeating: "a", count: WorkTypeDefinition.nameLimit + 1)
            for (typed, reason) in [("break", "already called"), ("UNSORTED", "already called"), (long, "24 characters")] {
                expect(!rig.f.store.keepAILabel(label.id, as: typed), "Rename kept “\(typed)”", &problems)
                expect(rig.f.store.correctionError?.contains(reason) == true,
                       "Rename to “\(typed)” said \(rig.f.store.correctionError ?? "nothing")", &problems)
            }
            expect(rig.f.persistence.workTypeDefinitions.isEmpty && rig.assistant.labels.book.labels.map(\.id) == [label.id],
                   "a refused Rename kept a category: \(rig.f.persistence.workTypeDefinitions.map(\.name))", &problems)
        }
    }

    private static func useCountsTheAnswerItTook() -> [String] {
        Rig.withRig(reply: { _, _ in Rig.answer("new", "Films") }) { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            rig.ask()
            let film = WorkTypeDefinition(id: "custom.selftest-film", name: "Film", symbolName: "film.fill", hue: .red)
            rig.f.persistence.workTypeDefinitions += [film]
            guard case .proposed? = rig.assistant.suggestions[rig.record.id],
                  rig.f.store.aiReport(for: rig.session()).suggestion == .pick(film.workType) else {
                problems.append("the proposal was not offered as Film: \(String(describing: rig.f.store.aiReport(for: rig.session()).suggestion))")
                return
            }
            expect(rig.use(rig.session()), "Use was refused", &problems)
            expect(rig.stored()?.workType == film.workType, "Use filed under \(rig.stored()?.workType.rawValue ?? "nothing")", &problems)
            let text = rig.assistant.labels.book.tallyText()
            expect(text == "AI matched your last choice", "Use was not counted a match: \(text)", &problems)
        }
    }

    private static func useRefusedKeepsNothing() -> [String] {
        Rig.withRig(reply: { _, _ in Rig.answer("new", "Films") }) { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            rig.ask()
            let before = rig.stored()
            // A sleep that outlasts the session's patience leaves the away question open.
            rig.f.engine.start(workType: .learning, intent: "Pending")
            rig.f.clock.advance(20 * 60)
            rig.f.engine.transition(on: .awayBegan(trigger: .systemSleep))
            rig.f.clock.advance(20 * 60)
            rig.f.engine.transition(on: .awayEnded)
            guard rig.f.store.hasUnresolvedAwayDecision, let shown = rig.f.store.aiReport(for: rig.session()).suggestion else {
                problems.append("no suggestion with the away question open"); return
            }
            expect(!rig.f.store.useAISuggestion(shown, for: rig.session()), "Use went ahead with an away question open", &problems)
            expect(rig.f.store.correctionError == "Answer the away question first.",
                   "Use refused saying \(rig.f.store.correctionError ?? "nothing")", &problems)
            expect(!rig.f.persistence.workTypeDefinitions.contains { $0.name == "Films" },
                   "a refused Use left a category behind: \(rig.f.persistence.workTypeDefinitions.map(\.name))", &problems)
            expect(rig.stored() == before, "a refused Use changed the session: \(String(describing: rig.stored()))", &problems)
        }
    }

    private static func useKeepsEachStretchsAnswer() -> [String] {
        let replies = [1: Rig.answer("new", "Films"), 2: Rig.answer("2")]
        return AIOfferChecks.twoStretches(reply: { count, _ in replies[count] ?? Rig.answer("none") }) { rig, problems in
            let film = WorkTypeDefinition(id: "custom.selftest-film", name: "Film", symbolName: "film.fill", hue: .red)
            rig.f.persistence.workTypeDefinitions += [film]
            let session = AIOfferChecks.joined(rig)
            guard case .pick(let other)? = rig.assistant.suggestions[rig.records[1].id], other != film.id,
                  rig.f.store.aiReport(for: session).suggestion == .pick(film.workType) else {
                problems.append("the stretches were not offered Film and another pick: \(rig.assistant.suggestions)"); return
            }
            expect(rig.use(session), "Use was refused", &problems)
            // Use filed only the stretch it was offered for; the second keeps its own offer, and Use files it next.
            expect(rig.stored(1) == rig.records[1] && rig.assistant.suggestions[rig.records[1].id] == .pick(other),
                   "Use filed or withdrew the second stretch: \(String(describing: rig.stored(1)))", &problems)
            expect(rig.use(AIOfferChecks.joined(rig)) && rig.stored(1)?.workType.rawValue == other,
                   "Use did not file the second stretch with its own answer", &problems)
            let text = rig.assistant.labels.book.tallyText()
            expect(text == "AI matched 2 of your last 2 choices", "each stretch's own answer was not kept: \(text)", &problems)
        }
    }
}
