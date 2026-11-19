import Foundation
/// What a split, a join or an Undo owes the sidecar (the link, the kept summaries, the power readings) is
/// journalled with its records. A write the sidecar refuses, or a process that ends between the records and the
/// sidecar, leaves that work owed: the next launch does it, and nothing is left half done.
enum RestructureSidecarChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A split whose link, summary and readings could not be saved gets them at the next launch, even with its journal save refused too",
         splitIsCompletedAtLaunch),
        ("A Merge Back, an Undo of it and an Undo of a split whose summaries and readings could not be saved are completed at the next launch",
         joinsAreCompletedAtLaunch),
        ("A Merge Back made once the disk is well again saves first what the cut still owed, so the link it needs is there",
         mergeBackSavesWhatTheCutOwed),
    ]
    /// Registered last, apart from `tests`, so earlier check numbers stay.
    static let laterTests: [(String, () -> [String])] = [
        ("A split or an Undo waits while an earlier change to the same session still owes its summaries, and goes ahead once they are saved",
         waitsForWhatIsOwed),
    ]

    private final class Disk { var refuses = false }

    /// A store whose sidecar refuses writes while `disk.refuses` is set, over one ended session with two power
    /// readings, one on each side of the cut the checks make at 2,400 seconds.
    private struct Fixture {
        let rig: SplitStoreChecks.Rig
        let disk: Disk
        let record: SessionRecord
        let early: PowerObservation, late: PowerObservation
        var store: SessionStore { rig.store }
    }

    private static func reading(at moment: Date, _ percentage: Double) -> PowerObservation {
        PowerObservation(timestamp: moment, source: .battery, percentage: percentage, charging: .notCharging)
    }

    @MainActor
    private static func fixture(journal: SplitRestructureChecks.Journal? = nil) -> Fixture {
        let disk = Disk(), directory = SelfTest.scratchDirectory()
        let metadata = SessionMetadataArchive(directory: directory,
                                              writeOverride: { _ in disk.refuses ? "The disk refused it." : nil })
        let gate: (() -> String?)? = journal.map { gate in { gate.save() } }
        let rig = SplitStoreChecks.rig(directory: directory, journal: gate, metadata: metadata)
        let record = SplitStoreChecks.ended(rig)
        SplitStoreChecks.seed(rig, [record])
        let early = reading(at: record.start.addingTimeInterval(600), 90)
        let late = reading(at: record.start.addingTimeInterval(3_000), 70)
        rig.store.metadataArchive.appendPower(early, for: record.id)
        rig.store.metadataArchive.appendPower(late, for: record.id)
        return Fixture(rig: rig, disk: disk, record: record, early: early, late: late)
    }

    /// The same folder, preferences and clock read by new objects, as the app does at launch.
    @MainActor
    private static func relaunched(_ fixture: Fixture) -> SessionStore {
        let again = SplitStoreChecks.rig(directory: fixture.rig.directory, suite: fixture.rig.suite, clock: fixture.rig.clock)
        AppCoordinator.restorePersistedEngine(again.store.engine, awayAtLaunch: false)
        again.store.refresh()
        return again.store
    }

    @MainActor
    private static func power(_ store: SessionStore, _ id: UUID) -> Set<UUID> {
        Set(store.sessionMetadata(for: id)?.power.map(\.id) ?? [])
    }

    private static func splitIsCompletedAtLaunch() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            for journalRefused in [false, true] {
                let journal = SplitRestructureChecks.Journal()
                let f = fixture(journal: journalRefused ? journal : nil)
                defer { MemoryDefaults.remove(named: f.rig.suite) }
                let way = journalRefused ? "with the journal save refused too" : "with the sidecar refusing"
                let kept = ActivitySnapshotChecks.shape(.activity(.coding), credited: ["coding": 3_000],
                                                        over: DateInterval(start: f.record.start, end: f.record.end))
                f.store.metadataArchive.saveActivityShape(kept, for: f.record.id)
                f.disk.refuses = true
                if journalRefused { journal.failSecondSave() }
                _ = f.store.splitSession(recordID: f.record.id, at: f.record.start.addingTimeInterval(2_400),
                                         tail: SplitStoreChecks.choice())
                guard let split = SplitStoreChecks.halves(of: f.record, in: f.store) else {
                    problems.append("the archive did not take the split \(way)"); continue
                }
                // The process ends here, the sidecar never having taken the link, the summary or the readings.
                let store = relaunched(f)
                expect(store.canMergeBack(recordID: split.tail.id) && store.sessionMetadata(for: split.tail.id)?.splitFrom?.head == f.record.id,
                       "the tail had no link after a relaunch, \(way), so Merge Back was not offered", &problems)
                expect(store.sessionMetadata(for: split.tail.id)?.activityShape != nil,
                       "the tail kept no summary after a relaunch, \(way)", &problems)
                expect(power(store, f.record.id) == [f.early.id] && power(store, split.tail.id) == [f.late.id],
                       "the readings did not follow their halves after a relaunch, \(way)", &problems)
            }
            return problems
        }
    }

    /// A session cut in two whose halves each kept a summary of their own part, and a reading on each.
    @MainActor
    private static func halves() -> (f: Fixture, split: (head: SessionRecord, tail: SessionRecord),
                                     own: SessionActivityShape, other: SessionActivityShape)? {
        let f = fixture()
        guard f.store.splitSession(recordID: f.record.id, at: f.record.start.addingTimeInterval(2_400),
                                   tail: SplitStoreChecks.choice()),
              let split = SplitStoreChecks.halves(of: f.record, in: f.store) else { return nil }
        let own = ActivitySnapshotChecks.shape(.activity(.coding), credited: ["coding": 1_500],
                                               over: DateInterval(start: split.head.start, end: split.head.end))
        let other = ActivitySnapshotChecks.shape(.activity(.design), credited: ["design": 900],
                                                 over: DateInterval(start: split.tail.start, end: split.tail.end))
        f.store.metadataArchive.saveActivityShape(own, for: split.head.id)
        f.store.metadataArchive.saveActivityShape(other, for: split.tail.id)
        return (f, split, own, other)
    }

    @MainActor
    private static func expectWhole(_ store: SessionStore, _ f: Fixture, _ what: String, _ problems: inout [String]) {
        guard let whole = store.engine.archive.records.first(where: { $0.id == f.record.id }) else {
            problems.append("\(what): the whole session is not in the archive"); return
        }
        let read = store.sessionActivity(for: SplitStoreChecks.row(whole))
        expect(read?.credited["coding"] == 1_500 && read?.credited["design"] == 900 && read?.depth == nil,
               "\(what): the session read \(String(describing: read?.credited)) after a relaunch, not both halves", &problems)
        expect(power(store, whole.id) == [f.early.id, f.late.id],
               "\(what): the readings were not all on the one record after a relaunch", &problems)
    }

    /// Nothing has refreshed since the disk recovered: Merge Back is the first thing to read the link the cut owes.
    private static func mergeBackSavesWhatTheCutOwed() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let f = fixture()
            defer { MemoryDefaults.remove(named: f.rig.suite) }
            f.disk.refuses = true
            guard f.store.splitSession(recordID: f.record.id, at: f.record.start.addingTimeInterval(2_400), tail: SplitStoreChecks.choice()),
                  let split = SplitStoreChecks.halves(of: f.record, in: f.store) else { return ["the cut was refused"] }
            f.disk.refuses = false
            expect(f.store.mergeBack(tailID: split.tail.id),
                   "Merge Back was refused after a cut whose link had not been saved yet: \(f.store.correctionError ?? "no reason")", &problems)
            expect(power(f.store, f.record.id) == [f.early.id, f.late.id],
                   "the readings were not all on the one record after the join", &problems)
            return problems
        }
    }

    /// A Merge Back made while the disk refused owes the joined summary: what an Undo or a cut works out from the
    /// sidecar before that is saved would miss it, so they wait, and the Undo then gives each half its own back.
    private static func waitsForWhatIsOwed() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let h = halves() else { return ["the cut was refused"] }
            defer { MemoryDefaults.remove(named: h.f.rig.suite) }
            h.f.disk.refuses = true
            expect(h.f.store.mergeBack(tailID: h.split.tail.id), "Merge Back was refused: \(h.f.store.correctionError ?? "no reason")", &problems)
            expect(!h.f.store.undoLastCorrection(), "Undo of Merge Back went ahead while the join still owed its summaries", &problems)
            expect(!h.f.store.splitSession(recordID: h.f.record.id, at: h.f.record.start.addingTimeInterval(1_200),
                                           tail: SplitStoreChecks.choice()),
                   "a cut went ahead while the join still owed its summaries", &problems)
            h.f.disk.refuses = false
            expect(h.f.store.undoLastCorrection(),
                   "Undo of Merge Back was refused once the disk was well: \(h.f.store.correctionError ?? "no reason")", &problems)
            expect(h.f.store.sessionMetadata(for: h.split.head.id)?.activityShape == h.own
                   && h.f.store.sessionMetadata(for: h.split.tail.id)?.activityShape == h.other,
                   "Undo of a Merge Back made while the disk refused did not give each half its own summary back", &problems)
            expect(h.f.store.metadataArchive.metadata(for: h.split.tail.id)?.headSummary == nil,
                   "the joined session's summary was left set aside on the second part", &problems)
            return problems
        }
    }

    private static func joinsAreCompletedAtLaunch() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            // Merge Back with the sidecar refusing.
            if let h = halves() {
                defer { MemoryDefaults.remove(named: h.f.rig.suite) }
                h.f.disk.refuses = true
                expect(h.f.store.mergeBack(tailID: h.split.tail.id), "Merge Back was refused: \(h.f.store.correctionError ?? "no reason")", &problems)
                expectWhole(relaunched(h.f), h.f, "Merge Back", &problems)
            } else { problems.append("the first cut was refused") }
            // Undo of the cut with the sidecar refusing.
            if let h = halves() {
                defer { MemoryDefaults.remove(named: h.f.rig.suite) }
                h.f.disk.refuses = true
                expect(h.f.store.undoLastCorrection(), "Undo of the cut was refused: \(h.f.store.correctionError ?? "no reason")", &problems)
                expectWhole(relaunched(h.f), h.f, "Undo of the cut", &problems)
            } else { problems.append("the second cut was refused") }
            // Undo of a Merge Back with the sidecar refusing: each half gets its own summary and reading back.
            if let h = halves() {
                defer { MemoryDefaults.remove(named: h.f.rig.suite) }
                expect(h.f.store.mergeBack(tailID: h.split.tail.id), "Merge Back was refused: \(h.f.store.correctionError ?? "no reason")", &problems)
                h.f.disk.refuses = true
                expect(h.f.store.undoLastCorrection(), "Undo of Merge Back was refused: \(h.f.store.correctionError ?? "no reason")", &problems)
                let store = relaunched(h.f)
                expect(store.sessionMetadata(for: h.split.head.id)?.activityShape == h.own
                       && store.sessionMetadata(for: h.split.tail.id)?.activityShape == h.other,
                       "Undo of Merge Back did not give each half its own summary back after a relaunch", &problems)
                expect(power(store, h.split.head.id) == [h.f.early.id] && power(store, h.split.tail.id) == [h.f.late.id],
                       "Undo of Merge Back did not send the readings back after a relaunch", &problems)
            } else { problems.append("the third cut was refused") }
            return problems
        }
    }
}
