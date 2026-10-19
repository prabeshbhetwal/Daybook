import Foundation

/// The engine's timed break: starting, ending and what leaves it alone, with
/// the helpers `BreakCapChecks` shares. Registered through
/// `BreakTakingChecks.tests`.
extension BreakTakingChecks {
    private static let workApp = SessionEvent.appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode")

    static func near(_ value: Double?, _ target: Double) -> Bool {
        abs((value ?? -1) - target) < 0.5
    }

    static func breaks(in engine: SessionEngine) -> [SessionRecord] {
        engine.archive.records.filter { $0.workType == .breakTime }
    }

    static func stretches(in engine: SessionEngine) -> [SessionRecord] {
        engine.archive.records.filter { $0.workType != .breakTime }
    }

    /// A new engine on the same preferences and the same archive folder, as a
    /// relaunch has.
    static func relaunched(_ engine: SessionEngine, _ clock: TestClock) -> SessionEngine {
        SessionEngine(store: engine.store,
                      archive: SessionArchive(directory: engine.archive.dataDirectoryURL,
                                              now: { clock.value }),
                      ownBundleID: FocusConstants.bundleIdentifier,
                      schedulesDwell: false, now: { clock.value })
    }

    /// An engine whose archive refuses writes while `refuses` says so.
    static func gatedEngine(_ clock: TestClock, refuses: @escaping () -> Bool) -> SessionEngine {
        let store = PersistenceStore(defaults: MemoryDefaults.suite(named: SelfTest.suiteName) ?? .standard)
        store.removeAll()
        let archive = SessionArchive(directory: SelfTest.scratchDirectory(), now: { clock.value },
                                     writeOverride: { _ in refuses() ? "You don't have permission to save." : nil })
        return SessionEngine(store: store, archive: archive, ownBundleID: FocusConstants.bundleIdentifier,
                             schedulesDwell: false, now: { clock.value })
    }

    static func startPausesRunning() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        let engine = SelfTest.makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Parser"); clock.advance(1_200)
        expect(engine.startBreak(length: 300), "starts", &problems)
        expect(engine.state == .paused(reason: .onBreak), "paused onBreak", &problems)
        expect(engine.activeBreak?.plannedLength == 300, "five minutes planned", &problems)
        expect(!engine.startBreak(length: 300), "second start refused", &problems)
        expect(near(engine.activeBreak?.remaining(at: clock.value), 300), "five minutes left", &problems)
        clock.advance(100)
        expect(near(engine.activeBreak?.remaining(at: clock.value), 200), "the time counts down", &problems)
        expect(near(engine.elapsed, 1_200), "the session's clock is stopped", &problems)

        // A pause the person pressed is left the way Resume leaves it, then
        // the break takes over; its minutes stay out of the work.
        let paused = TestClock(SelfTest.base)
        let manual = SelfTest.makeEngine(paused)
        manual.start(workType: .deepWork, intent: "Parser"); paused.advance(600)
        manual.transition(on: .manualPause); paused.advance(120)
        expect(manual.startBreak(length: 300), "a pressed pause gives way to a break", &problems)
        paused.advance(400)
        manual.endBreak()
        expect(near(stretches(in: manual).last?.workSeconds, 600), "the pause was not work", &problems)
        expect(near(breaks(in: manual).first?.workSeconds, 400), "the break starts when asked", &problems)
        return problems
    }

    static func endRecordsAndResumes() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        let engine = SelfTest.makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Parser")
        let thread = engine.activeThreadID
        clock.advance(1_200)
        let breakStart = clock.value
        engine.startBreak(length: 300)
        clock.advance(300)
        engine.markBreakOverNoticed()
        expect(engine.activeBreak?.overNoticed == true, "over is noticed once", &problems)
        clock.advance(120)
        engine.extendBreak(by: 300)
        expect(engine.activeBreak?.plannedLength == 600 && engine.activeBreak?.overNoticed == false,
               "plus five minutes, and the break is over later", &problems)
        let end = engine.endBreak()
        expect(end == clock.value, "ends now by default", &problems)
        let rest = breaks(in: engine).first
        expect(breaks(in: engine).count == 1, "one break on record", &problems)
        expect(near(rest?.workSeconds, 420) && rest?.plannedLength == 600 && rest?.breakOrigin == .started,
               "actual 7 min, planned 10", &problems)
        expect(rest?.name == "Break" && rest?.start == breakStart && rest?.end == clock.value,
               "named Break, from its start to now", &problems)
        expect(engine.state == .running && engine.activeThreadID == thread, "same thread resumes", &problems)
        expect(engine.archive.records.filter { $0.workType != .breakTime }.last?.end == breakStart,
               "stretch closed at the break's start", &problems)
        expect(near(stretches(in: engine).last?.workSeconds, 1_200), "with the work before it", &problems)
        expect(engine.activeBreak == nil && near(engine.elapsed, 0), "a new stretch begins", &problems)
        expect(engine.endBreak() == nil, "nothing to end twice", &problems)

        // Ended earlier than now, as sustained work does: the work resumes then.
        let back = TestClock(SelfTest.base)
        let sustained = SelfTest.makeEngine(back)
        sustained.start(workType: .deepWork, intent: "Parser"); back.advance(600)
        sustained.startBreak(length: 300); back.advance(400)
        let began = back.value.addingTimeInterval(-60)
        expect(sustained.endBreak(at: began) == began, "ends where the work began", &problems)
        expect(near(sustained.elapsed, 60), "and the minute since is work", &problems)
        expect(near(breaks(in: sustained).first?.workSeconds, 340), "the break is shorter by it", &problems)
        return problems
    }

    static func idleBreakRecordsOnly() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        let engine = SelfTest.makeEngine(clock)
        expect(engine.startBreak(length: 300), "starts with no session", &problems)
        expect(engine.state == .idle && engine.activeBreak?.threadID == nil,
               "starts nothing and pauses no thread", &problems)
        clock.advance(20)
        expect(engine.endBreak() == clock.value, "ends", &problems)
        expect(engine.archive.records.isEmpty && engine.activeBreak == nil,
               "under 30 seconds is not recorded", &problems)

        engine.startBreak(length: 300, label: "  Dinner ")
        clock.advance(400)
        engine.endBreak()
        expect(engine.archive.records.count == 1 && engine.state == .idle, "one record, no session", &problems)
        let rest = engine.archive.records.first
        expect(rest?.name == "Dinner" && near(rest?.workSeconds, 400) && rest?.breakOrigin == .started,
               "named as typed, at its real length", &problems)
        return problems
    }

    static func workAppDoesNotEndBreak() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        let engine = SelfTest.makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Parser"); clock.advance(600)
        engine.startBreak(length: 300)
        guard let original = engine.activeBreak else { return ["the break should have started"] }
        clock.advance(30)
        let events: [SessionEvent] = [
            workApp, .overrideApplied(bundleID: "com.apple.dt.Xcode"), .idleObserved(seconds: 600),
            .markedAway, .awayBegan(trigger: .screenLock), .awayEnded,
            .watchingObserved(seconds: 600), .dwellExpired(bundleID: "com.example.video"),
            .manualPause, .launch,
        ]
        for event in events {
            engine.transition(on: event)
            expect(engine.state == .paused(reason: .onBreak) && engine.activeBreak == original,
                   "still on a break after \(event)", &problems)
        }
        engine.transition(on: .manualResume)
        expect(engine.state == .running && engine.activeBreak == nil, "Resume ends it", &problems)
        expect(breaks(in: engine).count == 1, "recorded once", &problems)
        return problems
    }

    static func idleBreakBlocksLegacyStart() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        let engine = SelfTest.makeEngine(clock)
        engine.store.activityRuleAutomationEnabled = false
        engine.store.autoSessionsEnabled = true
        expect(engine.store.automationMode == .legacyHeuristic, "the work-app start is on", &problems)
        engine.startBreak(length: 300)
        engine.transition(on: workApp)
        expect(engine.state == .idle, "no session starts by itself during a break", &problems)
        engine.endBreak()
        engine.transition(on: workApp)
        expect(engine.state == .running, "the same work app starts one once the break is over", &problems)
        return problems
    }

    static func refusedWhileDeciding() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        let engine = SelfTest.makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Parser"); clock.advance(600)
        clock.advance(FocusConstants.idlePauseThreshold)
        engine.transition(on: .idleObserved(seconds: FocusConstants.idlePauseThreshold))
        expect(!engine.startBreak(length: 300), "refused while paused for idle", &problems)
        clock.advance(40 * 60)
        engine.transition(on: workApp)
        guard case .awaitingUserDecision = engine.state else {
            return problems + ["a long idle absence should leave the away question up"]
        }
        expect(!engine.startBreak(length: 300) && engine.activeBreak == nil,
               "refused while an away question waits", &problems)

        let away = TestClock(SelfTest.base)
        let declared = SelfTest.makeEngine(away)
        declared.start(workType: .deepWork, intent: "Parser"); away.advance(600)
        declared.transition(on: .markedAway)
        expect(!declared.startBreak(length: 300), "refused while away", &problems)
        return problems
    }

    static func retryClearsRefusal() -> [String] {
        var problems: [String] = []
        var refuses = false
        let clock = TestClock(SelfTest.base)
        let engine = gatedEngine(clock) { refuses }
        engine.start(workType: .deepWork, intent: "Parser"); clock.advance(600)
        engine.startBreak(length: 300); clock.advance(400)
        refuses = true
        expect(engine.endBreak() == nil && engine.state == .paused(reason: .onBreak)
                && engine.activeBreak != nil, "a refused save keeps the break", &problems)
        expect(engine.awayDecisionError != nil, "and says why", &problems)
        refuses = false
        expect(engine.endBreak() != nil && engine.state == .running, "the retry ends it", &problems)
        expect(engine.awayDecisionError == nil, "and the refusal is not left behind", &problems)

        var refusesExpiry = false
        let late = TestClock(SelfTest.base)
        let forgotten = gatedEngine(late) { refusesExpiry }
        forgotten.start(workType: .deepWork, intent: "Parser"); late.advance(600)
        forgotten.startBreak(length: 300)
        late.advance(300 + forgotten.store.longAwayCap + 60)
        refusesExpiry = true
        expect(forgotten.expireBreakIfOutgrown() == nil && forgotten.activeBreak != nil,
               "a refused save keeps the expired break to retry", &problems)
        expect(forgotten.awayDecisionError != nil, "and says why", &problems)
        refusesExpiry = false
        expect(forgotten.expireBreakIfOutgrown() != nil && forgotten.state == .idle,
               "the retry ends it", &problems)
        expect(forgotten.awayDecisionError == nil, "and the refusal is not left behind", &problems)
        return problems
    }

    static func breakLengthIsCapped() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        let engine = SelfTest.makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Parser"); clock.advance(600)
        expect(engine.startBreak(length: 1e300), "an absurd length is taken as the longest", &problems)
        expect(engine.activeBreak?.plannedLength == BreakLength.maximum, "a day at most", &problems)
        engine.extendBreak(by: .greatestFiniteMagnitude)
        engine.extendBreak(by: .greatestFiniteMagnitude)
        expect(engine.activeBreak?.plannedLength == BreakLength.maximum, "extending cannot pass it", &problems)
        expect(engine.store.loadState()?.activeBreak == engine.activeBreak,
               "and the break still saves", &problems)

        let nearDay = SelfTest.makeEngine(TestClock(SelfTest.base))
        nearDay.startBreak(length: BreakLength.maximum - 300)
        nearDay.extendBreak(by: BreakLength.extra)
        nearDay.extendBreak(by: BreakLength.extra)
        expect(nearDay.activeBreak?.plannedLength == BreakLength.maximum, "plus five minutes stops at a day", &problems)
        return problems
    }
}
