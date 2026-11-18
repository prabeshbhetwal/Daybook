import Foundation

/// A split after a relaunch, after a refused write and where it is not allowed: written the way an away
/// answer is, so it is journalled, it survives and it never half happens (plan Task 5).
enum SplitStoreRelaunchChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A split survives a relaunch with its link and its Undo, and power readings follow the half they belong to",
         survivesRelaunch),
        ("A refused write leaves the record whole, shows why and writes no link; the next try lands", refusedWriteChangesNothing),
        ("A cut that is not allowed, a break, a missing record and an unlinked pair change nothing", refusals),
    ]

    typealias Rig = SplitStoreChecks.Rig

    private static func reading(at moment: Date, _ percentage: Double) -> PowerObservation {
        PowerObservation(timestamp: moment, source: .battery, percentage: percentage, charging: .notCharging)
    }

    private static func survivesRelaunch() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let first = SplitStoreChecks.rig()
            defer { MemoryDefaults.remove(named: first.suite) }
            let record = SplitStoreChecks.ended(first)
            SplitStoreChecks.seed(first, [record])
            let early = reading(at: record.start.addingTimeInterval(600), 90)
            let late = reading(at: record.start.addingTimeInterval(3_000), 70)
            first.store.metadataArchive.appendPower(early, for: record.id)
            first.store.metadataArchive.appendPower(late, for: record.id)
            guard first.store.splitSession(recordID: record.id, at: record.start.addingTimeInterval(2_400),
                                           tail: SplitStoreChecks.choice()),
                  let split = SplitStoreChecks.halves(of: record, in: first.store) else { return ["the split was refused"] }
            expect(first.store.sessionMetadata(for: split.head.id)?.power.map(\.id) == [early.id]
                   && first.store.sessionMetadata(for: split.tail.id)?.power.map(\.id) == [late.id],
                   "the readings did not follow their halves", &problems)

            let again = SplitStoreChecks.rig(directory: first.directory, suite: first.suite, clock: first.clock)
            let store = again.store
            // What the app does at launch, so the engine's generations are the journal's.
            AppCoordinator.restorePersistedEngine(store.engine, awayAtLaunch: false)
            store.refresh()
            expect(Set(store.engine.archive.records.map(\.id)) == [split.head.id, split.tail.id]
                   && store.engine.archive.records.contains(split.head) && store.engine.archive.records.contains(split.tail),
                   "the halves did not come back after a relaunch", &problems)
            expect(store.canMergeBack(recordID: split.tail.id) && store.sessionMetadata(for: split.tail.id)?.splitFrom?.head == split.head.id,
                   "the link did not survive a relaunch", &problems)
            expect(store.corrections.last?.restructure == .split && store.canUndoCorrection,
                   "Undo did not survive a relaunch", &problems)
            expect(store.undoLastCorrection(), "Undo after a relaunch was refused: \(store.correctionError ?? "")", &problems)
            expect(store.engine.archive.records == [record], "Undo after a relaunch did not give back the one record", &problems)
            expect(Set(store.sessionMetadata(for: record.id)?.power.map(\.id) ?? []) == [early.id, late.id],
                   "the readings did not come back to the one record", &problems)

            // Joined again, the tail's readings go to the head, and Undo sends them back.
            guard store.splitSession(recordID: record.id, at: record.start.addingTimeInterval(2_400),
                                     tail: SplitStoreChecks.choice()),
                  let second = SplitStoreChecks.halves(of: record, in: store) else { return problems + ["no second split"] }
            expect(store.mergeBack(tailID: second.tail.id)
                   && Set(store.sessionMetadata(for: record.id)?.power.map(\.id) ?? []) == [early.id, late.id],
                   "a merge did not take the readings back to the head", &problems)
            expect(store.undoLastCorrection()
                   && store.sessionMetadata(for: second.tail.id)?.power.map(\.id) == [late.id]
                   && store.sessionMetadata(for: record.id)?.power.map(\.id) == [early.id],
                   "undoing a merge did not send the readings back", &problems)
            return problems
        }
    }

    private final class Gate { var error: String? }

    private static func refusedWriteChangesNothing() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let gate = Gate()
            let rig = SplitStoreChecks.rig(writeOverride: { _ in gate.error })
            defer { MemoryDefaults.remove(named: rig.suite) }
            let record = SplitStoreChecks.ended(rig)
            SplitStoreChecks.seed(rig, [record])
            let store = rig.store
            gate.error = "The disk refused it."
            let cut = record.start.addingTimeInterval(2_400)
            expect(!store.splitSession(recordID: record.id, at: cut, tail: SplitStoreChecks.choice()),
                   "a split went ahead on a refused write", &problems)
            expect(store.engine.archive.records == [record] && store.corrections.isEmpty,
                   "a refused split left records or a correction behind", &problems)
            expect(store.correctionError != nil, "a refused split said nothing", &problems)
            expect(store.metadataArchive.allMetadata.allSatisfy { $0.splitFrom == nil },
                   "a refused split left a link behind", &problems)
            gate.error = nil
            // A pending journal entry from the refused try is settled by the next correction, not replayed.
            expect(store.splitSession(recordID: record.id, at: cut, tail: SplitStoreChecks.choice()),
                   "the next try was refused: \(store.correctionError ?? "")", &problems)
            expect(store.engine.archive.records.count == 2 && store.corrections.count == 1
                   && store.correctionError == nil, "the next try did not land cleanly", &problems)
            return problems
        }
    }

    private static func refusals() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let rig = SplitStoreChecks.rig()
            defer { MemoryDefaults.remove(named: rig.suite) }
            let record = SplitStoreChecks.ended(rig)
            let rest = SessionRecord(name: "Break", workType: .breakTime, start: record.end.addingTimeInterval(60),
                                     end: record.end.addingTimeInterval(660), workSeconds: 600, breakOrigin: .started)
            SplitStoreChecks.seed(rig, [record, rest])
            let store = rig.store
            let before = store.engine.archive.records
            let start = record.start
            let attempts: [(String, UUID, Date)] = [
                ("at its start", record.id, start), ("at its end", record.id, record.end),
                ("inside a pause", record.id, start.addingTimeInterval(1_500)),
                ("at a pause's edge", record.id, start.addingTimeInterval(1_200)),
                ("of a break", rest.id, rest.start.addingTimeInterval(300)),
                ("of nothing", UUID(), start.addingTimeInterval(2_400)),
            ]
            for (label, id, moment) in attempts {
                expect(!store.splitSession(recordID: id, at: moment, tail: SplitStoreChecks.choice()),
                       "a cut \(label) was written", &problems)
                expect(store.engine.archive.records == before && store.corrections.isEmpty,
                       "a refused cut \(label) changed something", &problems)
            }
            // Two records that merely touch are not a split pair: Merge Back needs the link.
            let next = SessionRecord(name: "Later", workType: .deepWork, start: rest.end, end: rest.end.addingTimeInterval(600),
                                     workSeconds: 600, threadID: UUID(), isAuto: false, origin: .manual, categorySource: .user)
            SplitStoreChecks.seed(rig, [next])
            expect(!store.canMergeBack(recordID: next.id) && !store.mergeBack(tailID: next.id)
                   && !store.canMergeBack(recordID: UUID()), "an unlinked record offered Merge Back", &problems)
            expect(store.corrections.isEmpty, "a refused merge made a correction", &problems)
            return problems
        }
    }
}
