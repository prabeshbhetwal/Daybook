import Foundation

/// What happens to an answer that arrives late (Phase C, ruling C24; Review Focus 2 and 3): everything is
/// checked again when it comes, and a change since the question was put drops it, uncached and unwritten.
enum CategoryAssistantRaceChecks: CheckSuite {
    private typealias Rig = CategoryAssistantRig
    private typealias Spec = CategoryAssistantRig.Spec

    static let tests: [(String, () -> [String])] = [
        ("A record the person touched between its end and the answer is never written, cached or offered", touchedRecordIsLeftAlone),
        ("An answer is dropped when Apple Intelligence went off or a correction now matches", staleAnswersAreDropped),
        ("An answer that finds assigning switched off meanwhile is offered, not written", assigningSwitchedOffMeanwhile),
        ("A question that times out leaves the record alone, is not cached, and the next is asked", timeoutLeavesTheRecord),
    ]

    /// What the person does to the record while the model thinks, and what the archive then says of it.
    private static let touches: [(String, (Rig.Fixture, SessionRecord) -> Void)] = [
        ("renamed", { f, record in _ = f.engine.archive.rename(thread: record.threadID, to: "Mine") }),
        ("recategorised", { f, record in _ = f.engine.archive.setWorkType(.admin, forThread: record.threadID) }),
        ("claimed", { f, record in
            var claimed = record
            claimed.origin = .manual
            claimed.isAuto = false
            _ = f.engine.archive.edit(removing: [record], adding: [claimed])
        }),
        ("cut short by a split", { f, record in
            var cut = record
            cut.end = cut.end.addingTimeInterval(-600)
            _ = f.engine.archive.edit(removing: [record], adding: [cut])
        }),
        ("removed", { f, record in _ = f.engine.archive.edit(removing: [record]) }),
    ]

    @MainActor private static func nothingKept(_ rig: Rig.Rig, _ label: String, _ problems: inout [String]) {
        let book = rig.reloaded().book
        expect(book.answers.isEmpty && book.tally.isEmpty && book.labels.isEmpty,
               "an answer for a record that was \(label) was cached: \(book)", &problems)
        expect(rig.assistant.suggestions.isEmpty, "an answer for a record that was \(label) was offered", &problems)
    }

    private static func touchedRecordIsLeftAlone() -> [String] {
        var problems: [String] = []
        for (label, touch) in touches {
            let hook = Rig.Hook()
            problems += Rig.withRig(reply: { _, _ in hook.run(); return Rig.answer("2") }) { rig, found in
                hook.run = { touch(rig.f, rig.record) }
                rig.mode.assigns = true
                rig.ask()
                expect(rig.calls.questions.count == 1, "the session was not asked about (\(label))", &found)
                if label == "removed" {
                    expect(rig.stored() == nil, "a record the person removed came back", &found)
                } else {
                    expect(rig.stored()?.categorySource != .ai && rig.stored()?.workType != .meetings,
                           "a record that was \(label) was given the AI's pick: \(String(describing: rig.stored()))", &found)
                }
                nothingKept(rig, label, &found)
            }
        }
        return problems
    }

    private static func staleAnswersAreDropped() -> [String] {
        var problems: [String] = []
        let hook = Rig.Hook()
        let specs = [Spec(seed: 1), Spec(seed: 1)]
        // The switch goes off while the model thinks.
        problems += Rig.withRig(reply: { _, _ in hook.run(); return Rig.answer("2") }) { rig, found in
            hook.run = { rig.f.persistence.useAppleIntelligence = false }
            rig.mode.assigns = true
            rig.ask()
            expect(rig.stored() == rig.record, "an answer that came after the switch went off was written", &found)
            nothingKept(rig, "asked before the switch went off", &found)
        }
        // The person files another session of this kind while the model thinks: a remembered correction now
        // matches, and their word beats the model's.
        problems += Rig.withRig(specs, reply: { _, _ in hook.run(); return Rig.answer("2") }) { rig, found in
            hook.run = {
                let other = ActivitySnapshotChecks.daySession([rig.records[1]])
                _ = rig.f.store.setWorkType(.learning, for: other)
            }
            rig.mode.assigns = true
            rig.ask(0)
            expect(rig.stored(0) == rig.record, "an answer was written over a kind of session the person had just filed", &found)
            expect(rig.stored(1)?.workType == .learning && rig.stored(1)?.categorySource == .user,
                   "the person's own filing was lost: \(String(describing: rig.stored(1)))", &found)
            expect(rig.reloaded().book.answers.isEmpty, "an answer that lost to a correction was cached", &found)
        }
        return problems
    }

    private static func assigningSwitchedOffMeanwhile() -> [String] {
        let hook = Rig.Hook()
        return Rig.withRig(reply: { _, _ in hook.run(); return Rig.answer("2") }) { rig, problems in
            hook.run = { rig.mode.assigns = false }
            rig.mode.assigns = true
            rig.ask()
            expect(rig.stored() == rig.record, "an answer was written after assigning was switched off", &problems)
            expect(rig.assistant.suggestions[rig.record.id] == .pick(WorkType.meetings.rawValue),
                   "the answer was not left on offer: \(rig.assistant.suggestions)", &problems)
        }
    }

    private static func timeoutLeavesTheRecord() -> [String] {
        Rig.withRig([Spec(seed: 1), Spec(seed: 2)], reply: { count, _ in
            // The first never answers in time, and ignores being told to stop.
            if count == 1 { await NameSuggesterChecks.pause(0.4) }
            return Rig.answer("2")
        }) { rig, problems in
            rig.assistant.timeout = .milliseconds(40)
            rig.mode.assigns = true
            rig.ask(0, wait: 0.6)
            expect(rig.stored(0) == rig.record, "a record was written by a question that timed out", &problems)
            expect(rig.reloaded().book.answers.isEmpty && rig.assistant.suggestions.isEmpty,
                   "a question that timed out was cached or offered", &problems)
            rig.assistant.timeout = .seconds(5)
            rig.ask(1)
            expect(rig.calls.questions.count == 2 && rig.stored(1)?.categorySource == .ai,
                   "the question after a timeout was not asked and written: \(rig.calls.questions.count)", &problems)
        }
    }
}
