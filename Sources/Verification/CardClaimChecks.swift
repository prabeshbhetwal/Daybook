import Foundation

/// A save in a running automatic session's card claims it even when nothing
/// changes; Undo of a claiming rename gives the name back but not the
/// ownership; and a claim outlives a relaunch.
enum CardClaimChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Saving the name an automatic session already has in its card claims it", unchangedSaveClaims),
        ("Undo of a rename that claimed a session restores the name and leaves it claimed", undoKeepsClaim),
        ("A session claimed in its card is still claimed after a relaunch", claimSurvivesRelaunch),
    ]

    private struct Fixture {
        let store: SessionStore
        let clock: TestClock
        let persistence: PersistenceStore
        let archive: SessionArchive
        let suite: String
    }

    @MainActor
    private static func make() -> Fixture? {
        let suite = "fc-selftest-card-claim-\(UUID().uuidString)"
        guard let defaults = MemoryDefaults.suite(named: suite) else { return nil }
        let clock = TestClock(SelfTest.anchoredNow())
        let archive = SessionArchive(directory: SelfTest.scratchDirectory(), now: { clock.value })
        let persistence = PersistenceStore(defaults: defaults)
        let engine = SessionEngine(store: persistence, archive: archive, ownBundleID: "com.test",
                                   schedulesDwell: false, now: { clock.value })
        engine.start(workType: .deepWork, intent: "Detected work", isAuto: true)
        clock.advance(20 * 60)
        // The persisted ownership is what marks the stretch automatic.
        var snapshot = engine.snapshot()
        snapshot.isAuto = true
        engine.restore(from: snapshot)
        return Fixture(store: SessionStore(engine: engine, now: { clock.value }), clock: clock,
                       persistence: persistence, archive: archive, suite: suite)
    }

    @MainActor
    private static func running(_ fixture: Fixture) -> DaySession {
        let engine = fixture.store.engine
        let now = fixture.clock.value
        return DaySession(id: UUID(), threadID: engine.activeThreadID, name: engine.sessionName,
                          workType: engine.activeWorkType, start: engine.sessionStartDate, end: now,
                          worked: now.timeIntervalSince(engine.sessionStartDate), stretches: 1,
                          spans: [DateInterval(start: engine.sessionStartDate, end: now)], isRunning: true)
    }

    private static func unchangedSaveClaims() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            for byName in [true, false] {
                guard let fixture = make() else { return ["could not create isolated preferences"] }
                defer { MemoryDefaults.remove(named: fixture.suite) }
                let store = fixture.store
                let wasPaused = store.engine.state.isPaused
                let saved = byName
                    ? store.renameSession(running(fixture), to: store.engine.sessionName)
                    : store.setWorkType(store.engine.activeWorkType, for: running(fixture))
                let what = byName ? "name" : "category"
                expect(saved, "saving the unchanged \(what) reported failure", &problems)
                expect(!store.isAutoSession, "saving the unchanged \(what) left the session automatic", &problems)
                expect(store.engine.sessionName == "Detected work",
                       "the unchanged \(what) save renamed the session to \(store.engine.sessionName)", &problems)
                expect(store.engine.state.isPaused == wasPaused,
                       "the unchanged \(what) save changed whether the session is paused", &problems)
                expect(!store.canUndoCorrection,
                       "an unchanged \(what) save offered an Undo for a change that never happened", &problems)
            }
            return problems
        }
    }

    private static func undoKeepsClaim() -> [String] {
        MainActor.assumeIsolated {
            guard let fixture = make() else { return ["could not create isolated preferences"] }
            defer { MemoryDefaults.remove(named: fixture.suite) }
            var problems: [String] = []
            let store = fixture.store
            expect(store.renameSession(running(fixture), to: "Job application"),
                   "the rename saved: \(store.correctionError ?? "no reason")", &problems)
            expect(store.undoLastCorrection(), "Undo saved: \(store.correctionError ?? "no reason")", &problems)
            expect(store.engine.sessionName == "Detected work",
                   "Undo restores the name, got \(store.engine.sessionName)", &problems)
            expect(!store.isAutoSession, "Undo of the rename handed the session back to the rules", &problems)
            return problems
        }
    }

    /// Both claims: a rename, which commits a correction, and an unchanged
    /// save, which only persists the ownership.
    private static func claimSurvivesRelaunch() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            for name in ["Job application", "Detected work"] {
                guard let fixture = make() else { return ["could not create isolated preferences"] }
                defer { MemoryDefaults.remove(named: fixture.suite) }
                let store = fixture.store
                expect(store.renameSession(running(fixture), to: name),
                       "saving '\(name)' failed: \(store.correctionError ?? "no reason")", &problems)
                guard let saved = fixture.persistence.loadState() else {
                    return problems + ["the claimed session left no saved state"]
                }
                let relaunched = SessionEngine(store: fixture.persistence, archive: fixture.archive,
                                               ownBundleID: "com.test", schedulesDwell: false,
                                               now: { fixture.clock.value })
                relaunched.restore(from: saved)
                let restored = SessionStore(engine: relaunched, now: { fixture.clock.value })
                expect(restored.engine.sessionName == name,
                       "the relaunch kept the name '\(name)', got \(restored.engine.sessionName)", &problems)
                expect(!restored.isAutoSession,
                       "the relaunch made the session claimed as '\(name)' automatic again", &problems)
            }
            return problems
        }
    }
}
