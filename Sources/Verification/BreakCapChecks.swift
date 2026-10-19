import Foundation

/// The engine's break across a relaunch, past its cap, over midnight, and as
/// the correction checkpoints and recovery paths find it.
/// Registered through `BreakTakingChecks.tests`.
extension BreakTakingChecks {
    static func breakSurvivesRelaunch() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        let engine = SelfTest.makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Parser"); clock.advance(600)
        engine.startBreak(length: 300, label: "Walk")
        guard let original = engine.activeBreak, let saved = engine.store.loadState() else {
            return ["the break should have been saved"]
        }
        clock.advance(7_200)
        let restored = relaunched(engine, clock)
        restored.restore(from: saved)
        expect(restored.activeBreak == original && restored.state == .paused(reason: .onBreak),
               "same break back", &problems)
        expect(restored.activeThreadID == engine.activeThreadID, "on the same thread", &problems)
        // A pause that says break but has none to go with it is a plain pause.
        var orphan = saved
        orphan.activeBreak = nil
        let plain = relaunched(engine, clock)
        plain.restore(from: orphan)
        expect(plain.state == .paused(reason: .manual) && plain.activeBreak == nil,
               "a break reason with no break restores as a pause", &problems)

        restored.endBreak()
        let started = restored.archive.records.filter { $0.breakOrigin == .started }
        expect(started.count == 1 && started.first?.name == "Walk", "recorded once, as named", &problems)
        expect(restored.state == .running && restored.activeBreak == nil, "and the work resumes", &problems)

        // A break with no session comes back with none.
        let quietClock = TestClock(SelfTest.base)
        let quiet = SelfTest.makeEngine(quietClock)
        quiet.startBreak(length: 300)
        guard let idleBreak = quiet.activeBreak, let idleSaved = quiet.store.loadState() else {
            return problems + ["the idle break should have been saved"]
        }
        let quietBack = relaunched(quiet, quietClock)
        quietBack.restore(from: idleSaved)
        expect(quietBack.activeBreak == idleBreak && quietBack.state == .idle,
               "a break with no session comes back alone", &problems)
        return problems
    }

    static func forgottenBreakEndsAtCap() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        let engine = SelfTest.makeEngine(clock)
        let cap = engine.store.longAwayCap
        engine.start(workType: .deepWork, intent: "Parser"); clock.advance(600)
        let breakStart = clock.value
        engine.startBreak(length: 300)
        guard let brk = engine.activeBreak else { return ["the break should have started"] }
        clock.advance(300 + cap - 60)
        expect(engine.expireBreakIfOutgrown() == nil && engine.state == .paused(reason: .onBreak),
               "not before the cap", &problems)
        clock.advance(60 + 3_600)
        let capped = brk.plannedEnd.addingTimeInterval(cap)
        expect(engine.expireBreakIfOutgrown() == capped, "reports the capped end", &problems)
        let rest = breaks(in: engine).first
        expect(breaks(in: engine).count == 1 && rest?.end == capped, "ends at cap, not now", &problems)
        expect(rest?.start == breakStart && rest?.breakOrigin == .started, "from its start", &problems)
        expect(engine.state == .idle, "session ended as a long absence", &problems)
        expect(stretches(in: engine).count == 1 && stretches(in: engine).first?.end == breakStart
                && near(stretches(in: engine).first?.workSeconds, 600),
               "its stretch is archived once, where the break began", &problems)
        expect(engine.activeBreak == nil && engine.expireBreakIfOutgrown() == nil
                && engine.archive.records.count == 2, "and nothing is written twice", &problems)
        return problems
    }

    static func restorePastCapExpires() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        let engine = SelfTest.makeEngine(clock)
        let cap = engine.store.longAwayCap
        engine.start(workType: .deepWork, intent: "Parser"); clock.advance(600)
        engine.startBreak(length: 300)
        guard let brk = engine.activeBreak else { return ["the break should have started"] }
        let saved = engine.snapshot()
        clock.advance(300 + cap + 7_200)
        let restored = relaunched(engine, clock)
        restored.restore(from: saved)
        let rest = breaks(in: restored).first
        expect(restored.state == .idle && restored.activeBreak == nil, "ends the session", &problems)
        expect(breaks(in: restored).count == 1 && rest?.end == brk.plannedEnd.addingTimeInterval(cap),
               "one record ending at the cap", &problems)
        expect(stretches(in: restored).count == 1 && stretches(in: restored).first?.end == brk.start,
               "and one stretch ending where it began", &problems)

        // Gone for the cap since the last save, but not for the break's own:
        // a long break is still the break's to end.
        let long = TestClock(SelfTest.base)
        let held = SelfTest.makeEngine(long)
        held.start(workType: .deepWork, intent: "Parser"); long.advance(600)
        held.startBreak(length: 1_800)
        let heldSaved = held.snapshot()
        long.advance(cap + 600)
        let back = relaunched(held, long)
        back.restore(from: heldSaved)
        expect(back.state == .paused(reason: .onBreak) && back.activeBreak != nil
                && back.archive.records.isEmpty, "a break inside its own cap is kept", &problems)
        return problems
    }

    static func breakAcrossMidnight() -> [String] {
        var problems: [String] = []
        let calendar = SelfTest.gregorian
        guard let evening = calendar.date(bySettingHour: 23, minute: 40, second: 0, of: SelfTest.base) else {
            return ["could not build the evening"]
        }
        let clock = TestClock(evening)
        let engine = SelfTest.makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Late"); clock.advance(17 * 60)
        engine.startBreak(length: 600); clock.advance(600)
        engine.endBreak()
        let rest = breaks(in: engine)
        expect(rest.count == 1 && near(rest.first?.workSeconds, 600), "one ten-minute record across midnight", &problems)
        if let first = rest.first {
            expect(!calendar.isDate(first.start, inSameDayAs: first.end), "which does cross it", &problems)
        }
        return problems
    }

    static func recordedBreakStaysEnded() -> [String] {
        var problems: [String] = []

        // Killed after the break was written and before the state was: the
        // relaunch restores the snapshot from before it ended.
        let clock = TestClock(SelfTest.base)
        let engine = SelfTest.makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Parser"); clock.advance(600)
        engine.startBreak(length: 300)
        let beforeEnd = engine.snapshot()
        clock.advance(400)
        engine.endBreak()
        let back = relaunched(engine, clock)
        back.restore(from: beforeEnd)
        expect(back.activeBreak == nil && back.state == .idle, "an ended break is not live again", &problems)
        expect(breaks(in: back).count == 1 && back.store.loadState()?.activeBreak == nil,
               "and it is on record once", &problems)

        // Preferences lost: the journal's checkpoint, written while the break
        // was ending, is what a launch finds. A full history makes ending
        // write that checkpoint.
        let late = TestClock(SelfTest.base)
        let directory = SelfTest.scratchDirectory()
        let seed = SessionArchive(directory: directory, now: { late.value }, capacity: 2)
        for hours in [4.0, 3.0] {
            let start = SelfTest.base.addingTimeInterval(-hours * 3_600)
            seed.append(SessionRecord(name: "Earlier", workType: .deepWork, start: start,
                                      end: start.addingTimeInterval(1_200), workSeconds: 1_200))
        }
        let store = PersistenceStore(defaults: MemoryDefaults.suite(named: SelfTest.suiteName) ?? .standard)
        store.removeAll()
        let ended = SessionEngine(store: store, archive: SessionArchive(directory: directory, now: { late.value },
                                                                       capacity: 2),
                                  ownBundleID: FocusConstants.bundleIdentifier, schedulesDwell: false,
                                  now: { late.value })
        ended.start(workType: .deepWork, intent: "Parser"); late.advance(600)
        ended.startBreak(length: 300); late.advance(400)
        ended.endBreak()
        expect(ended.decisionHistory.document.checkpoint != nil, "ending a break wrote the checkpoint", &problems)
        store.removeAll()
        let launched = SessionEngine(store: store, archive: SessionArchive(directory: directory, now: { late.value }),
                                     ownBundleID: FocusConstants.bundleIdentifier, schedulesDwell: false,
                                     now: { late.value })
        guard let checkpoint = launched.launchSnapshot() else {
            return problems + ["the journal should still hold a checkpoint"]
        }
        launched.restore(from: checkpoint)
        expect(launched.activeBreak == nil && launched.state == .idle,
               "a break in the journal's checkpoint is not live again", &problems)
        expect(breaks(in: launched).count == 1, "and it is on record once", &problems)
        return problems
    }

    static func breakPauseWithoutBreakResumes() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        let stuck = SelfTest.makeEngine(clock)
        stuck.start(workType: .deepWork, intent: "Parser"); clock.advance(600)
        stuck.startBreak(length: 300)
        // No call leaves a break pause without its break; this forces that
        // state to see that nothing is trapped in it.
        stuck.activeBreak = nil
        stuck.transition(on: .manualResume)
        expect(stuck.state == .running, "Resume leaves a break pause that has no break", &problems)
        return problems
    }

    static func breakPauseIsPresence() -> [String] {
        var problems: [String] = []
        expect(!SessionEngine.pauseMeansNobodyHere(.onBreak), "a break has a cap of its own", &problems)
        expect(SessionEngine.pauseMeansNobodyHere(.manual), "and a pause still does not", &problems)
        return problems
    }

    static func correctionCheckpointKeepsBreak() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        let engine = SelfTest.makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Parser"); clock.advance(600)
        engine.startBreak(length: 300)
        guard let original = engine.activeBreak else { return ["the break should have started"] }
        expect(engine.commitCorrection(before: engine.snapshot()), "a correction mid-break commits", &problems)
        // A copy of the app that has not seen it adopts the newer checkpoint.
        let other = relaunched(engine, clock)
        expect(!other.prepareCorrection(), "the newer checkpoint is loaded, not corrected over", &problems)
        expect(other.state == .paused(reason: .onBreak) && other.activeBreak == original,
               "with the break it was taken in", &problems)
        return problems
    }
}
