import Foundation
/// The summary a record keeps once its beats expire, across a cut and a join. A cut leaves each half a
/// summary of its own part, and nothing rebuilds either without beats: a join that left the head's alone
/// would read only its former half for good.
enum JoinedSummaryChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Merge Back joins the halves' kept summaries over the whole session, and Undo of the join gives each half its own back",
         mergeJoinsTheSummaries),
        ("Undo of a cut joins the halves' kept summaries over the whole session",
         undoOfACutJoinsTheSummaries),
    ]

    private struct Cut {
        let rig: SplitStoreChecks.Rig
        let record: SessionRecord
        let split: (head: SessionRecord, tail: SessionRecord)
        let own: SessionActivityShape, other: SessionActivityShape
    }

    /// A session cut in two whose halves each kept a summary of their own part, as a sweep that read their
    /// beats leaves them.
    @MainActor
    private static func cut() -> Cut? {
        let rig = SplitStoreChecks.rig()
        let record = SplitStoreChecks.ended(rig)
        SplitStoreChecks.seed(rig, [record])
        guard rig.store.splitSession(recordID: record.id, at: record.start.addingTimeInterval(2_400), tail: SplitStoreChecks.choice()),
              let split = SplitStoreChecks.halves(of: record, in: rig.store) else { return nil }
        let own = ActivitySnapshotChecks.shape(.activity(.coding), credited: ["coding": 1_500],
                                               over: DateInterval(start: split.head.start, end: split.head.end))
        let other = ActivitySnapshotChecks.shape(.activity(.design), credited: ["design": 900],
                                                 over: DateInterval(start: split.tail.start, end: split.tail.end))
        rig.store.metadataArchive.saveActivityShape(own, for: split.head.id)
        rig.store.metadataArchive.saveActivityShape(other, for: split.tail.id)
        return Cut(rig: rig, record: record, split: split, own: own, other: other)
    }

    @MainActor
    private static func kept(_ id: UUID, in store: SessionStore) -> SessionActivityShape? {
        store.metadataArchive.metadata(for: id)?.activityShape
    }

    @MainActor
    private static func expectWhole(_ cut: Cut, _ what: String, _ problems: inout [String]) {
        let store = cut.rig.store
        guard let whole = store.engine.archive.records.first(where: { $0.id == cut.record.id }) else {
            problems.append("\(what): the whole session is not in the archive"); return
        }
        let read = store.sessionActivity(for: SplitStoreChecks.row(whole))
        expect(read?.bounds == DateInterval(start: whole.start, end: whole.end)
               && read?.credited["coding"] == 1_500 && read?.credited["design"] == 900 && read?.depth == nil,
               "\(what): the session read \(String(describing: read?.bounds)) \(String(describing: read?.credited)), not both halves over its whole time",
               &problems)
    }

    private static func mergeJoinsTheSummaries() -> [String] {
        MainActor.assumeIsolated {
            guard let cut = cut() else { return ["the cut was refused"] }
            defer { MemoryDefaults.remove(named: cut.rig.suite) }
            var problems: [String] = []
            let store = cut.rig.store
            expect(store.mergeBack(tailID: cut.split.tail.id), "Merge Back was refused: \(store.correctionError ?? "no reason")", &problems)
            expectWhole(cut, "after Merge Back", &problems)
            guard let join = store.corrections.last else { return problems + ["Merge Back kept no correction"] }
            expect(store.undoCorrection(expectedID: join.id), "the undo of Merge Back was refused: \(store.correctionError ?? "no reason")", &problems)
            expect(kept(cut.split.head.id, in: store) == cut.own && kept(cut.split.tail.id, in: store) == cut.other,
                   "Undo of Merge Back did not give each half its own summary back", &problems)
            return problems
        }
    }

    private static func undoOfACutJoinsTheSummaries() -> [String] {
        MainActor.assumeIsolated {
            guard let cut = cut() else { return ["the cut was refused"] }
            defer { MemoryDefaults.remove(named: cut.rig.suite) }
            var problems: [String] = []
            let store = cut.rig.store
            guard let made = store.corrections.last else { return ["the cut kept no correction"] }
            expect(store.undoCorrection(expectedID: made.id), "the undo of the cut was refused: \(store.correctionError ?? "no reason")", &problems)
            expectWhole(cut, "after Undo of the cut", &problems)
            return problems
        }
    }
}
