import Foundation

/// Retry of a split or a Merge Back that was refused before its records changed. It used to replay a removal
/// that does nothing, so the error cleared and the session stayed as it was.
enum RestructureRetryChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Retry of a cut refused before its write splits the session, whether the journal or the archive refused it",
         retryCutsTheSession),
        ("Retry of a Merge Back refused before its write joins the halves", retryJoinsTheHalves),
    ]

    private final class Refusals { var journal = false, archive = false }

    @MainActor
    private static func makeRig(_ refusals: Refusals) -> SplitStoreChecks.Rig {
        SplitStoreChecks.rig(writeOverride: { _ in refusals.archive ? "The disk is full." : nil },
                             journal: { refusals.journal ? "The disk is full." : nil })
    }

    private static func retryCutsTheSession() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            for byJournal in [true, false] {
                let what = byJournal ? "the journal" : "the archive"
                let refusals = Refusals()
                let rig = makeRig(refusals)
                defer { MemoryDefaults.remove(named: rig.suite) }
                let store = rig.store, record = SplitStoreChecks.ended(rig)
                SplitStoreChecks.seed(rig, [record])
                refusals.journal = byJournal; refusals.archive = !byJournal
                expect(!store.splitSession(recordID: record.id, at: record.start.addingTimeInterval(2_400),
                                           tail: SplitStoreChecks.choice()),
                       "a cut refused by \(what) reported success", &problems)
                expect(store.engine.archive.records == [record] && store.correctionError != nil && store.correctionRetry != nil,
                       "the cut refused by \(what) changed the archive or offered no Retry", &problems)
                refusals.journal = false; refusals.archive = false
                expect(store.retryLastCorrection(),
                       "Retry after \(what) refused the cut did not finish it: \(store.correctionError ?? "no error shown")", &problems)
                expect(SplitStoreChecks.halves(of: record, in: store) != nil,
                       "Retry after \(what) refused the cut left the session whole", &problems)
                expect(store.correctionError == nil && store.correctionRetry == nil,
                       "Retry after \(what) refused the cut left its error or Retry shown", &problems)
            }
            return problems
        }
    }

    private static func retryJoinsTheHalves() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let refusals = Refusals()
            let rig = makeRig(refusals)
            defer { MemoryDefaults.remove(named: rig.suite) }
            let store = rig.store, record = SplitStoreChecks.ended(rig)
            SplitStoreChecks.seed(rig, [record])
            guard store.splitSession(recordID: record.id, at: record.start.addingTimeInterval(2_400), tail: SplitStoreChecks.choice()),
                  let split = SplitStoreChecks.halves(of: record, in: store) else {
                return ["the cut was refused: \(store.correctionError ?? "no reason")"]
            }
            refusals.journal = true
            expect(!store.mergeBack(tailID: split.tail.id) && store.engine.archive.records.contains(split.tail)
                   && store.correctionRetry != nil, "a Merge Back refused by the journal changed the archive or offered no Retry", &problems)
            refusals.journal = false
            expect(store.retryLastCorrection(),
                   "Retry after a refused Merge Back did not finish it: \(store.correctionError ?? "no error shown")", &problems)
            expect(store.engine.archive.records.map(\.id) == [record.id],
                   "Retry after a refused Merge Back left \(store.engine.archive.records.count) records", &problems)
            return problems
        }
    }
}
