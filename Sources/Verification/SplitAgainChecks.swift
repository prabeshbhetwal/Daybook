import Foundation

/// A part cut again keeps its later part's link to it: joining the part back to the one before would
/// strand that link on a record that is gone, so the later part is joined first.
enum SplitAgainChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A part of a split that was cut again is not offered Merge Back until its later part is gone, and then merges back in order",
         partSplitAgainMergesBackInOrder),
    ]

    private static func partSplitAgainMergesBackInOrder() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let rig = SplitStoreChecks.rig()
            defer { MemoryDefaults.remove(named: rig.suite) }
            let record = SplitStoreChecks.ended(rig)
            SplitStoreChecks.seed(rig, [record])
            let store = rig.store
            guard store.splitSession(recordID: record.id, at: record.start.addingTimeInterval(2_400), tail: SplitStoreChecks.choice()),
                  let (_, middle) = SplitStoreChecks.halves(of: record, in: store),
                  store.splitSession(recordID: middle.id, at: middle.start.addingTimeInterval(600), tail: SplitStoreChecks.choice()),
                  let (_, last) = SplitStoreChecks.halves(of: middle, in: store) else { return ["the two cuts were refused"] }
            expect(store.canMergeBack(recordID: last.id), "the latest part was not offered Merge Back", &problems)
            expect(!store.canMergeBack(recordID: middle.id)
                   && store.mergeBackOffer(for: SplitStoreChecks.row(middle)) == nil,
                   "the part cut again was still offered Merge Back", &problems)
            let kept = store.engine.archive.records
            expect(!store.mergeBack(tailID: middle.id) && store.engine.archive.records == kept && store.correctionError != nil,
                   "Merge Back went ahead on the part cut again, or said nothing", &problems)

            // Undoing the second cut takes its part away: the middle one is whole again and offered.
            expect(store.undoLastCorrection() && store.canMergeBack(recordID: middle.id),
                   "undoing the second cut did not offer the part Merge Back again", &problems)
            guard store.splitSession(recordID: middle.id, at: middle.start.addingTimeInterval(600), tail: SplitStoreChecks.choice()),
                  let (_, again) = SplitStoreChecks.halves(of: middle, in: store) else { return problems + ["the second cut was refused again"] }
            expect(!store.canMergeBack(recordID: middle.id), "the part cut again was offered Merge Back after a second cut", &problems)
            expect(store.mergeBack(tailID: again.id), "the later part's Merge Back was refused: \(store.correctionError ?? "no reason")", &problems)
            expect(store.canMergeBack(recordID: middle.id) && store.mergeBack(tailID: middle.id),
                   "the part was not merged back once its later part was: \(store.correctionError ?? "no reason")", &problems)
            expect(store.engine.archive.records.map(\.id) == [record.id] && store.engine.archive.records.first?.end == record.end,
                   "the merges did not give back the one session: \(store.engine.archive.records.count) records", &problems)
            return problems
        }
    }
}
