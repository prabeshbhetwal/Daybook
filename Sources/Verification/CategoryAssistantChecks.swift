import Foundation

/// When the on-device model is asked about an ended automatic session and what becomes of its answer
/// (Phase C, Task 3): the gates, the trigger, shadow mode, assigning, and the sweep that tells the
/// assistant a session has ended. Every check drives a responder; none reaches the live model.
enum CategoryAssistantChecks: CheckSuite {
    private typealias Rig = CategoryAssistantRig
    private typealias Spec = CategoryAssistantRig.Spec

    static let tests: [(String, () -> [String])] = [
        ("No question is asked while Apple Intelligence is off, in Low Power Mode or under thermal pressure", gatesStopTheQuestion),
        ("A session that is clear, short, filed by a rule or already corrected is not asked about", quietSessionsAreNotAsked),
        ("In shadow mode the answer is cached and offered, and the record is untouched", shadowOffersOnly),
        ("With assigning on, a pick is written as the AI's and is not an undo step", assigningWritesThePick),
        ("An answer naming the category the session already has changes and offers nothing", sameCategoryIsNothing),
        ("The sweep tells the assistant of a session that ended, once, and of none that was there at launch", sweepTellsTheAssistant),
    ]

    private static func gatesStopTheQuestion() -> [String] {
        Rig.withRig { rig, problems in
            @MainActor func stops(_ why: String) {
                rig.ask(wait: 0.05)
                expect(rig.calls.questions.isEmpty, "a question was asked \(why)", &problems)
            }
            rig.f.persistence.useAppleIntelligence = false
            stops("with Apple Intelligence off")
            rig.f.persistence.useAppleIntelligence = true
            rig.assistant.lowPower = { true }
            stops("in Low Power Mode")
            rig.assistant.lowPower = { false }
            rig.assistant.thermalSerious = { true }
            stops("under thermal pressure")
            // A session that ended while gated is never asked later: nothing waits for the gate to open.
            rig.assistant.thermalSerious = { false }
            rig.settle(0.05)
            expect(rig.calls.questions.isEmpty, "a session that ended while gated was asked once the gate opened", &problems)
            rig.ask()
            expect(rig.calls.questions.count == 1, "with every gate open the question was not asked", &problems)
        }
    }

    private static func quietSessionsAreNotAsked() -> [String] {
        var clear = Spec(seed: 1), short = Spec(seed: 2), ruled = Spec(seed: 3), corrected = Spec(seed: 4)
        clear.credited = [.coding: 1_700, .research: 100]
        short.counted = 500
        ruled.source = .rule
        corrected.name = "Corrected"
        let specs = [clear, short, ruled, corrected, Spec(seed: 5)]
        return Rig.withRig(specs, prepare: { f in
            // The person already told Daybook how they file this kind of session.
            _ = CorrectionsStore(directory: f.engine.archive.dataDirectoryURL)
                .record(fingerprint: AIFixture.fingerprint(4), chosen: "learning", vetoed: nil, at: SelfTest.base)
        }) { rig, problems in
            for index in 0..<4 { rig.ask(index) }
            expect(rig.calls.questions.isEmpty,
                   "a clear, short, rule-filed or corrected session was asked about: \(rig.calls.questions.count)", &problems)
            rig.ask(4)
            expect(rig.calls.questions.count == 1, "the unclear session beside them was not asked", &problems)
        }
    }

    private static func shadowOffersOnly() -> [String] {
        Rig.withRig(reply: { _, _ in Rig.answer("2") }) { rig, problems in
            let before = rig.stored()
            rig.ask()
            expect(rig.calls.questions.count == 1, "the session was asked about \(rig.calls.questions.count) times", &problems)
            expect(rig.calls.questions.first?.text.contains("2. Meetings") == true,
                   "the question did not number the person's categories: \(rig.calls.questions.first?.text ?? "none")", &problems)
            expect(rig.stored() == before, "shadow mode changed the record: \(String(describing: rig.stored()))", &problems)
            expect(rig.assistant.suggestions[rig.record.id] == .pick(WorkType.meetings.rawValue),
                   "the answer was not on offer: \(rig.assistant.suggestions)", &problems)
            let kept = rig.reloaded().book
            expect(kept.answers.map(\.answer) == [.pick(WorkType.meetings.rawValue)],
                   "the answer was not cached in the file: \(kept.answers)", &problems)
            expect(kept.tally == [TallyEntry(recordID: rig.record.id, answerID: WorkType.meetings.rawValue, chosen: nil)],
                   "the comparison was not begun: \(kept.tally)", &problems)
            expect(rig.f.store.lastCorrection == nil, "an offer was put on the undo list", &problems)
        }
    }

    private static func assigningWritesThePick() -> [String] {
        Rig.withRig(reply: { _, _ in Rig.answer("2") }) { rig, problems in
            rig.mode.assigns = true
            rig.ask()
            var expected = rig.record
            expected.workType = .meetings
            expected.categorySource = .ai
            expect(rig.stored() == expected,
                   "the record was not the AI's pick and nothing else: \(String(describing: rig.stored()))", &problems)
            expect(rig.f.store.lastCorrection == nil && !rig.f.store.canUndoCorrection,
                   "an AI write was put on the undo list", &problems)
            expect(rig.assistant.suggestions.isEmpty, "a written pick was still on offer: \(rig.assistant.suggestions)", &problems)
            expect(rig.reloaded().book.tally.map(\.answerID) == [WorkType.meetings.rawValue],
                   "the written pick was not in the comparison", &problems)
        }
    }

    private static func sameCategoryIsNothing() -> [String] {
        Rig.withRig(reply: { _, _ in Rig.answer("1") }) { rig, problems in
            rig.mode.assigns = true
            let before = rig.stored()
            rig.ask()
            expect(rig.calls.questions.count == 1, "the session was not asked about", &problems)
            expect(rig.stored() == before, "the category it already had was written again: \(String(describing: rig.stored()))", &problems)
            expect(rig.assistant.suggestions.isEmpty, "the category it already had was offered", &problems)
            expect(rig.reloaded().book.answers.map(\.answer) == [.pick(WorkType.deepWork.rawValue)],
                   "the answer was not cached", &problems)
        }
    }

    private static func sweepTellsTheAssistant() -> [String] {
        Rig.withRig([Spec(seed: 1), Spec(seed: 2)], reply: { _, _ in Rig.answer("none") }) { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            // The first pass of a launch only notes what is there: nothing recorded before is ever asked about.
            rig.f.store.writeActivitySnapshots()
            rig.settle(0.05)
            expect(rig.calls.questions.isEmpty, "a session from before the launch was asked about", &problems)
            let start = rig.f.clock.value
            let later = SessionRecord(name: "Later", workType: .deepWork, start: start, end: start.addingTimeInterval(1_800),
                                      workSeconds: 1_800, isAuto: true, origin: .automatic, categorySource: .builtIn)
            let fresh = Rig.shape(for: later, Spec(seed: 3))
            expect(rig.f.engine.archive.append(later) == nil && rig.f.metadata.saveActivityShape(fresh, for: later.id) == .saved,
                   "the later session was not recorded", &problems)
            rig.f.clock.advance(3_600)
            rig.f.store.writeActivitySnapshots()
            rig.settle()
            expect(rig.calls.questions.count == 1, "the session that ended was asked about \(rig.calls.questions.count) times", &problems)
            rig.f.store.writeActivitySnapshots()
            rig.settle(0.05)
            expect(rig.calls.questions.count == 1, "a later sweep asked about it again", &problems)
        }
    }
}
