import Foundation

/// A reminder counts as said only once it reached the screen, and an end the
/// disk refused is tried again on the store's own five-second gate.
extension BreakSeamChecks {
    static func unseenReminderIsAskedAgain() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []

            // Refused once (the screen was out of reach), accepted the next time.
            guard let f = BreakStoreChecks.makeDue() else { return ["could not create isolated preferences"] }
            defer { f.close() }
            var shown: [BreakPrompt] = []
            f.store.onBreakDue = { _ in false }
            f.store.refresh()
            expect(f.persistence.lastBreakNotice == nil, "a refused reminder is not written down as said", &problems)
            f.store.onBreakDue = { shown.append($0); return true }
            f.clock.advance(5)
            f.store.refresh()
            expect(shown.count == 1 && shown.first?.tier == .cognitive,
                   "the reminder is shown the next time it can be, got \(shown.count)", &problems)
            expect(f.persistence.lastBreakNotice?.tier == .cognitive, "and only now is it written down", &problems)
            f.clock.advance(5)
            f.store.refresh()
            expect(shown.count == 1, "and then it is not repeated", &problems)

            // Launch: the first refresh runs before the coordinator has wired the callback.
            guard let g = BreakStoreChecks.makeDue() else {
                return problems + ["could not create isolated preferences"]
            }
            defer { g.close() }
            var wired: [BreakPrompt] = []
            g.store.refresh()
            expect(g.persistence.lastBreakNotice == nil, "with no callback yet nothing is written down", &problems)
            g.store.onBreakDue = { wired.append($0); return true }
            g.store.refresh()
            expect(wired.count == 1, "the reminder comes once the callback exists, got \(wired.count)", &problems)

            // A Later that runs out while the reminder cannot reach the screen.
            guard let h = BreakStoreChecks.make() else {
                return problems + ["could not create isolated preferences"]
            }
            defer { h.close() }
            var seen: [BreakPrompt] = []
            h.store.onBreakDue = { seen.append($0); return true }
            h.work(0, 55); h.go(toMinute: 55); h.store.refresh()
            guard let first = seen.first else { return problems + ["no first reminder"] }
            h.store.laterBreak(first)
            h.work(55, 66); h.go(toMinute: 66)
            h.store.onBreakDue = { _ in false }
            h.store.refresh()
            h.store.onBreakDue = { seen.append($0); return true }
            h.go(toMinute: 67)
            h.work(66, 67)
            h.store.refresh()
            expect(seen.count == 2, "a Later that ran out unseen comes back once it can, got \(seen.count)", &problems)
            return problems
        }
    }

    static func sustainedEndRetriesOnTheGate() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let f = BreakStoreChecks.make(prepare: BreakStoreChecks.running) else {
                return ["could not create isolated preferences"]
            }
            defer { f.close() }
            f.store.startBreak(length: 300)
            f.clock.advance(300)
            f.gate.refuses = true
            f.idle.value = 0
            for _ in 0..<60 { f.store.runTick(); f.clock.advance(1) }
            let perTry = f.gate.attempts
            expect(perTry > 0 && f.store.isOnBreak, "setup: the first minute of input met the window and was refused",
                   &problems)
            for _ in 0..<30 { f.store.runTick(); f.clock.advance(1) }
            let tries = perTry > 0 ? f.gate.attempts / perTry : 0
            expect((7...8).contains(tries),
                   "thirty more seconds make six more tries on the five-second gate, got \(tries - 1)", &problems)

            f.gate.refuses = false
            for _ in 0..<6 { f.store.runTick(); f.clock.advance(1) }
            expect(!f.store.isOnBreak && f.store.correctionError == nil,
                   "and the break ends on the next try once the disk works", &problems)
            return problems
        }
    }
}
