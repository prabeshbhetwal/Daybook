import Foundation

/// Regression coverage for durable, reversible corrections. Each case owns an
/// isolated archive and preferences suite; no check can see personal history.
enum StoryCorrectionChecks: CheckSuite {

    static let tests: [(String, () -> [String])] = [
        ("Story corrections: running and resumed threads update as one work item", runningAndResumedThreadsUpdateTogether),
        ("Story corrections: no-op requests and failed writes stay honest", noOpsAndFailedWritesStayHonest),
        ("Story corrections: undo restores corrected fields without removing work", undoRestoresAffectedFields),
        ("Story corrections: active Break excludes live focus until undone", activeBreakExcludesLiveFocus),
        ("Story corrections: active-only undo and field undo preserve newer evidence", undoPreservesNewerEvidence),
        ("Story corrections: active type and thread survive restore", activeCorrectionPersistsAcrossRestore),
        ("Story corrections: Continue admits stopped threads and undo restores continuations", continueAndUndoLifecycle),
        ("Story corrections: undo restores an empty active name", undoRestoresEmptyActiveName),
        ("Story corrections: combined undo fails atomically and retries", combinedUndoIsAtomicAndRetryable)
    ]

    private struct Fixture {
        let store: SessionStore
        let engine: SessionEngine
        let archive: SessionArchive
        let directory: URL
        let cleanUp: () -> Void
    }

    private static func makeFixture(_ clock: TestClock,
                                    writeOverride: (([SessionRecord]) -> String?)? = nil) -> Fixture? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fc-story-correction-\(UUID().uuidString)", isDirectory: true)
        let suite = "com.prabesh.daybook.story-correction.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return nil }
        defaults.removePersistentDomain(forName: suite)
        let archive = SessionArchive(directory: directory, now: { clock.value },
                                     writeOverride: writeOverride)
        let engine = SessionEngine(store: PersistenceStore(defaults: defaults), archive: archive,
                                   ownBundleID: "com.example.story-correction",
                                   schedulesDwell: false, now: { clock.value })
        let store = SessionStore(engine: engine, now: { clock.value })
        return Fixture(store: store, engine: engine, archive: archive, directory: directory, cleanUp: {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        })
    }

    private static func session(thread: UUID, name: String, workType: WorkType,
                                start: Date, isRunning: Bool = false) -> DaySession {
        DaySession(id: thread, threadID: thread, name: name, workType: workType,
                   start: start, end: start.addingTimeInterval(600), worked: 600,
                   stretches: 1, spans: [DateInterval(start: start, duration: 600)],
                   isRunning: isRunning)
    }

    private static func archiveBytes(in directory: URL) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent("sessions.json"))
    }

    /// Catches an implementation that uses the displayed row's `isRunning`
    /// flag instead of the engine's actual active thread identity.
    private static func runningAndResumedThreadsUpdateTogether() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let clock = TestClock(Date(timeIntervalSince1970: 1_788_000_000))
            guard let fixture = makeFixture(clock) else {
                return ["could not create isolated correction preferences"]
            }
            defer { fixture.cleanUp() }

            let thread = UUID()
            fixture.engine.start(workType: .deepWork, intent: "Draft", threadID: thread)
            clock.advance(600)
            let historicalRow = session(thread: thread, name: "Draft", workType: .deepWork,
                                        start: clock.value.addingTimeInterval(-600))
            expect(fixture.store.renameSession(historicalRow, to: "Final draft"),
                   "fresh running thread should accept a rename without an archived record", &problems)
            expect(fixture.engine.sessionName == "Final draft",
                   "fresh running thread rename did not update the active engine", &problems)

            fixture.engine.stop()
            clock.advance(60)
            fixture.engine.start(workType: .deepWork, intent: "Final draft", threadID: thread)
            clock.advance(600)
            expect(fixture.store.setWorkType(.admin, for: historicalRow),
                   "resumed thread should accept a type correction", &problems)
            expect(fixture.archive.records.allSatisfy { $0.threadID != thread || $0.workType == .admin },
                   "resumed correction did not update archived stretches", &problems)
            expect(fixture.engine.activeWorkType == .admin,
                   "resumed correction did not update the actual active thread", &problems)
            expect(!fixture.store.canContinue(historicalRow),
                   "a historical fragment of the active thread was incorrectly continuable", &problems)
            return problems
        }
    }

    /// Catches a false success after an archive write failure, as well as an
    /// undo affordance for a request that changed nothing.
    private static func noOpsAndFailedWritesStayHonest() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let clock = TestClock(Date(timeIntervalSince1970: 1_788_100_000))
            guard let fixture = makeFixture(clock) else {
                return ["could not create isolated correction preferences"]
            }
            defer { fixture.cleanUp() }

            let thread = UUID()
            let row = session(thread: thread, name: "Archive", workType: .deepWork,
                              start: clock.value.addingTimeInterval(-600))
            fixture.archive.append(SessionRecord(name: "Archive", workType: .deepWork,
                                                 start: row.start, end: row.end,
                                                 workSeconds: 600, threadID: thread))
            expect(!fixture.store.renameSession(row, to: "Archive"),
                   "same-name correction should be an honest no-op", &problems)
            expect(!fixture.store.canUndoCorrection,
                   "no-op correction exposed an undo affordance", &problems)

            try? FileManager.default.removeItem(at: fixture.directory)
            FileManager.default.createFile(atPath: fixture.directory.path, contents: Data())
            expect(!fixture.store.renameSession(row, to: "Blocked rename"),
                   "blocked archive write reported success", &problems)
            expect(fixture.archive.records.first?.name == "Archive",
                   "blocked archive write changed the in-memory evidence", &problems)
            expect(fixture.store.correctionError != nil,
                   "blocked archive write did not expose a visible error", &problems)
            expect(!fixture.store.retryLastCorrection(),
                   "retry reported success while storage was still blocked", &problems)
            return problems
        }
    }

    /// Catches an undo that replaces the archive wholesale and therefore drops
    /// work written after the original correction.
    private static func undoRestoresAffectedFields() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let clock = TestClock(Date(timeIntervalSince1970: 1_788_200_000))
            guard let fixture = makeFixture(clock) else {
                return ["could not create isolated correction preferences"]
            }
            defer { fixture.cleanUp() }

            let thread = UUID()
            let row = session(thread: thread, name: "Planning", workType: .deepWork,
                              start: clock.value.addingTimeInterval(-1_200))
            fixture.archive.append(SessionRecord(name: "Planning", workType: .deepWork,
                                                 start: row.start, end: row.end,
                                                 workSeconds: 600, threadID: thread))
            expect(fixture.store.setWorkType(.breakTime, for: row),
                   "conversion to Break should succeed", &problems)
            fixture.archive.append(SessionRecord(name: "Later work", workType: .learning,
                                                 start: clock.value.addingTimeInterval(-300),
                                                 end: clock.value, workSeconds: 300))
            expect(fixture.store.undoLastCorrection(), "Break correction should be undoable", &problems)
            expect(fixture.archive.records.contains { $0.threadID == thread && $0.workType == .deepWork },
                   "undo did not restore the corrected thread's original type", &problems)
            expect(fixture.archive.records.contains { $0.name == "Later work" && $0.workType == .learning },
                   "undo erased work recorded after the correction", &problems)
            return problems
        }
    }

    /// Catches live focus totals that test only `state != .idle`, allowing a
    /// reclassified active Break to remain credited until it is stopped.
    private static func activeBreakExcludesLiveFocus() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let clock = TestClock(Date(timeIntervalSince1970: 1_788_300_000))
            guard let fixture = makeFixture(clock) else {
                return ["could not create isolated correction preferences"]
            }
            defer { fixture.cleanUp() }

            let thread = UUID()
            fixture.engine.start(workType: .deepWork, intent: "Live planning", threadID: thread)
            clock.advance(600)
            fixture.store.refresh()
            let row = session(thread: thread, name: "Live planning", workType: .deepWork,
                              start: clock.value.addingTimeInterval(-600))
            expect(fixture.store.setWorkType(.breakTime, for: row),
                   "active conversion to Break should succeed", &problems)
            expect(fixture.engine.elapsedToday() == 0,
                   "active Break still contributed elapsed focus", &problems)
            expect(fixture.store.todayTotal == 0 && fixture.store.sessionsToday == 0
                    && fixture.store.longestToday == 0,
                   "published live focus totals still credited an active Break", &problems)
            expect(fixture.store.undoLastCorrection(),
                   "active Break correction should be undoable", &problems)
            expect(fixture.engine.elapsedToday() == 600,
                   "undo did not restore active elapsed focus", &problems)
            expect(fixture.store.todayTotal == 600 && fixture.store.sessionsToday == 1
                    && fixture.store.longestToday == 600,
                   "undo did not restore published live focus totals", &problems)
            return problems
        }
    }

    /// Catches undo implementations that either cannot reverse a fresh live
    /// correction once it is archived, or restore both fields and clobber a
    /// later independent correction.
    private static func undoPreservesNewerEvidence() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let clock = TestClock(Date(timeIntervalSince1970: 1_788_400_000))
            guard let fixture = makeFixture(clock) else {
                return ["could not create isolated correction preferences"]
            }
            defer { fixture.cleanUp() }

            let liveThread = UUID()
            let liveRow = session(thread: liveThread, name: "Live", workType: .deepWork,
                                  start: clock.value)
            fixture.engine.start(workType: .deepWork, intent: "Live", threadID: liveThread)
            clock.advance(600)
            expect(fixture.store.setWorkType(.breakTime, for: liveRow),
                   "fresh active-only correction should succeed", &problems)
            fixture.engine.stop()
            expect(fixture.store.undoLastCorrection(),
                   "undo should restore a fresh correction after it was archived", &problems)
            expect(fixture.archive.records.contains { $0.threadID == liveThread
                    && $0.workType == .deepWork },
                   "active-only undo did not restore the later archived record", &problems)

            let renamedThread = UUID()
            let renamedRow = session(thread: renamedThread, name: "Original", workType: .deepWork,
                                     start: clock.value.addingTimeInterval(-1_200))
            fixture.archive.append(SessionRecord(name: "Original", workType: .deepWork,
                                                 start: renamedRow.start, end: renamedRow.end,
                                                 workSeconds: 600, threadID: renamedThread))
            expect(fixture.store.renameSession(renamedRow, to: "Renamed"),
                   "archive rename should succeed", &problems)
            fixture.archive.setWorkType(.admin, forThread: renamedThread)
            expect(fixture.store.undoLastCorrection(), "rename should be undoable", &problems)
            expect(fixture.archive.records.contains { $0.threadID == renamedThread
                    && $0.name == "Original" && $0.workType == .admin },
                   "rename undo reset a later work-type correction", &problems)

            let typedThread = UUID()
            let typedRow = session(thread: typedThread, name: "Type original", workType: .deepWork,
                                   start: clock.value.addingTimeInterval(-2_400))
            fixture.archive.append(SessionRecord(name: "Type original", workType: .deepWork,
                                                 start: typedRow.start, end: typedRow.end,
                                                 workSeconds: 600, threadID: typedThread))
            expect(fixture.store.setWorkType(.breakTime, for: typedRow),
                   "archive type correction should succeed", &problems)
            fixture.archive.rename(thread: typedThread, to: "Later name")
            expect(fixture.store.undoLastCorrection(), "type correction should be undoable", &problems)
            expect(fixture.archive.records.contains { $0.threadID == typedThread
                    && $0.name == "Later name" && $0.workType == .deepWork },
                   "type undo reset a later rename", &problems)
            return problems
        }
    }

    /// Catches a persisted correction that returns to the default Deep work
    /// type or a new thread identity after a relaunch.
    private static func activeCorrectionPersistsAcrossRestore() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let clock = TestClock(Date(timeIntervalSince1970: 1_788_500_000))
            guard let fixture = makeFixture(clock) else {
                return ["could not create isolated correction preferences"]
            }
            defer { fixture.cleanUp() }

            let thread = UUID()
            fixture.engine.start(workType: .deepWork, intent: "Persisted", threadID: thread)
            clock.advance(600)
            let row = session(thread: thread, name: "Persisted", workType: .deepWork,
                              start: clock.value.addingTimeInterval(-600))
            expect(fixture.store.setWorkType(.breakTime, for: row),
                   "active Break correction should save before restore", &problems)
            guard let snapshot = fixture.engine.store.loadState() else {
                return problems + ["active correction did not persist a state snapshot"]
            }
            let restored = SessionEngine(store: fixture.engine.store, archive: fixture.archive,
                                         ownBundleID: "com.example.story-correction",
                                         schedulesDwell: false, now: { clock.value })
            restored.restore(from: snapshot)
            expect(restored.activeWorkType == .breakTime,
                   "restored active work type reverted to Deep work", &problems)
            expect(restored.activeThreadID == thread,
                   "restored active thread identity fractured the corrected thread", &problems)

            expect(fixture.store.undoLastCorrection(),
                   "persisted active correction should still undo", &problems)
            guard let undoSnapshot = fixture.engine.store.loadState() else {
                return problems + ["undo did not persist a replacement state snapshot"]
            }
            let undone = SessionEngine(store: fixture.engine.store, archive: fixture.archive,
                                       ownBundleID: "com.example.story-correction",
                                       schedulesDwell: false, now: { clock.value })
            undone.restore(from: undoSnapshot)
            expect(undone.activeWorkType == .deepWork && undone.activeThreadID == thread,
                   "undo type or thread identity did not survive restore", &problems)
            return problems
        }
    }

    /// Catches rejecting the retained last thread while idle, and leaving a
    /// continuation with the correction after Undo either side of Stop.
    private static func continueAndUndoLifecycle() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let clock = TestClock(Date(timeIntervalSince1970: 1_788_600_000))
            guard let fixture = makeFixture(clock) else {
                return ["could not create isolated correction preferences"]
            }
            defer { fixture.cleanUp() }

            let thread = UUID()
            let row = session(thread: thread, name: "Original", workType: .deepWork,
                              start: clock.value.addingTimeInterval(-600))
            fixture.archive.append(SessionRecord(name: "Original", workType: .deepWork,
                                                 start: row.start, end: row.end,
                                                 workSeconds: 600, threadID: thread))
            fixture.engine.start(workType: .deepWork, intent: "Original", threadID: thread)
            clock.advance(600)
            fixture.engine.stop()
            let resumedRow = DaySession(id: row.id, threadID: thread, name: "Original",
                                        workType: .deepWork, start: row.start, end: clock.value,
                                        worked: 1_200, stretches: 2,
                                        spans: [DateInterval(start: row.start, end: row.end),
                                                DateInterval(start: row.end, end: clock.value)],
                                        isRunning: false)
            expect(fixture.store.canContinue(resumedRow),
                   "stopped thread was rejected because the engine retained its ID", &problems)

            expect(fixture.store.setWorkType(.admin, for: resumedRow),
                   "archive-only correction should succeed", &problems)
            let correctedRow = DaySession(id: resumedRow.id, threadID: thread, name: "Original",
                                          workType: .admin, start: resumedRow.start,
                                          end: resumedRow.end, worked: resumedRow.worked,
                                          stretches: resumedRow.stretches, spans: resumedRow.spans,
                                          isRunning: false)
            fixture.store.continueSession(correctedRow)
            expect(fixture.engine.activeWorkType == .admin,
                   "Continue did not adopt the corrected type", &problems)
            expect(fixture.store.undoLastCorrection(),
                   "Undo should restore an active continuation", &problems)
            expect(fixture.engine.activeWorkType == .deepWork,
                   "Undo left the active continuation corrected", &problems)

            fixture.engine.stop()
            let stoppedThread = UUID()
            let stoppedStart = clock.value.addingTimeInterval(-1_800)
            let stoppedRow = session(thread: stoppedThread, name: "Idle original",
                                     workType: .deepWork, start: stoppedStart)
            fixture.archive.append(SessionRecord(name: "Idle original", workType: .deepWork,
                                                 start: stoppedStart,
                                                 end: stoppedStart.addingTimeInterval(600),
                                                 workSeconds: 600, threadID: stoppedThread))
            expect(fixture.store.setWorkType(.admin, for: stoppedRow),
                   "second archive-only correction should succeed while idle", &problems)
            let stoppedCorrectedRow = session(thread: stoppedThread, name: "Idle original",
                                              workType: .admin, start: stoppedStart)
            fixture.store.continueSession(stoppedCorrectedRow)
            clock.advance(600)
            fixture.engine.stop()
            let timingBeforeUndo = Dictionary(uniqueKeysWithValues: fixture.archive.records
                .filter { $0.threadID == stoppedThread }
                .map { ($0.id, $0) })
            expect(fixture.store.undoLastCorrection(),
                   "Undo should restore a stopped continuation", &problems)
            let restored = fixture.archive.records.filter { $0.threadID == stoppedThread }
            expect(restored.count == 2 && restored
                    .allSatisfy { $0.workType == .deepWork },
                   "Undo left a stopped continuation with the corrected type", &problems)
            expect(restored.allSatisfy { restoredRecord in
                timingBeforeUndo[restoredRecord.id].map {
                    $0.start == restoredRecord.start && $0.end == restoredRecord.end
                        && $0.workSeconds == restoredRecord.workSeconds
                } ?? false
            }, "Undo changed a continuation's timing evidence", &problems)
            return problems
        }
    }

    /// Catches routing restoration through the user-input validation path,
    /// which refuses an empty name despite empty intents being supported.
    private static func undoRestoresEmptyActiveName() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let clock = TestClock(Date(timeIntervalSince1970: 1_788_700_000))
            guard let fixture = makeFixture(clock) else {
                return ["could not create isolated correction preferences"]
            }
            defer { fixture.cleanUp() }

            let thread = UUID()
            fixture.engine.start(workType: .deepWork, intent: "", threadID: thread)
            clock.advance(600)
            let row = session(thread: thread, name: "", workType: .deepWork,
                              start: clock.value.addingTimeInterval(-600))
            expect(fixture.store.renameSession(row, to: "Draft"),
                   "empty active intent should accept a non-empty rename", &problems)
            expect(fixture.store.undoLastCorrection(),
                   "undo should restore an empty active intent", &problems)
            expect(fixture.engine.sessionName.isEmpty,
                   "undo routed empty name through input validation", &problems)
            return problems
        }
    }

    /// Catches an Undo that writes the original and subsequent archived
    /// stretches separately. The gate rejects only a single complete candidate;
    /// the old split implementation partly published its first write.
    private static func combinedUndoIsAtomicAndRetryable() -> [String] {
        MainActor.assumeIsolated {
            final class WriteGate {
                var blockCompleteUndo = false
                var thread = UUID()
                func error(for candidate: [SessionRecord]) -> String? {
                    guard blockCompleteUndo else { return nil }
                    let mine = candidate.filter { $0.threadID == thread }
                    return mine.count >= 2 && mine.allSatisfy { $0.workType == .deepWork }
                        ? "deterministic combined undo block" : nil
                }
            }

            var problems: [String] = []
            let clock = TestClock(Date(timeIntervalSince1970: 1_788_800_000))
            let gate = WriteGate()
            guard let fixture = makeFixture(clock, writeOverride: { gate.error(for: $0) }) else {
                return ["could not create isolated correction preferences"]
            }
            defer { fixture.cleanUp() }

            let thread = UUID()
            gate.thread = thread
            let row = session(thread: thread, name: "Atomic", workType: .deepWork,
                              start: clock.value.addingTimeInterval(-600))
            fixture.archive.append(SessionRecord(name: "Atomic", workType: .deepWork,
                                                 start: row.start, end: row.end,
                                                 workSeconds: 600, threadID: thread))
            fixture.engine.start(workType: .deepWork, intent: "Atomic", threadID: thread)
            clock.advance(600)
            expect(fixture.store.setWorkType(.breakTime, for: row),
                   "combined Undo fixture correction should succeed", &problems)
            fixture.engine.stop()
            let bytesBeforeUndo = archiveBytes(in: fixture.directory)
            let recordsBeforeUndo = fixture.archive.records
            let activeBeforeUndo = fixture.engine.activeWorkType
            gate.blockCompleteUndo = true
            expect(!fixture.store.undoLastCorrection(),
                   "blocked complete undo reported success", &problems)
            expect(archiveBytes(in: fixture.directory) == bytesBeforeUndo
                    && fixture.archive.records == recordsBeforeUndo,
                   "blocked complete undo changed persisted or cached evidence", &problems)
            expect(fixture.engine.activeWorkType == activeBeforeUndo
                    && fixture.store.canUndoCorrection,
                   "blocked complete undo changed active state or cleared availability", &problems)
            gate.blockCompleteUndo = false
            expect(fixture.store.retryLastCorrection(),
                   "retry after combined undo storage recovery did not succeed", &problems)
            expect(fixture.archive.records.filter { $0.threadID == thread }
                    .allSatisfy { $0.workType == .deepWork },
                   "successful retry did not restore every affected stretch", &problems)
            return problems
        }
    }
}
