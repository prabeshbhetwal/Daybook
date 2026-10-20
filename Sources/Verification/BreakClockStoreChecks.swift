import Foundation

/// The reminder clock as the store uses it: read from the saved copy,
/// changed by Later and Skip, and written back. What the clock holds beside
/// the floors and the Later (the credited rests) must survive each of those,
/// and a damaged Later count must not change how often a break can be put off.
enum BreakClockStoreChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A damaged Later count gives two Laters, not more", damagedCountGivesTwoLaters),
        ("The store keeps the credited rests when it rewrites the reminder clock", storeKeepsCredits),
    ]

    private static func at(_ minutes: Double) -> Date { SelfTest.base.addingTimeInterval(minutes * 60) }

    private static func damagedCountGivesTwoLaters() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            var direct = BreakClock()
            direct.snooze = BreakSnooze(tier: .cognitive, until: at(10), count: -3)
            direct.later(.cognitive, at: at(0))
            expect(direct.snooze?.count == 1, "a Later on a count of -3 is the first, got "
                   + "\(String(describing: direct.snooze?.count))", &problems)

            guard let f = BreakStoreChecks.make() else { return ["could not create isolated preferences"] }
            defer { f.close() }
            var shown: [BreakPrompt] = []
            f.store.onBreakDue = { shown.append($0); return true }
            // A Later for the break due now, saved with a count that cannot be true.
            f.work(0, 55); f.go(toMinute: 55)
            var stored = BreakClock()
            stored.later(.cognitive, at: at(55))
            stored.snooze?.count = -3
            f.persistence.breakClock = stored

            var accepted = 0
            var minute = 55.0
            for _ in 0..<8 {
                let before = shown.count
                f.work(minute, minute + 10); minute += 10; f.go(toMinute: minute); f.store.refresh()
                guard shown.count == before + 1, let prompt = shown.last, prompt.canLater else { break }
                f.store.laterBreak(prompt)
                accepted += 1
            }
            expect(accepted == BreakClock.maxLaters,
                   "a break may be put off twice whatever was saved, got \(accepted)", &problems)
            expect(shown.last?.canLater == false, "and the next showing may not be", &problems)
            return problems
        }
    }

    private static func storeKeepsCredits() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let rest = [at(0)]

            // A Later that the evaluation drops is cleared from the saved clock.
            guard let f = BreakStoreChecks.make() else { return ["could not create isolated preferences"] }
            defer { f.close() }
            f.store.onBreakDue = { _ in true }
            f.work(0, 30); f.go(toMinute: 30)
            var stale = BreakClock()
            stale.credit(at: at(0))
            stale.later(.cognitive, at: at(25))
            f.persistence.breakClock = stale
            f.store.refresh()
            expect(f.persistence.breakClock.snooze == nil,
                   "a Later for a break that is not due is dropped from the saved clock", &problems)
            expect(f.persistence.breakClock.credits == rest,
                   "and the credited rest stays, got \(f.persistence.breakClock.credits.count)", &problems)

            // Later and Skip on a due break.
            guard let g = BreakStoreChecks.make() else { return problems + ["could not create isolated preferences"] }
            defer { g.close() }
            var shown: [BreakPrompt] = []
            g.store.onBreakDue = { shown.append($0); return true }
            var credited = BreakClock()
            credited.credit(at: at(0))
            g.persistence.breakClock = credited
            g.work(0, 55); g.go(toMinute: 55); g.store.refresh()
            guard let first = shown.last else { return problems + ["no reminder was due"] }
            g.store.laterBreak(first)
            expect(g.persistence.breakClock.snooze?.count == 1 && g.persistence.breakClock.credits == rest,
                   "a Later keeps the credited rest", &problems)
            g.work(55, 65); g.go(toMinute: 65); g.store.refresh()
            guard shown.count == 2, let second = shown.last else { return problems + ["no second reminder"] }
            g.store.skipBreak(second)
            expect(g.persistence.breakClock.floors[.cognitive] == at(65) && g.persistence.breakClock.credits == rest,
                   "and so does a Skip", &problems)
            return problems
        }
    }
}
