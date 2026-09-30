import Foundation

/// The window's strip keeps the automatic session's naming row folded until
/// Name is pressed, and folds it again once the session is adopted or ended.
/// The bar and the underline are two views of one store, so the flag lives
/// there and this checks the store as well as the layout rule.
enum AutomaticNamingChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The strip's automatic row unfolds on Name and folds after Adopt or Stop", foldsUntilAsked),
    ]

    private static func foldsUntilAsked() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let automatic = FocusSurfaceComposition(state: .running, hasPendingDecision: false,
                                                    isAutomatic: true)
            let manual = FocusSurfaceComposition(state: .running, hasPendingDecision: false,
                                                 isAutomatic: false)
            expect(!FocusHero.showsAutomaticRow(automatic, isStrip: true, naming: false),
                   "the strip keeps the row folded until asked", &problems)
            expect(FocusHero.showsAutomaticRow(automatic, isStrip: true, naming: true),
                   "Name unfolds the strip's row", &problems)
            expect(FocusHero.showsAutomaticRow(automatic, isStrip: false, naming: false),
                   "the popover still shows the controls outright", &problems)
            expect(!FocusHero.showsAutomaticRow(manual, isStrip: true, naming: true),
                   "a manual session has no row to unfold", &problems)

            func makeAutomatic() -> (store: SessionStore, suite: String) {
                let suite = "fc-selftest-naming-\(UUID().uuidString)"
                let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
                let archive = SessionArchive(directory: SelfTest.scratchDirectory(),
                                             now: { clock.value })
                let persistence = PersistenceStore(defaults: UserDefaults(suiteName: suite) ?? .standard)
                persistence.removeAll()
                let engine = SessionEngine(store: persistence, archive: archive,
                                           ownBundleID: "com.test", schedulesDwell: false,
                                           now: { clock.value })
                engine.start(workType: .deepWork, intent: "Detected coding", isAuto: true)
                clock.advance(12 * 60)
                // The persisted ownership is what marks the stretch automatic.
                var snapshot = engine.snapshot()
                snapshot.isAuto = true
                engine.restore(from: snapshot)
                return (SessionStore(engine: engine, now: { clock.value }), suite)
            }

            let adopted = makeAutomatic()
            expect(adopted.store.isAutoSession && !adopted.store.isNamingAutomaticSession,
                   "an automatic session starts with its row folded", &problems)
            expect(!FocusHero.underlineHasContent(adopted.store),
                   "nothing sits under the bar for an unnamed automatic session", &problems)
            adopted.store.isNamingAutomaticSession = true
            expect(FocusHero.underlineHasContent(adopted.store),
                   "Name puts the row under the bar", &problems)
            adopted.store.intent = "Coding"
            adopted.store.applyAutomaticSessionCorrection()
            expect(!adopted.store.isNamingAutomaticSession,
                   "Adopt folds the row", &problems)

            let ended = makeAutomatic()
            ended.store.isNamingAutomaticSession = true
            ended.store.stop()
            expect(!ended.store.isNamingAutomaticSession, "Stop folds the row", &problems)

            for suite in [adopted.suite, ended.suite] {
                UserDefaults.standard.removePersistentDomain(forName: suite)
            }
            return problems
        }
    }
}
