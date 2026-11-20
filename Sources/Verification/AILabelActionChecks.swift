import Foundation

/// The person's answers to what the model said (Phase C, rulings C13, C14 and C25): Keep and Change on an AI
/// pick, Keep and Rename on an AI-made label, Use on a suggestion, and the tally of every such choice.
enum AILabelActionChecks: CheckSuite {
    private typealias Rig = CategoryAssistantRig
    private typealias Spec = CategoryAssistantRig.Spec

    static let tests: [(String, () -> [String])] = [
        ("Keep on an AI pick makes it the person's, counts a match, and Undo gives the pick back", keepsAPick),
        ("Changing an AI pick in the picker remembers it vetoed and counts a miss", changeVetoesThePick),
        ("Keep on an AI-made label makes it the person's category under the same id, records unchanged", keepsALabel),
        ("Rename keeps an AI-made label under the typed name, and refuses an empty one", renamesALabel),
        ("Use on a suggested pick or a suggested new label files the session as the person's", usesASuggestion),
    ]

    /// Assigning on, the model's answer written; the store reaches the assistant's label file.
    @MainActor private static func assigned(_ rig: Rig.Rig) {
        rig.f.store.installCategoryAssistant(rig.assistant)
        rig.mode.assigns = true
        rig.ask()
    }

    private static func keepsAPick() -> [String] {
        Rig.withRig(reply: { _, _ in Rig.answer("2") }) { rig, problems in
            assigned(rig)
            guard let picked = rig.stored(), picked.categorySource == .ai else {
                problems.append("no pick was written: \(String(describing: rig.stored()))"); return
            }
            expect(rig.f.store.keepAIPick(rig.session()), "Keep on the pick was refused", &problems)
            expect(rig.stored()?.workType == picked.workType && rig.stored()?.categorySource == .user,
                   "Keep did not make the pick the person's: \(String(describing: rig.stored()))", &problems)
            let text = rig.assistant.labels.book.tallyText()
            expect(text == "AI matched your last choice", "Keep was not counted a match: \(text)", &problems)
            expect(rig.f.store.undoLastCorrection() && rig.stored() == picked,
                   "Undo did not give the AI pick back: \(String(describing: rig.stored()))", &problems)
        }
    }

    private static func changeVetoesThePick() -> [String] {
        Rig.withRig(reply: { _, _ in Rig.answer("2") }) { rig, problems in
            assigned(rig)
            guard let picked = rig.stored(), picked.categorySource == .ai else {
                problems.append("no pick was written: \(String(describing: rig.stored()))"); return
            }
            let other: WorkType = picked.workType == .admin ? .meetings : .admin
            expect(rig.f.store.setWorkType(other, for: rig.session()), "the picker's change was refused", &problems)
            expect(rig.stored()?.workType == other && rig.stored()?.categorySource == .user,
                   "the change was not the person's: \(String(describing: rig.stored()))", &problems)
            let learned = CorrectionsStore(directory: rig.directory, now: rig.f.clock.value).corrections.entries.first { $0.fingerprint == AIFixture.fingerprint(1) }
            expect(learned?.chosen == other.rawValue && learned?.vetoed == [picked.workType.rawValue],
                   "the correction did not veto the AI pick: \(String(describing: learned))", &problems)
            let text = rig.assistant.labels.book.tallyText()
            expect(text == "AI did not match your last choice", "the picker's choice was not counted: \(text)", &problems)
        }
    }

    private static func keepsALabel() -> [String] {
        Rig.withRig(reply: { _, _ in Rig.answer("new", "Films") }) { rig, problems in
            assigned(rig)
            guard let label = rig.assistant.labels.book.labels.first, let carried = rig.stored(),
                  carried.workType.rawValue == label.id else { problems.append("no label was made and written"); return }
            expect(!rig.f.persistence.workTypeDefinitions.contains { $0.id.hasPrefix("ai.") },
                   "an unkept label was among the person's categories before Keep", &problems)
            expect(rig.f.store.keepAILabel(label.id), "Keep on the label was refused", &problems)
            let kept = rig.f.persistence.workTypeDefinitions.first { $0.id == label.id }
            expect(kept?.name == "Films" && kept?.isUnkeptAILabel == false && kept?.countsTowardFocus == label.countsTowardFocus,
                   "the label did not join the person's categories under its id: \(String(describing: kept))", &problems)
            expect(rig.assistant.labels.book.labels.isEmpty && rig.reloaded().book.labels.isEmpty,
                   "the kept label stayed among the unkept ones", &problems)
            expect(WorkType.startable.contains(WorkType(rawValue: label.id)) && WorkType(rawValue: label.id).displayName == "Films",
                   "the kept label cannot be started", &problems)
            expect(rig.stored() == carried, "Keep changed the record: \(String(describing: rig.stored()))", &problems)
            let text = rig.assistant.labels.book.tallyText()
            expect(text == "AI matched your last choice", "Keep on the label was not counted a match: \(text)", &problems)
        }
    }

    private static func renamesALabel() -> [String] {
        Rig.withRig(reply: { _, _ in Rig.answer("new", "Films") }) { rig, problems in
            assigned(rig)
            guard let label = rig.assistant.labels.book.labels.first else { problems.append("no label was made"); return }
            expect(!rig.f.store.keepAILabel(label.id, as: "   ") && rig.assistant.labels.book.labels.count == 1
                   && rig.f.persistence.workTypeDefinitions.isEmpty, "an empty name was kept", &problems)
            expect(rig.f.store.keepAILabel(label.id, as: "  Movies "), "Rename was refused", &problems)
            let kept = rig.f.persistence.workTypeDefinitions.first { $0.id == label.id }
            expect(kept?.name == "Movies" && WorkType(rawValue: label.id).displayName == "Movies",
                   "the label was not kept under the typed name: \(String(describing: kept))", &problems)
            expect(rig.stored()?.workType.rawValue == label.id, "Rename moved the record", &problems)
        }
    }

    private static func usesASuggestion() -> [String] {
        let replies = [1: Rig.answer("new", "Films"), 2: Rig.answer("2")]
        return Rig.withRig([Spec(seed: 1), Spec(seed: 2)], reply: { count, _ in replies[count] ?? Rig.answer("none") }) { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            rig.ask(0)
            rig.ask(1)
            guard case .proposed(let id, _)? = rig.assistant.suggestions[rig.records[0].id],
                  case .pick(let pick)? = rig.assistant.suggestions[rig.records[1].id] else {
                problems.append("shadow mode offered no suggestions: \(rig.assistant.suggestions)"); return
            }
            expect(rig.use(rig.session(0)), "Use on a new label was refused", &problems)
            let kept = rig.f.persistence.workTypeDefinitions.first { $0.id == id }
            expect(kept?.name == "Films" && kept?.isUnkeptAILabel == false && rig.assistant.labels.book.labels.isEmpty,
                   "Use did not make the label the person's: \(String(describing: kept))", &problems)
            expect(rig.stored(0)?.workType.rawValue == id && rig.stored(0)?.categorySource == .user,
                   "Use did not file the session: \(String(describing: rig.stored(0)))", &problems)
            expect(rig.use(rig.session(1)), "Use on a pick was refused", &problems)
            expect(rig.stored(1)?.workType.rawValue == pick && rig.stored(1)?.categorySource == .user,
                   "Use did not file the pick: \(String(describing: rig.stored(1)))", &problems)
            expect(rig.assistant.suggestions.isEmpty, "a used suggestion is still offered: \(rig.assistant.suggestions)", &problems)
            let text = rig.assistant.labels.book.tallyText()
            expect(text == "AI matched 2 of your last 2 choices", "Use was not counted a match: \(text)", &problems)
        }
    }
}
