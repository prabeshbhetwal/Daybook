import Foundation

/// Every way a session starts, and every change that keeps or alters how it
/// began, leaves the right provenance on the record it writes.
enum ProvenanceEngineChecks: CheckSuite {

    static let tests: [(String, () -> [String])] = [
        ("A manual start writes manual origin and the person's category", manualStart),
        ("A rule start writes the rule's id and name, and the rule as the category source", ruleStart),
        ("An automatic start writes built in, even for a learned category, and flags the app's name", automaticStart),
        ("Claiming an automatic or rule session keeps its origin and makes the category the person's", claimKeepsOrigin),
        ("Pausing and an away answer keep the provenance on the record written before the gap", pauseAndAwayKeepProvenance),
        ("A relaunch keeps the provenance, and a state saved before it reads from isAuto and the rule", relaunchKeepsProvenance),
        ("A rule switch gives the old stretch its own provenance and the new one the new rule's", switchSplitsProvenance),
    ]

    private static func rule(_ name: String, from start: Date, to end: Date) -> ActivityAutomaticAction {
        ActivityAutomaticAction(ruleID: UUID(), ruleName: name, workType: .deepWork,
                                evidence: DateInterval(start: start, end: end),
                                reason: "\(name) foreground evidence", ruleVersion: 1, generation: 1,
                                expectedRecordID: nil)
    }

    /// Ends the running session and returns its one record.
    private static func ended(_ engine: SessionEngine) -> SessionRecord? {
        guard engine.stop() else { return nil }
        return engine.archive.records.last
    }

    private static func manualStart() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        let engine = SelfTest.makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Write the spec")
        clock.advance(600)
        let record = ended(engine)
        expect(record?.origin == .manual && record?.categorySource == .user && record?.nameByApp == false
               && record?.originRuleID == nil && record?.originRuleName == nil,
               "manual start wrote \(String(describing: record))", &problems)
        return problems
    }

    private static func ruleStart() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base.addingTimeInterval(300))
        let engine = SelfTest.makeEngine(clock)
        let action = rule("Coding", from: SelfTest.base, to: clock.value)
        expect(engine.startAutomatically(action: action), "the rule start was refused", &problems)
        clock.advance(600)
        let record = ended(engine)
        expect(record?.origin == .rule && record?.originRuleID == action.ruleID
               && record?.originRuleName == "Coding" && record?.categorySource == .rule
               && record?.nameByApp == false,
               "rule start wrote \(String(describing: record))", &problems)
        return problems
    }

    private static func automaticStart() -> [String] {
        var problems: [String] = []
        for (workType, nameByApp) in [(WorkType.deepWork, true), (WorkType.learning, false)] {
            let clock = TestClock(SelfTest.base)
            let engine = SelfTest.makeEngine(clock)
            engine.start(workType: workType, intent: nameByApp ? "Coding" : "", isAuto: true, nameByApp: nameByApp)
            clock.advance(600)
            let record = ended(engine)
            expect(record?.origin == .automatic && record?.categorySource == .builtIn
                   && record?.nameByApp == nameByApp && record?.originRuleID == nil,
                   "automatic start (\(workType.rawValue)) wrote \(String(describing: record))", &problems)
        }
        return problems
    }

    private static func claimKeepsOrigin() -> [String] {
        var problems: [String] = []
        // The persisted ownership is what marks an engine.start session automatic.
        let clock = TestClock(SelfTest.base)
        let engine = SelfTest.makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Coding", isAuto: true, nameByApp: true)
        clock.advance(300)
        var snapshot = engine.snapshot()
        snapshot.isAuto = true
        engine.restore(from: snapshot)
        engine.claim()
        clock.advance(300)
        let claimed = ended(engine)
        expect(claimed?.origin == .automatic && claimed?.categorySource == .user && claimed?.nameByApp == true,
               "claiming an automatic session wrote \(String(describing: claimed))", &problems)

        let ruled = SelfTest.makeEngine(clock)
        let action = rule("Coding", from: clock.value, to: clock.value)
        expect(ruled.startAutomatically(action: action), "the rule start was refused", &problems)
        clock.advance(600)
        ruled.claim()
        let ruleRecord = ended(ruled)
        expect(ruleRecord?.origin == .rule && ruleRecord?.originRuleID == action.ruleID
               && ruleRecord?.categorySource == .user,
               "claiming a rule session wrote \(String(describing: ruleRecord))", &problems)
        return problems
    }

    private static func pauseAndAwayKeepProvenance() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        let engine = SelfTest.makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Coding", isAuto: true, nameByApp: true)
        let expected = engine.activeProvenance
        clock.advance(600)
        engine.transition(on: .manualPause)
        clock.advance(60)
        engine.transition(on: .manualResume)
        expect(engine.activeProvenance == expected, "a pause and resume changed the provenance", &problems)

        clock.advance(120)
        engine.transition(on: .awayBegan(trigger: .screenLock))
        clock.advance(1_320)
        engine.transition(on: .awayEnded)
        engine.transition(on: .decision(.continueSession))
        let before = engine.archive.records.first { $0.workType.countsAsFocus }
        expect(before?.origin == .automatic && before?.categorySource == .builtIn && before?.nameByApp == true,
               "the record written before the away gap lost its provenance: \(String(describing: before))", &problems)
        return problems
    }

    private static func relaunchKeepsProvenance() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base.addingTimeInterval(300))
        let engine = SelfTest.makeEngine(clock)
        let action = rule("Coding", from: SelfTest.base, to: clock.value)
        _ = engine.startAutomatically(action: action)
        clock.advance(600)

        let relaunched = SelfTest.makeEngine(clock)
        relaunched.restore(from: engine.snapshot())
        expect(relaunched.activeProvenance == .rule(action), "a relaunch lost the rule's provenance", &problems)

        // A state saved before provenance existed: read from isAuto and the action.
        for (action, expected) in [(Optional(action), SessionProvenance.rule(action)),
                                   (nil, SessionProvenance.automatic(nameByApp: false))] {
            var old = engine.snapshot()
            old.provenance = nil
            old.automaticActivityAction = action
            let engineFromOld = SelfTest.makeEngine(clock)
            engineFromOld.restore(from: old)
            expect(engineFromOld.activeProvenance == expected,
                   "an old state read as \(engineFromOld.activeProvenance)", &problems)
        }
        var manual = SelfTest.makeEngine(clock).snapshot()
        manual.provenance = nil
        manual.isAuto = false
        let engineFromManual = SelfTest.makeEngine(clock)
        engineFromManual.restore(from: manual)
        expect(engineFromManual.activeProvenance == .manual, "an old manual state read as automatic", &problems)
        return problems
    }

    private static func switchSplitsProvenance() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base.addingTimeInterval(300))
        let engine = SelfTest.makeEngine(clock)
        let first = rule("Coding", from: SelfTest.base, to: clock.value)
        _ = engine.startAutomatically(action: first)
        clock.advance(900)
        let boundary = clock.value
        clock.advance(300)
        let second = ActivityAutomaticAction(ruleID: UUID(), ruleName: "Research", workType: .deepWork,
                                             evidence: DateInterval(start: boundary, end: clock.value),
                                             reason: "Research evidence", ruleVersion: 1, generation: 2,
                                             expectedRecordID: engine.activeRecordID)
        expect(engine.switchAutomatically(action: second, expectedRecordID: engine.activeRecordID),
               "the switch was refused", &problems)
        let old = engine.archive.records.first
        expect(old?.origin == .rule && old?.originRuleID == first.ruleID && old?.originRuleName == "Coding",
               "the closed stretch did not keep the first rule: \(String(describing: old))", &problems)
        expect(engine.activeProvenance == .rule(second), "the new stretch did not take the second rule", &problems)
        return problems
    }
}
