import Foundation

/// Four carry-overs from phase 1 in how a break meets session state: a break
/// taken on a pause left past the cap, a break too short to be recorded and
/// killed while it ended, a correction's checkpoint, and where recording starts
/// again after input ended a break.
enum BreakRestoreCarryOverChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Take a break on a pause past the cap ends that session first", pastCapPauseEndsFirst),
        ("A break under 30 seconds stays ended after a kill", shortBreakStaysEnded),
        ("A correction does not bring back a break restore would drop", correctionFiltersBreak),
        ("Recording resumes where the input that ended a break began", trackingResumesAtBackdatedStart),
    ]

    private static func pastCapPauseEndsFirst() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        let engine = SelfTest.makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Parser"); clock.advance(600)
        engine.transition(on: .manualPause)
        let pausedAt = clock.value
        clock.advance(engine.store.longAwayCap + 3_600)
        expect(engine.state == .paused(reason: .manual) && engine.canStartBreak,
               "setup: a pause left past the cap still offers a break, got \(engine.state)", &problems)
        expect(engine.startBreak(length: 300), "the break begins", &problems)
        expect(engine.state == .idle && engine.activeBreak != nil,
               "it pauses no session: the old one ended, got \(engine.state)", &problems)
        expect(engine.lastLongAwayTransition?.outcome == .completed,
               "and the long absence's result stays for the store to show", &problems)
        clock.advance(300)
        engine.endBreak()
        let stretches = BreakTakingChecks.stretches(in: engine)
        expect(stretches.count == 1 && stretches.first?.end == pausedAt
               && BreakTakingChecks.near(stretches.first?.workSeconds, 600),
               "the session ended where the person left, once", &problems)
        expect(BreakTakingChecks.breaks(in: engine).count == 1, "the break is recorded once", &problems)
        expect(engine.state == .idle && engine.activeBreak == nil,
               "and ending it starts no session, got \(engine.state)", &problems)
        return problems
    }

    private static func shortBreakStaysEnded() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        let engine = SelfTest.makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Parser"); clock.advance(600)
        engine.startBreak(length: 300)
        // What was saved when the kill came: the stretch is on record, the
        // state that says the break ended is not.
        let beforeEnd = engine.snapshot()
        clock.advance(20)
        engine.endBreak()
        expect(BreakTakingChecks.breaks(in: engine).isEmpty, "setup: twenty seconds is not written down", &problems)
        let back = BreakTakingChecks.relaunched(engine, clock)
        back.restore(from: beforeEnd)
        expect(back.activeBreak == nil && back.state == .idle,
               "the break does not come back live, got \(back.state)", &problems)
        expect(back.store.loadState()?.activeBreak == nil && BreakTakingChecks.breaks(in: back).isEmpty,
               "and nothing of it is saved or recorded", &problems)

        // Left until past its own cap, it is the cap that ends it, as before.
        let cap = engine.store.longAwayCap
        clock.advance(300 + cap)
        let late = BreakTakingChecks.relaunched(engine, clock)
        late.restore(from: beforeEnd)
        expect(late.activeBreak == nil && BreakTakingChecks.breaks(in: late).count == 1,
               "found past its cap it is recorded there, once", &problems)
        return problems
    }

    private static func correctionFiltersBreak() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        let source = SelfTest.makeEngine(clock)
        source.start(workType: .deepWork, intent: "Parser"); clock.advance(600)
        source.startBreak(length: 300)
        guard let real = source.activeBreak else { return ["the break should have started"] }

        // A checkpoint taken with a break no one could have taken.
        source.activeBreak = ActiveBreak(id: real.id, start: real.start,
                                         plannedEnd: real.start.addingTimeInterval(1e9), threadID: real.threadID)
        expect(source.commitCorrection(before: source.snapshot()), "setup: the correction commits", &problems)
        let damaged = BreakTakingChecks.relaunched(source, clock)
        expect(!damaged.prepareCorrection(), "the newer checkpoint is loaded", &problems)
        expect(damaged.activeBreak == nil && damaged.state == .paused(reason: .manual),
               "without a break restore would drop, got \(String(describing: damaged.activeBreak))", &problems)

        // One taken with a real break that has since been ended and recorded.
        source.activeBreak = real
        expect(source.commitCorrection(before: source.snapshot()), "setup: a second correction commits", &problems)
        clock.advance(400)
        source.endBreak()
        let ended = BreakTakingChecks.relaunched(source, clock)
        expect(!ended.prepareCorrection() && BreakTakingChecks.breaks(in: ended).count == 1,
               "setup: the checkpoint is loaded and the break is on record", &problems)
        expect(ended.activeBreak == nil, "nor one already on record is live again", &problems)
        return problems
    }

    private static func trackingResumesAtBackdatedStart() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let f = BreakStoreChecks.make(prepare: BreakStoreChecks.running) else {
                return ["could not create isolated preferences"]
            }
            defer { f.close() }
            let tracker = BreakSeamChecks.trackerOn(f)
            f.front.value = ("com.safari", "Safari")
            f.store.startBreak(length: 300)
            f.clock.advance(300)
            // Fifteen seconds of input, a quiet fifteen, then forty-five more:
            // sixty active seconds in all, and the first of them 75 s back.
            for second in 0..<75 {
                f.idle.value = (15..<30).contains(second) ? 600 : 0
                f.store.runTick()
                f.clock.advance(1)
            }
            guard let ended = f.engine.lastEndedBreak, !f.store.isOnBreak else {
                return problems + ["setup: sustained input should have ended the break"]
            }
            expect(f.clock.value.timeIntervalSince(ended.end) >= 74, "setup: the end is backdated", &problems)
            f.clock.advance(60)
            tracker.flush()
            let first = f.usage.sessions.filter { $0.bundleID == "com.safari" }.min { $0.start < $1.start }
            expect(first?.start == ended.end,
                   "use is recorded from the input's start, not from the end of the break, got "
                   + "\(String(describing: first?.start.timeIntervalSince(ended.end)))", &problems)
            return problems
        }
    }
}
