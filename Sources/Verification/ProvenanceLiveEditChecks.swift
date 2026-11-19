import Foundation

/// The person's edits to a session that is still running (rename, category,
/// adopting it) mark it as theirs, and Undo puts back what each changed, on the
/// running stretch and on any stretch of the same work saved since.
enum ProvenanceLiveEditChecks: CheckSuite {

    static let tests: [(String, () -> [String])] = [
        ("A rename, a category change and adopting a running session mark it as the person's", liveEditsMarkProvenance),
        ("Undo puts back the running session's provenance, and a stretch saved since", undoRestoresRunningProvenance),
    ]

    /// An automatic session whose name is the app's, 10 minutes in.
    private static func automaticEngine(_ clock: TestClock) -> SessionEngine {
        let engine = SelfTest.makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Coding", isAuto: true, nameByApp: true)
        clock.advance(600)
        return engine
    }

    private static func liveEditsMarkProvenance() -> [String] {
        var problems: [String] = []
        let clock = TestClock(SelfTest.base)

        // The person's own name and category, each alone, and the no-op.
        let engine = automaticEngine(clock)
        let thread = engine.activeThreadID
        engine.stageActiveCorrection(.workType(.deepWork), threadID: thread)
        expect(engine.activeProvenance == .automatic(nameByApp: true),
               "choosing the category it already has changed \(engine.activeProvenance)", &problems)
        engine.stageActiveCorrection(.rename("Parser"), threadID: thread)
        expect(engine.activeProvenance.nameByApp == false && engine.activeProvenance.categorySource == .builtIn,
               "a rename must clear only nameByApp: \(engine.activeProvenance)", &problems)
        engine.stageActiveCorrection(.workType(.learning), threadID: thread)
        expect(engine.activeProvenance.categorySource == .user && engine.activeProvenance.origin == .automatic,
               "a category change must make only the source the person's: \(engine.activeProvenance)", &problems)
        _ = engine.stop()
        let stored = engine.archive.records.last
        expect(stored?.origin == .automatic && stored?.nameByApp == false && stored?.categorySource == .user,
               "the stored record lost the edits: \(String(describing: stored))", &problems)

        // Adopting: a given name is the person's, none leaves the app's.
        for (intent, nameByApp) in [("", true), ("Parser", false)] {
            let adopted = automaticEngine(clock)
            adopted.adopt(intent: intent)
            expect(adopted.activeProvenance.categorySource == .user && adopted.activeProvenance.nameByApp == nameByApp
                   && adopted.activeProvenance.origin == .automatic,
                   "adopting with \"\(intent)\" read \(adopted.activeProvenance)", &problems)
        }
        return problems
    }

    private static func undoRestoresRunningProvenance() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let clock = TestClock(SelfTest.base.addingTimeInterval(7_200))
            let suite = "fc-selftest-provenance-live-\(UUID().uuidString)"
            guard let defaults = MemoryDefaults.suite(named: suite) else { return ["could not create isolated preferences"] }
            defer { MemoryDefaults.remove(named: suite) }
            let archive = SessionArchive(directory: SelfTest.scratchDirectory(), now: { clock.value })
            let engine = SessionEngine(store: PersistenceStore(defaults: defaults), archive: archive,
                                       ownBundleID: "com.test", schedulesDwell: false, now: { clock.value })
            let store = SessionStore(engine: engine, now: { clock.value })
            engine.start(workType: .deepWork, intent: "Coding", isAuto: true, nameByApp: true)
            clock.advance(600)
            let thread = engine.activeThreadID
            let row = DaySession(id: thread, threadID: thread, name: "Coding", workType: .deepWork,
                                 start: clock.value, end: clock.value, worked: 600, stretches: 1,
                                 spans: [], isRunning: true)

            expect(store.setWorkType(.learning, threadID: thread), "the category change was refused", &problems)
            expect(engine.activeProvenance.categorySource == .user, "the change did not mark the source", &problems)
            expect(store.undoLastCorrection(), "the category change was not undoable", &problems)
            expect(engine.activeWorkType == .deepWork && engine.activeProvenance == .automatic(nameByApp: true),
                   "Undo left the running category's source as the person's: \(engine.activeProvenance)", &problems)

            // A rename, then work saved under the new name before the Undo.
            expect(store.renameSession(row, to: "Parser"), "the rename was refused", &problems)
            expect(engine.activeProvenance.nameByApp == false, "the rename did not clear nameByApp", &problems)
            engine.transition(on: .markedAway)
            clock.advance(1_320)
            engine.transition(on: .manualResume)
            let saved = archive.records.filter { $0.threadID == thread && $0.workType.countsAsFocus }
            expect(saved.count == 1 && saved[0].name == "Parser" && saved[0].nameByApp == false,
                   "the stretch saved before the Undo read \(saved)", &problems)
            expect(store.undoLastCorrection(), "the rename was not undoable", &problems)
            expect(engine.sessionName == "Coding" && engine.activeProvenance.nameByApp == true,
                   "Undo left the running name as the person's: \(engine.activeProvenance)", &problems)
            let after = archive.records.filter { $0.threadID == thread && $0.workType.countsAsFocus }
            expect(after.count == 1 && after[0].name == "Coding" && after[0].nameByApp == true,
                   "Undo left the saved stretch's name as the person's: \(after)", &problems)
            return problems
        }
    }
}
