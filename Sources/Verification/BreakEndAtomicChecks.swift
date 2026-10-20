import Foundation

/// A break ends in one archive edit with the stretch it paused, so a kill
/// leaves both on record or neither: the break is recorded whole, or was
/// under the shortest recorded session and is not live again. Also the
/// journalled ending, and a refusal that a retry before a break outlives.
enum BreakEndAtomicChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A break ended just before a kill is recorded whole, or not at all if under the minimum", endKillWindow),
        ("A break that ran out its cap just before a kill is recorded with its stretch", expiryKillWindow),
        ("A break ended through the correction journal stays ended after a kill", journalledEndKillWindow),
        ("A refused ending of a stale session does not outlive a retry before a break", retryClearsRefusal),
    ]

    /// How many archive edits are still accepted; past that the archive turns
    /// every write away, as a process that has been killed does.
    private final class Budget {
        var left = Int.max
    }

    private static func budgetedEngine(_ clock: TestClock, _ budget: Budget) -> SessionEngine {
        let store = PersistenceStore(defaults: MemoryDefaults.suite(named: SelfTest.suiteName) ?? .standard)
        store.removeAll()
        let archive = SessionArchive(directory: SelfTest.scratchDirectory(), now: { clock.value },
                                     writeOverride: { _ in
            guard budget.left > 0 else { return "The process was killed." }
            budget.left -= 1
            return nil
        })
        return SessionEngine(store: store, archive: archive, ownBundleID: FocusConstants.bundleIdentifier,
                             schedulesDwell: false, now: { clock.value })
    }

    private static func endKillWindow() -> [String] {
        var problems: [String] = []
        let cases: [(length: TimeInterval, recorded: Int)] = [(120, 1), (45, 1), (20, 0)]
        for (length, recorded) in cases {
            let clock = TestClock(SelfTest.base)
            let budget = Budget()
            let engine = budgetedEngine(clock, budget)
            engine.start(workType: .deepWork, intent: "Parser"); clock.advance(600)
            engine.startBreak(length: 300)
            let beforeEnd = engine.snapshot()
            clock.advance(length)
            // One write is all the process gets: the state is never saved.
            budget.left = 1
            engine.endBreak()
            budget.left = 0
            for (when, delay) in [("ten seconds later", 10.0), ("past its cap", 300 + engine.store.longAwayCap)] {
                clock.advance(delay)
                let back = BreakTakingChecks.relaunched(engine, clock)
                back.restore(from: beforeEnd)
                expect(back.activeBreak == nil && back.state == .idle,
                       "\(Int(length)) s, \(when): no live break, got \(back.state)", &problems)
                expect(BreakTakingChecks.breaks(in: back).count == recorded
                       && BreakTakingChecks.stretches(in: back).count == 1,
                       "\(Int(length)) s, \(when): \(recorded) break and one stretch on record, got "
                       + "\(BreakTakingChecks.breaks(in: back).count) and \(BreakTakingChecks.stretches(in: back).count)",
                       &problems)
            }
        }

        // A write that is refused lands neither, the break stays live, and the
        // retry records the length it really had.
        let clock = TestClock(SelfTest.base)
        let budget = Budget()
        let engine = budgetedEngine(clock, budget)
        engine.start(workType: .deepWork, intent: "Parser"); clock.advance(600)
        engine.startBreak(length: 300)
        clock.advance(120)
        budget.left = 0
        expect(engine.endBreak() == nil && engine.activeBreak != nil && engine.archive.records.isEmpty,
               "a refused end leaves the break live and nothing on record", &problems)
        budget.left = Int.max
        clock.advance(60)
        expect(engine.endBreak() != nil && BreakTakingChecks.near(BreakTakingChecks.breaks(in: engine).first?.workSeconds, 180)
               && BreakTakingChecks.stretches(in: engine).count == 1,
               "and the retry records the whole 180 s once", &problems)
        return problems
    }

    private static func expiryKillWindow() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        let budget = Budget()
        let engine = budgetedEngine(clock, budget)
        let cap = engine.store.longAwayCap
        engine.start(workType: .deepWork, intent: "Parser"); clock.advance(600)
        engine.startBreak(length: 300)
        let beforeEnd = engine.snapshot()
        clock.advance(300 + cap + 60)
        budget.left = 1
        expect(engine.expireBreakIfOutgrown() != nil, "setup: the cap ends the break", &problems)
        budget.left = 0
        let onDisk = BreakTakingChecks.relaunched(engine, clock)
        expect(BreakTakingChecks.breaks(in: onDisk).count == 1 && BreakTakingChecks.stretches(in: onDisk).count == 1,
               "one write left the break and its stretch on record", &problems)
        onDisk.restore(from: beforeEnd)
        expect(onDisk.activeBreak == nil && onDisk.state == .idle
               && BreakTakingChecks.breaks(in: onDisk).count == 1,
               "and a relaunch from the older state adds nothing, got \(onDisk.state)", &problems)
        return problems
    }

    private static func journalledEndKillWindow() -> [String] {
        var problems: [String] = []
        let cases: [(session: TimeInterval, length: TimeInterval, recorded: Int)] = [(600, 20, 0), (600, 300, 1), (10, 20, 0)]
        for (session, length, recorded) in cases {
            let clock = TestClock(SelfTest.base)
            let engine = SelfTest.makeEngine(clock)
            engine.start(workType: .deepWork, intent: "Parser"); clock.advance(session)
            expect(engine.commitCorrection(before: engine.snapshot()), "setup: the history is not empty", &problems)
            engine.startBreak(length: 300)
            let beforeEnd = engine.snapshot()
            clock.advance(length)
            engine.endBreak()
            let back = BreakTakingChecks.relaunched(engine, clock)
            back.restore(from: beforeEnd)
            expect(back.activeBreak == nil && back.state == .idle,
                   "a \(Int(length)) s break after \(Int(session)) s of work is not live again, got \(back.state)",
                   &problems)
            expect(BreakTakingChecks.breaks(in: back).count == recorded,
                   "and \(recorded) break is on record, got \(BreakTakingChecks.breaks(in: back).count)", &problems)
        }
        return problems
    }

    private static func retryClearsRefusal() -> [String] {
        var problems: [String] = []
        var refuses = false
        let clock = TestClock(SelfTest.base)
        let engine = BreakTakingChecks.gatedEngine(clock, refuses: { refuses })
        engine.start(workType: .deepWork, intent: "Parser"); clock.advance(600)
        engine.transition(on: .manualPause)
        clock.advance(engine.store.longAwayCap + 3_600)
        refuses = true
        engine.startBreak(length: 300)
        var refused = false
        if case .refused? = engine.lastLongAwayTransition?.outcome { refused = true }
        expect(refused && engine.activeBreak == nil && engine.state == .paused(reason: .manual),
               "setup: the first try is refused and the pause stands", &problems)
        refuses = false
        expect(engine.startBreak(length: 300), "the retry begins the break", &problems)
        expect(engine.lastLongAwayTransition?.outcome == .completed && engine.state == .idle,
               "and the refusal is not carried into its result, got "
               + "\(String(describing: engine.lastLongAwayTransition?.outcome))", &problems)
        return problems
    }
}
