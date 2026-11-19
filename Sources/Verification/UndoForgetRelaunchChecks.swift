import Foundation
/// An Undo of a category change takes back the choice it taught. The Undo's records are written first, and the
/// receipt that says what to take back goes with it: when the remembered choices cannot be saved just then, the
/// Undo still stands, and the choice has to be taken back at the next launch, not stay offered.
enum UndoForgetRelaunchChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("An Undo of a category change whose remembered choice could not be saved is taken back at the next launch",
         forgottenAfterARelaunch),
        ("A category change made while an Undo's forgetting is still owed starts from the choices that stand, and keeps none the Undo withdrew",
         filingWhileForgettingIsOwed),
        ("Work a sidecar that cannot be written leaves owed does not hold back the forgetting of an Undone category change",
         forgettingIsNotHeldBackBySidecarWork),
    ]

    private final class Disk { var refuses = false }

    /// The remembered choices cannot be saved: a folder stands where their file is, so every save is refused.
    private static func refuseSaves(of file: URL) {
        try? FileManager.default.removeItem(at: file)
        try? FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
    }

    /// The disk is well again: the file as it was.
    private static func allowSaves(of file: URL, as bytes: Data) {
        try? FileManager.default.removeItem(at: file)
        try? bytes.write(to: file)
    }

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
            refuseSaves(of: file)
            expect(store.undoLastCorrection(), "the Undo was refused: \(store.correctionError ?? "no reason")", &problems)
            allowSaves(of: file, as: taught)
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

    /// The next category change is the first thing to touch the store after the disk recovers: it must not write back
    /// the choices as they stood before the Undo's forgetting was done.
    private static func filingWhileForgettingIsOwed() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let (store, clock, suite) = CorrectionsStoreChecks.make()
            defer { MemoryDefaults.remove(named: suite) }
            guard let first = CorrectionsStoreChecks.ended(store, clock, begin: CorrectionsStoreChecks.automatic("Parser")),
                  let second = CorrectionsStoreChecks.ended(store, clock, begin: CorrectionsStoreChecks.automatic("Router"))
            else { return ["no sessions were made"] }
            expect(store.setWorkType(.learning, for: first), "the first change was refused: \(store.correctionError ?? "no reason")", &problems)
            let file = store.engine.archive.dataDirectoryURL.appendingPathComponent(CorrectionsStore.fileName)
            guard let taught = try? Data(contentsOf: file) else { return problems + ["the change taught nothing"] }
            refuseSaves(of: file)
            expect(store.undoLastCorrection(), "the Undo was refused: \(store.correctionError ?? "no reason")", &problems)
            allowSaves(of: file, as: taught)
            expect(store.setWorkType(.learning, for: second), "the second change was refused: \(store.correctionError ?? "no reason")", &problems)
            let kept = CorrectionsStoreChecks.stored(store).entries
            expect(kept.count == 1 && kept.first?.count == 1,
                   "the remembered choices were \(kept.map(\.count)) filings, not the one that stands", &problems)
            return problems
        }
    }

    /// A sidecar that refuses every write leaves a split's work owed for good; the forgetting does not wait for it.
    private static func forgettingIsNotHeldBackBySidecarWork() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let disk = Disk(), directory = SelfTest.scratchDirectory()
            let metadata = SessionMetadataArchive(directory: directory,
                                                  writeOverride: { _ in disk.refuses ? "The disk refused it." : nil })
            let rig = SplitStoreChecks.rig(directory: directory, metadata: metadata)
            defer { MemoryDefaults.remove(named: rig.suite) }
            let store = rig.store
            let record = SplitStoreChecks.ended(rig)
            SplitStoreChecks.seed(rig, [record])
            guard let first = CorrectionsStoreChecks.ended(store, rig.clock, begin: CorrectionsStoreChecks.automatic("Parser")),
                  let third = CorrectionsStoreChecks.ended(store, rig.clock, begin: CorrectionsStoreChecks.automatic("Linker"))
            else { return ["no sessions were made"] }
            expect(store.setWorkType(.learning, for: first), "the category change was refused: \(store.correctionError ?? "no reason")", &problems)
            guard let filed = store.corrections.last, store.correctionSuggestion(for: third) == .learning else {
                return problems + ["the change taught nothing to take back"]
            }
            disk.refuses = true
            expect(store.splitSession(recordID: record.id, at: record.start.addingTimeInterval(2_400), tail: SplitStoreChecks.choice()),
                   "the split was refused: \(store.correctionError ?? "no reason")", &problems)
            expect(store.undoCorrection(expectedID: filed.id), "the Undo was refused: \(store.correctionError ?? "no reason")", &problems)
            let kept = CorrectionsStoreChecks.stored(store).entries
            expect(kept.isEmpty, "the Undo's choice stayed remembered behind work the sidecar could not take: \(kept.map(\.chosen))", &problems)
            return problems
        }
    }
}
