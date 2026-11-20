import Foundation
/// The running card is drawn again every second, and its origin is read each time. The stretch running now is
/// written to the archive only when it ends, so the search for its stretches must not wait for it: that search
/// then ended only at the oldest record, on every update, however long the archive.
enum LiveOriginChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The origin of the running session is read without searching the archive for its unsaved stretch",
         liveOriginDoesNotSearchTheArchive),
    ]

    private static func liveOriginDoesNotSearchTheArchive() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let rig = SplitStoreChecks.rig()
            defer { MemoryDefaults.remove(named: rig.suite) }
            let store = rig.store
            // Sixty ended sessions over forty days, then a new one running.
            let first = rig.clock.value.addingTimeInterval(-40 * 86_400)
            let archived = (0..<60).map { number -> SessionRecord in
                let start = first.addingTimeInterval(Double(number) * 28_800)
                return SessionRecord(name: "Earlier \(number)", workType: .deepWork, start: start,
                                     end: start.addingTimeInterval(1_800), workSeconds: 1_800, threadID: UUID(),
                                     isAuto: false, origin: .manual, categorySource: .user)
            }
            SplitStoreChecks.seed(rig, archived)
            store.engine.start(workType: .deepWork, intent: "Live")
            rig.clock.advance(300)
            store.refresh()
            let running = store.storyMoments.compactMap { moment -> DaySession? in
                if case .entry(.session(let session)) = moment, session.isRunning { return session }
                return nil
            }.first
            guard let running, running.recordIDs.contains(store.engine.activeRecordID) else {
                return ["today's story has no running session holding the running stretch's id"]
            }
            let held = store.engine.archive.records.count
            expect(held >= archived.count, "the archive kept \(held) of \(archived.count) records", &problems)
            let text = store.originText(for: running)
            expect(text?.lines.map(\.text) == ["Started by you"], "the running session read \(String(describing: text?.lines.map(\.text)))", &problems)
            // Nothing to search for, so the search ends before the first of the archived records.
            let search = store.originSearch(for: running)
            expect(search.isEmpty, "the running session's origin searched \(held) archived records for \(search.count) stretches", &problems)
            // An ended session is still found, among the newest records.
            guard let newest = store.engine.archive.records.last else { return problems + ["the archive is empty"] }
            let row = SplitStoreChecks.row(newest)
            let ended = store.originText(for: row)
            expect(ended?.lines.map(\.text) == ["Started by you"] && store.originSearch(for: row) == [newest.id],
                   "an ended session read \(String(describing: ended?.lines.map(\.text))), searching for \(store.originSearch(for: row))", &problems)
            return problems
        }
    }
}
