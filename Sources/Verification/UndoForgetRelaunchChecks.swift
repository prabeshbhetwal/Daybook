import Foundation
/// An Undo of a category change takes back the choice it taught. The Undo's records are written first, and the
/// receipt that says what to take back goes with it: when the remembered choices cannot be saved just then, the
/// Undo still stands, and the choice has to be taken back at the next launch, not stay offered.
enum UndoForgetRelaunchChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("An Undo of a category change whose remembered choice could not be saved is taken back at the next launch",
         forgottenAfterARelaunch),
    ]

    private static func forgottenAfterARelaunch() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let (store, clock, suite) = CorrectionsStoreChecks.make()
            defer { MemoryDefaults.remove(named: suite) }
            guard let first = CorrectionsStoreChecks.ended(store, clock, begin: CorrectionsStoreChecks.automatic("Parser")),
                  let third = CorrectionsStoreChecks.ended(store, clock, begin: CorrectionsStoreChecks.automatic("Linker"))
            else { return ["no sessions were made"] }
            expect(store.setWorkType(.learning, for: first), "the category change was refused: \(store.correctionError ?? "no reason")", &problems)
            let directory = store.engine.archive.dataDirectoryURL
            let file = directory.appendingPathComponent(CorrectionsStore.fileName)
            guard let taught = try? Data(contentsOf: file), store.correctionSuggestion(for: third) == .learning else {
                return problems + ["the change taught nothing to take back"]
            }
            // The file cannot be written: a folder stands where it is, so every save of it is refused.
            try? FileManager.default.removeItem(at: file)
            try? FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
            expect(store.undoLastCorrection(), "the Undo was refused: \(store.correctionError ?? "no reason")", &problems)
            // The disk is well again at the next launch: the file as the change left it.
            try? FileManager.default.removeItem(at: file)
            try? taught.write(to: file)
            let archive = SessionArchive(directory: directory, now: { clock.value })
            let engine = SessionEngine(store: PersistenceStore(defaults: MemoryDefaults.suite(named: suite) ?? .standard),
                                       archive: archive, ownBundleID: "com.test", schedulesDwell: false,
                                       now: { clock.value })
            AppCoordinator.restorePersistedEngine(engine, awayAtLaunch: false)
            let relaunched = SessionStore(engine: engine, now: { clock.value })
            relaunched.refresh()
            let kept = CorrectionsStoreChecks.stored(relaunched).entries
            expect(kept.isEmpty && relaunched.correctionSuggestion(for: third) == nil,
                   "the Undo's choice was still remembered after a relaunch: \(kept.map(\.chosen))", &problems)
            return problems
        }
    }
}
