import Foundation

/// How a session began follows the work, not the clock: a stretch that carries
/// on keeps it, time counted back into a session takes the session's own, and a
/// value a later build changes never costs the person a record or the running
/// session. The edits the person makes to a running session are in
/// `ProvenanceLiveEditChecks`.
enum ProvenanceCarryChecks: CheckSuite {

    static let tests: [(String, () -> [String])] = [
        ("A stretch that carries on keeps how it began; a fresh session begins as the person's", carryOnKeepsProvenance),
        ("Time counted back in, by an away re-answer or a reclassified break, began as its session did", countedTimeTakesTheSessions),
        ("A malformed provenance reads as nil and never drops the running session or a record", malformedProvenanceReadsNil),
    ]

    /// A session the detector started, 10 minutes in, its name the app's.
    private static func automaticEngine(_ clock: TestClock) -> SessionEngine {
        let engine = SelfTest.makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Coding", isAuto: true, nameByApp: true)
        clock.advance(600)
        return engine
    }

    private static let theApps = SessionProvenance.automatic(nameByApp: true)

    private static func awayAnswered(_ engine: SessionEngine, _ clock: TestClock, _ answer: UserDecision) {
        engine.transition(on: .awayBegan(trigger: .screenLock))
        clock.advance(1_320)
        engine.transition(on: .awayEnded)
        engine.transition(on: .decision(answer))
    }

    private static func carryOnKeepsProvenance() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)

        let onBreak = automaticEngine(clock)
        let thread = onBreak.activeThreadID
        onBreak.startBreak(length: 300)
        clock.advance(600)
        onBreak.endBreak()
        expect(onBreak.activeThreadID == thread && onBreak.activeProvenance == theApps,
               "the stretch after a break read \(onBreak.activeProvenance)", &problems)

        let declared = automaticEngine(clock)
        declared.transition(on: .markedAway)
        clock.advance(1_320)
        declared.transition(on: .manualResume)
        expect(declared.activeProvenance == theApps,
               "the stretch after a declared away read \(declared.activeProvenance)", &problems)
        clock.advance(120)
        _ = declared.stop()
        let stretches = declared.archive.records.filter(\.workType.countsAsFocus)
        expect(stretches.count == 2 && stretches.allSatisfy {
            $0.origin == .automatic && $0.nameByApp == true && $0.categorySource == .builtIn
        }, "the stretches around a declared away lost how they began: \(stretches)", &problems)

        let answered = automaticEngine(clock)
        answered.transition(on: .awayBegan(trigger: .screenLock))
        clock.advance(1_320)
        answered.transition(on: .awayEnded)
        let kept = answered.activeThreadID
        answered.transition(on: .decision(.continueSession))
        expect(answered.activeThreadID == kept && answered.activeProvenance == theApps,
               "the same work after an away answer read \(answered.activeProvenance)", &problems)

        // A fresh session begins as the person's own.
        let fresh = automaticEngine(clock)
        fresh.transition(on: .resetSession)
        expect(fresh.activeProvenance == .manual, "Start Fresh kept \(fresh.activeProvenance)", &problems)

        let restarted = automaticEngine(clock)
        awayAnswered(restarted, clock, .resetTimer)
        expect(restarted.activeProvenance == .manual, "an away answer that starts over kept \(restarted.activeProvenance)", &problems)

        let longAway = automaticEngine(clock)
        longAway.transition(on: .markedAway)
        clock.advance(5 * 3_600)
        longAway.transition(on: .manualResume)
        expect(longAway.state == .running && longAway.activeProvenance == .manual,
               "a new session after a long absence read \(longAway.activeProvenance)", &problems)

        let legacy = SelfTest.makeEngine(clock)
        legacy.store.activityRuleAutomationEnabled = false
        legacy.store.autoSessionsEnabled = true
        legacy.transition(on: .appActivated(bundleID: "com.apple.dt.Xcode", name: "Xcode"))
        expect(legacy.state == .running && legacy.activeProvenance == .manual,
               "the legacy work-app start read \(legacy.activeProvenance)", &problems)
        return problems
    }

    private static func countedTimeTakesTheSessions() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base.addingTimeInterval(7_200))

        // Away, "I was away", Undo, "I was working": the counted stretch is the session's.
        let engine = automaticEngine(clock)
        awayAnswered(engine, clock, .continueSession)
        expect(engine.undoAwayDecision(), "the away answer was not undoable", &problems)
        expect(engine.reviseAwayDecision(.mergeTime), "the re-answer was refused", &problems)
        let counted = engine.archive.records.first { $0.id == engine.lastAwayDecision?.id }
        expect(counted?.workType == .deepWork && counted?.origin == .automatic
               && counted?.categorySource == .builtIn && counted?.nameByApp == true,
               "the re-answered stretch read as the person's: \(String(describing: counted))", &problems)

        // A legacy break counted into a recorded session.
        let reclassify = SelfTest.makeEngine(clock)
        let base = SelfTest.base
        let target = SessionRecord(name: "Coding", workType: .deepWork, start: base,
                                   end: base.addingTimeInterval(600), workSeconds: 600,
                                   threadID: UUID(), isAuto: true, origin: .automatic,
                                   categorySource: .builtIn, nameByApp: true)
        let rest = SessionRecord(name: "Away", workType: .breakTime, start: base.addingTimeInterval(600),
                                 end: base.addingTimeInterval(1_800), workSeconds: 1_200)
        reclassify.archive.append(target)
        reclassify.archive.append(rest)
        expect(reclassify.reclassifyLegacyBreak(recordID: rest.id, decision: .mergeTime, focusTargetID: target.id),
               "the legacy break was not reclassified", &problems)
        let merged = reclassify.archive.records.first { $0.start == rest.start && $0.workType == .deepWork }
        expect(merged?.threadID == target.threadID && merged?.origin == .automatic
               && merged?.categorySource == .builtIn && merged?.nameByApp == true,
               "the reclassified stretch read as the person's: \(String(describing: merged))", &problems)
        return problems
    }

    private static func malformedProvenanceReadsNil() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)
        let engine = automaticEngine(clock)

        // The saved state: the running session survives, reading as the app's own.
        guard let data = try? JSONEncoder().encode(engine.snapshot()),
              var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return ["could not encode the saved state"]
        }
        let wrongTypes: [String: Any] = ["origin": 7, "ruleID": 3, "categorySource": ["x"], "nameByApp": "yes"]
        for value in [wrongTypes, "garbage"] as [Any] {
            json["provenance"] = value
            guard let broken = try? JSONSerialization.data(withJSONObject: json),
                  let state = try? JSONDecoder().decode(PersistedState.self, from: broken) else {
                problems.append("a malformed provenance \(value) made the saved state unreadable")
                continue
            }
            let relaunched = SelfTest.makeEngine(clock)
            relaunched.restore(from: state)
            expect(relaunched.state != .idle && relaunched.sessionName == "Coding",
                   "a malformed provenance \(value) lost the running session", &problems)
            expect(relaunched.activeProvenance.origin != .manual && relaunched.activeProvenance.categorySource != .user,
                   "a malformed provenance \(value) read as the person's", &problems)
        }

        // A record: the malformed values read as nil, the totals are kept.
        let record = SessionRecord(name: "Parser", workType: .deepWork, start: SelfTest.base,
                                   end: SelfTest.base.addingTimeInterval(600), workSeconds: 600)
        guard let recordData = try? JSONEncoder().encode(record),
              var object = (try? JSONSerialization.jsonObject(with: recordData)) as? [String: Any] else {
            return problems + ["could not encode the record"]
        }
        object["origin"] = 7
        object["originRuleID"] = "not an id"
        object["categorySource"] = ["x"]
        object["nameByApp"] = "yes"
        let directory = SelfTest.scratchDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let file = try? JSONSerialization.data(withJSONObject: [object]) {
            try? file.write(to: directory.appendingPathComponent("sessions.json"), options: .atomic)
        }
        let archive = SessionArchive(directory: directory, now: { SelfTest.base.addingTimeInterval(7_200) })
        let read = archive.records.first
        expect(archive.records.count == 1 && read?.workSeconds == 600 && read?.origin == nil
               && read?.originRuleID == nil && read?.categorySource == nil && read?.nameByApp == nil,
               "a record with malformed provenance was not read as nil: \(String(describing: read))", &problems)

        // The journal's copy of what Undo puts back.
        let fields = SessionStoreCorrectionState.ActiveFields(name: "Coding", workType: .deepWork)
        guard let fieldData = try? JSONEncoder().encode(fields),
              var fieldJSON = (try? JSONSerialization.jsonObject(with: fieldData)) as? [String: Any] else {
            return problems + ["could not encode the fields"]
        }
        let wrongFields: [String: Any] = ["categorySource": 4, "nameByApp": "x"]
        for value in [wrongFields, "junk"] as [Any] {
            fieldJSON["provenance"] = value
            let back = (try? JSONSerialization.data(withJSONObject: fieldJSON))
                .flatMap { try? JSONDecoder().decode(SessionStoreCorrectionState.ActiveFields.self, from: $0) }
            expect(back?.name == "Coding" && back?.provenance?.categorySource == nil && back?.provenance?.nameByApp == nil,
                   "malformed saved fields \(value) were not read as nil: \(String(describing: back))", &problems)
        }
        return problems
    }
}
