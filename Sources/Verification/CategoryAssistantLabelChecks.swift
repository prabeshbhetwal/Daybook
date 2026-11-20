import Foundation

/// AI-made labels and the cache as the assistant uses them (Phase C, rulings C7, C9, C25 and C29): a label
/// is made unkept and written only while assigning is on and within the limits, a later session of its kind
/// gets it back with no question, and a cached answer in daily use does not lapse.
enum CategoryAssistantLabelChecks: CheckSuite {
    private typealias Rig = CategoryAssistantRig
    private typealias Spec = CategoryAssistantRig.Spec

    static let tests: [(String, () -> [String])] = [
        ("A proposed label is made unkept and written, a second within a day is not, and one after a day is", makesLabelsWithinLimits),
        ("A later session of the same kind gets the label back with no question", reusesALabelByCode),
        ("Shadow mode offers a proposed label and makes none", shadowMakesNoLabel),
        ("A cache hit is recorded again, so a pattern in daily use does not lapse", cacheHitsDoNotLapse),
        ("A cached proposal is not made a label once a category of the person's carries its name", cachedNameIsTaken),
        ("A cached proposal gets the live label that now holds its name, not a second one", cachedNameIsALiveLabel),
    ]

    private static func makesLabelsWithinLimits() -> [String] {
        let replies = [1: "Films", 2: "Games", 3: "Chess"]
        return Rig.withRig([Spec(seed: 1), Spec(seed: 2), Spec(seed: 3)],
                           reply: { count, _ in Rig.answer("new", replies[count] ?? "") }) { rig, problems in
            rig.mode.assigns = true
            rig.ask(0)
            let first = rig.assistant.labels.book.labels.first
            expect(first?.name == "Films" && first?.id.hasPrefix("ai.") == true && first?.countsTowardFocus == false
                   && first?.archived == false, "the label was not made unkept as Films: \(String(describing: first))", &problems)
            let id = first?.id ?? ""
            expect(rig.stored(0)?.workType.rawValue == id && rig.stored(0)?.categorySource == .ai,
                   "the record was not written under the new label: \(String(describing: rig.stored(0)))", &problems)
            let kind = WorkType(rawValue: id)
            expect(kind.displayName == "Films" && kind.definition.isHidden && !WorkType.startable.contains(kind)
                   && !kind.countsAsFocus, "the label did not reach the catalogue hidden and not counted: \(kind.definition)", &problems)
            expect(rig.reloaded().book.labels.map(\.id) == [id], "the label was not saved to the file", &problems)
            // The person renames a category of their own: the catalogue is installed again without the label book.
            rig.f.persistence.workTypeDefinitions = [
                WorkTypeDefinition(id: WorkType.admin.rawValue, name: "Paperwork", symbolName: "tray.full.fill", hue: .teal),
            ]
            expect(kind.displayName == "Films" && kind.definition.isHidden && WorkType.admin.displayName == "Paperwork",
                   "an edit to the person's own categories dropped the unkept label: \(kind.definition)", &problems)
            expect(rig.f.persistence.workTypeDefinitions.map(\.id) == [WorkType.admin.rawValue],
                   "an unkept label was written into the person's own categories: \(rig.f.persistence.workTypeDefinitions.map(\.id))", &problems)

            // A second within 24 hours: the answer is kept, nothing is made and nothing is written.
            rig.ask(1)
            expect(rig.calls.questions.count == 2 && !(rig.calls.questions[1].text.contains("Films")),
                   "the unkept label was offered to the model: \(rig.calls.questions.last?.text ?? "")", &problems)
            expect(rig.assistant.labels.book.labels.count == 1 && rig.stored(1) == rig.records[1],
                   "a second label within a day was made or written", &problems)
            expect(rig.assistant.labels.book.answers.contains { $0.answer.id != nil && $0.fingerprint == AIFixture.fingerprint(2) },
                   "the refused proposal was not cached", &problems)

            // After a day it may.
            rig.f.clock.advance(AILabelConstants.labelWindow + 1)
            rig.ask(2)
            expect(rig.assistant.labels.book.labels.map(\.name) == ["Films", "Chess"]
                   && rig.stored(2)?.categorySource == .ai, "a label after a day was refused", &problems)
        }
    }

    private static func reusesALabelByCode() -> [String] {
        Rig.withRig([Spec(seed: 1), Spec(seed: 1)], reply: { _, _ in Rig.answer("new", "Films") }) { rig, problems in
            rig.mode.assigns = true
            rig.ask(0)
            rig.f.clock.advance(3_600)
            rig.ask(1)
            let labels = rig.assistant.labels.book.labels
            expect(rig.calls.questions.count == 1, "the model was asked again for a kind that has a label: \(rig.calls.questions.count)", &problems)
            expect(labels.count == 1 && rig.stored(1)?.workType.rawValue == labels.first?.id && rig.stored(1)?.categorySource == .ai,
                   "the second session did not get the same label: \(String(describing: rig.stored(1)))", &problems)
            expect(labels.first?.lastUsed == rig.f.clock.value, "the label's use was not noted: \(String(describing: labels.first?.lastUsed))", &problems)
        }
    }

    private static func shadowMakesNoLabel() -> [String] {
        Rig.withRig(reply: { _, _ in Rig.answer("new", "Films") }) { rig, problems in
            rig.ask()
            let book = rig.reloaded().book
            guard case .proposed(let id, let name)? = rig.assistant.suggestions[rig.record.id] else {
                return problems.append("the proposal was not on offer: \(rig.assistant.suggestions)")
            }
            expect(name == "Films" && id.hasPrefix("ai."), "the offer was not a new label: \(id) \(name)", &problems)
            expect(book.labels.isEmpty && rig.stored() == rig.record, "shadow mode made a label or wrote the record", &problems)
            // The id is the one cached and tallied, so a kept suggestion can be told from any other (C25).
            expect(book.answers.first?.answer == .proposed(id: id, name: "Films") && book.tally.first?.answerID == id,
                   "the cached and tallied id was not the offered one: \(book.answers) \(book.tally)", &problems)
        }
    }

    private static func cachedNameIsTaken() -> [String] {
        Rig.withRig([Spec(seed: 1), Spec(seed: 1)], reply: { _, _ in Rig.answer("new", "Films") }) { rig, problems in
            // Shadow mode keeps the proposal in the cache, keyed by the ids of the categories offered.
            rig.ask(0)
            guard case .proposed(_, _)? = rig.reloaded().book.answers.first?.answer else {
                return problems.append("the proposal was not cached: \(rig.reloaded().book.answers)")
            }
            // The person names a category of their own "Films": a rename keeps its id, so the cache's key is unchanged.
            rig.f.persistence.workTypeDefinitions = [
                WorkTypeDefinition(id: WorkType.admin.rawValue, name: "Films", symbolName: "tray.full.fill", hue: .teal),
            ]
            rig.mode.assigns = true
            rig.ask(1)
            let labels = rig.assistant.labels.book.labels
            expect(labels.isEmpty, "a second Films was made beside the person's own: \(labels.map(\.name))", &problems)
            expect(rig.stored(1)?.workType.rawValue.hasPrefix("ai.") != true,
                   "the session was filed under a label named like the person's category: \(String(describing: rig.stored(1)))", &problems)
        }
    }

    private static func cachedNameIsALiveLabel() -> [String] {
        // Kind 1 twice, kind 2 once, all asking for "Films".
        Rig.withRig([Spec(seed: 1), Spec(seed: 2), Spec(seed: 1)], reply: { _, _ in Rig.answer("new", "Films") }) { rig, problems in
            // Shadow mode caches kind 1's proposal and makes no label.
            rig.ask(0)
            guard case .proposed(_, _)? = rig.reloaded().book.answers.first?.answer else {
                return problems.append("the proposal was not cached: \(rig.reloaded().book.answers)")
            }
            // Kind 2 proposes the same name with assigning on and is given the label.
            rig.mode.assigns = true
            rig.ask(1)
            let id = rig.assistant.labels.book.labels.first?.id ?? ""
            expect(rig.assistant.labels.book.labels.map(\.name) == ["Films"] && rig.stored(1)?.workType.rawValue == id,
                   "kind 2 was not given a Films label: \(rig.assistant.labels.book.labels.map(\.name))", &problems)
            // A day on the limits allow a make, but the cached proposal for kind 1 finds the name held by a live label.
            rig.f.clock.advance(AILabelConstants.labelWindow + 1)
            rig.ask(2)
            expect(rig.calls.questions.count == 2, "the cached proposal was asked about again: \(rig.calls.questions.count)", &problems)
            expect(rig.assistant.labels.book.labels.map(\.name) == ["Films"],
                   "a second Films was made: \(rig.assistant.labels.book.labels.map(\.name))", &problems)
            expect(rig.stored(2)?.workType.rawValue == id && rig.stored(2)?.categorySource == .ai,
                   "the session was not given the existing Films label: \(String(describing: rig.stored(2)))", &problems)
        }
    }

    private static func cacheHitsDoNotLapse() -> [String] {
        let specs = [Spec(seed: 7), Spec(seed: 7), Spec(seed: 7)]
        return Rig.withRig(specs, reply: { _, _ in Rig.answer("2") }) { rig, problems in
            let day: TimeInterval = 86_400
            rig.ask(0)
            rig.f.clock.advance(80 * day)
            rig.ask(1)
            expect(rig.calls.questions.count == 1, "a cached answer was asked for again at 80 days", &problems)
            expect(rig.reloaded().book.answers.first?.lastUsed == rig.f.clock.value,
                   "a cache hit did not renew the answer: \(String(describing: rig.reloaded().book.answers.first?.lastUsed))", &problems)
            expect(rig.reloaded().book.tally.map(\.recordID) == [rig.records[0].id, rig.records[1].id],
                   "a cache hit was not in the comparison", &problems)
            expect(rig.assistant.suggestions[rig.records[1].id] == .pick(WorkType.meetings.rawValue),
                   "a cache hit was not offered", &problems)
            // 160 days after it was first asked, but 80 after it was last used: still a hit.
            rig.f.clock.advance(80 * day)
            rig.ask(2)
            expect(rig.calls.questions.count == 1, "an answer in use lapsed: asked \(rig.calls.questions.count) times", &problems)
        }
    }
}
