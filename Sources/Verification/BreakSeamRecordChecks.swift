import Foundation

/// What a stored record or a saved snapshot may hold: a value from a later
/// build, a break that could not have been taken, and who ended a break.
extension BreakSeamChecks {
    static func futureOriginKeepsRecord() -> [String] {
        var problems: [String] = []
        let started = SessionRecord(name: "Break", workType: .breakTime, start: SelfTest.base,
                                    end: SelfTest.base.addingTimeInterval(600), workSeconds: 600,
                                    breakOrigin: .started, plannedLength: 300)
        let answered = SessionRecord(name: "Lunch", workType: .breakTime,
                                     start: SelfTest.base.addingTimeInterval(900),
                                     end: SelfTest.base.addingTimeInterval(1_800), workSeconds: 900,
                                     breakOrigin: .answered)
        do {
            let data = try JSONEncoder().encode([started, answered])
            let text = String(decoding: data, as: UTF8.self)
            guard text.contains("\"started\"") else { return ["the origin is not stored as its name"] }
            // A value the next build adds, read by this one.
            let later = Data(text.replacingOccurrences(of: "\"started\"", with: "\"someFutureValue\"").utf8)
            let back = try JSONDecoder().decode([SessionRecord].self, from: later)
            expect(back.count == 2, "both records survive, got \(back.count)", &problems)
            var unknown = started
            unknown.breakOrigin = nil
            expect(back.first == unknown, "the record keeps every other field, with no origin", &problems)
            expect(back.last == answered, "and its neighbour is untouched", &problems)
        } catch {
            problems.append("a record from a later build made the whole list unreadable: \(error)")
        }
        return problems
    }

    static func impossibleBreakIsNotRestored() -> [String] {
        var problems: [String] = []
        /// A relaunch from a snapshot whose break is `edit`ed after it was saved.
        func relaunch(_ edit: (Date) -> (start: Date, end: Date)) -> SessionEngine? {
            let clock = TestClock(SelfTest.base)
            let engine = SelfTest.makeEngine(clock)
            engine.start(workType: .deepWork, intent: "Parser"); clock.advance(600)
            engine.startBreak(length: 300)
            var saved = engine.snapshot()
            guard let brk = saved.activeBreak else { return nil }
            let dates = edit(brk.start)
            saved.activeBreak = ActiveBreak(id: brk.id, start: dates.start, plannedEnd: dates.end,
                                            threadID: brk.threadID)
            clock.advance(100)
            let restored = BreakTakingChecks.relaunched(engine, clock)
            restored.restore(from: saved)
            return restored
        }
        let impossible: [(String, (Date) -> (start: Date, end: Date))] = [
            ("a planned end 1e300 s away", { ($0, $0.addingTimeInterval(1e300)) }),
            ("one that is not a number", { ($0, Date(timeIntervalSinceReferenceDate: .nan)) }),
            ("one at infinity", { ($0, Date(timeIntervalSinceReferenceDate: .infinity)) }),
            ("a start that is not a number", { _ in
                (Date(timeIntervalSinceReferenceDate: .nan), SelfTest.base) }),
            ("an end before the start", { ($0, $0.addingTimeInterval(-60)) }),
            ("a plan longer than a day", { ($0, $0.addingTimeInterval(BreakLength.maximum + 60)) }),
        ]
        for (name, edit) in impossible {
            guard let restored = relaunch(edit) else { return problems + ["no break was saved"] }
            expect(restored.activeBreak == nil && restored.state == .paused(reason: .manual),
                   "\(name) is not a live break, got \(restored.state)", &problems)
        }
        // The longest plan there is still a break.
        guard let longest = relaunch({ ($0, $0.addingTimeInterval(BreakLength.maximum)) }) else {
            return problems + ["no break was saved"]
        }
        expect(longest.activeBreak != nil && longest.state == .paused(reason: .onBreak),
               "a plan of exactly a day is kept", &problems)
        return problems
    }

    static func countdownIsTotal() -> [String] {
        var problems: [String] = []
        // None of these may trap converting to a whole number of minutes.
        for value: TimeInterval in [1e300, -1e300, .infinity, -.infinity, .nan] {
            let said = [BreakCountdown.text(remaining: value), BreakCountdown.cardText(remaining: value),
                        BreakCountdown.spoken(remaining: value)]
            expect(said.allSatisfy { !$0.isEmpty }, "\(value) gave an empty text", &problems)
        }
        return problems
    }

    static func breakEndKnowsWhoEndedIt() -> [String] {
        var problems: [String] = []
        func onBreak() -> (SessionEngine, TestClock) {
            let clock = TestClock(SelfTest.base)
            let engine = SelfTest.makeEngine(clock)
            engine.start(workType: .deepWork, intent: "Parser"); clock.advance(600)
            engine.startBreak(length: 300)
            return (engine, clock)
        }
        let (pressed, pressedClock) = onBreak()
        pressedClock.advance(100)
        pressed.endBreak()
        expect(pressed.lastEndedBreak?.byPerson == true, "End break is the person's", &problems)

        let (undone, undoneClock) = onBreak()
        undoneClock.advance(100)
        undone.discard()
        expect(undone.lastEndedBreak?.byPerson == true, "so is undoing the session it paused", &problems)

        let (forgotten, forgottenClock) = onBreak()
        forgottenClock.advance(300 + forgotten.store.longAwayCap)
        _ = forgotten.expireBreakIfOutgrown()
        expect(forgotten.lastEndedBreak != nil && forgotten.lastEndedBreak?.byPerson == false,
               "the cap is not: nobody pressed anything", &problems)

        let (closed, closedClock) = onBreak()
        let saved = closed.snapshot()
        closedClock.advance(300 + closed.store.longAwayCap + 7_200)
        let relaunched = BreakTakingChecks.relaunched(closed, closedClock)
        relaunched.restore(from: saved)
        expect(relaunched.lastEndedBreak != nil && relaunched.lastEndedBreak?.byPerson == false,
               "nor is a break found past its cap at launch", &problems)
        return problems
    }
}
