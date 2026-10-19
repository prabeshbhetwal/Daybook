import Foundation

/// Breaks the person takes on purpose: where each rest on record came from,
/// and the records the feature leaves behind.
enum BreakTakingChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A break record written before origins existed still reads", oldRecordDecodes),
        ("Away, Watching and answered breaks say where they came from", restsAreTagged),
    ]

    private static func oldRecordDecodes() -> [String] {
        var problems: [String] = []
        let record = SessionRecord(name: "Break", workType: .breakTime,
                                   start: SelfTest.base, end: SelfTest.base.addingTimeInterval(300),
                                   workSeconds: 300, breakOrigin: .started, plannedLength: 300)
        guard let data = try? JSONEncoder().encode(record) else {
            return ["a record should encode"]
        }
        let roundTripped = try? JSONDecoder().decode(SessionRecord.self, from: data)
        expect(roundTripped?.breakOrigin == .started && roundTripped?.plannedLength == 300,
               "fields round-trip", &problems)

        guard var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return problems + ["the record should encode as an object"]
        }
        json.removeValue(forKey: "breakOrigin")
        json.removeValue(forKey: "plannedLength")
        guard let stripped = try? JSONSerialization.data(withJSONObject: json),
              let decoded = try? JSONDecoder().decode(SessionRecord.self, from: stripped) else {
            return problems + ["a record without the origin fields should still decode"]
        }
        expect(decoded.breakOrigin == nil && decoded.plannedLength == nil,
               "absent fields read as nil", &problems)
        return problems
    }

    private static func restsAreTagged() -> [String] {
        var problems: [String] = []

        // Declared away past the break threshold, then back to work.
        let awayClock = TestClock(SelfTest.base)
        let away = SelfTest.makeEngine(awayClock)
        away.start(workType: .deepWork, intent: "Parser")
        awayClock.advance(5 * 60)
        away.transition(on: .markedAway)
        awayClock.advance(40 * 60)
        away.transition(on: .manualResume)
        let declared = away.archive.records.first { $0.name == "Away" }
        expect(declared?.breakOrigin == .away, "declared away is .away", &problems)

        // An idle absence, answered "It was a break".
        let askClock = TestClock(SelfTest.base)
        let asked = SelfTest.makeEngine(askClock)
        asked.start(workType: .deepWork, intent: "Parser")
        askClock.advance(30 * 60)
        asked.transition(on: .awayBegan(trigger: .screenLock))
        askClock.advance(33 * 60)
        asked.transition(on: .awayEnded)
        asked.transition(on: .decision(.tookBreak))
        let answered = asked.archive.records.first { $0.workType == .breakTime }
        expect(answered?.breakOrigin == .answered, "answered break is .answered", &problems)

        // Undo, then answering "It was a break" again, is the same answer.
        if asked.undoAwayDecision(), asked.reviseAwayDecision(.tookBreak) {
            let revised = asked.archive.records.first { $0.workType == .breakTime }
            expect(revised?.breakOrigin == .answered,
                   "a break re-answered after Undo is .answered", &problems)
        } else {
            problems.append("Undo then re-answering as a break should save")
        }

        // Behind a film for longer than the break threshold.
        let watchClock = TestClock(SelfTest.base)
        let watch = SelfTest.makeEngine(watchClock)
        watch.breakThreshold = 5 * 60
        watch.start(workType: .deepWork, intent: "Parser")
        watchClock.advance(30 * 60)
        watch.transition(on: .watchingObserved(seconds: 600))
        watchClock.advance(35 * 60)
        watch.transition(on: .watchingObserved(seconds: 45 * 60))
        watch.transition(on: .idleObserved(seconds: 2))
        let watching = watch.archive.records.first { $0.name == "Watching" }
        expect(watching?.breakOrigin == .watching, "watching is .watching", &problems)
        return problems
    }
}
