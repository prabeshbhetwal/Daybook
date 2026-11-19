import Foundation

/// Splitting and joining, after the first review (Tasks 5 and 6): the link and the power readings follow a
/// cut whose archive write landed with its journal save still owed; a refused automatic split is deferred or
/// offered, never lost; the journal stays readable by a build from before Phase B; a join gives the record's
/// work back to the last bit; and the person's own error and a tail they accepted are left alone.
enum SplitRestructureChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A cut, a join and an Undo whose archive write landed with the journal save refused still move the link and the readings, and Retry finishes them",
         sidecarFollowsALandedWrite),
        ("An automatic split refused behind an away question is judged after the answer, and any other refusal becomes the offer",
         refusedAutomaticSplitIsNotLost),
        ("A split and a merge are journalled as removals, so a build from before Phase B reads the history and its Undo refuses",
         olderBuildReadsTheJournal),
        ("Merging back gives the record's work seconds back to the last bit, whatever the cut",
         mergeIsBitForBit),
        ("An automatic split leaves the person's own error and Retry, and a tail from an offer they accepted never splits itself",
         ownErrorAndAcceptedTail),
    ]

    /// A journal whose chosen save is refused: counted from the call to `failSecondSave()`, so the first
    /// save (the pending entry) goes through and the second (the finished one) does not. `failFirstSave()`
    /// refuses the pending entry, so nothing lands.
    final class Journal {
        var calls = 0
        var failOn: Int?
        func save() -> String? { calls += 1; return calls == failOn ? "The disk is full." : nil }
        func failSecondSave() { calls = 0; failOn = 2 }
        func failFirstSave() { calls = 0; failOn = 1 }
    }

    private static func reading(at moment: Date, _ percentage: Double) -> PowerObservation {
        PowerObservation(timestamp: moment, source: .battery, percentage: percentage, charging: .notCharging)
    }

    @MainActor
    private static func power(_ store: SessionStore, _ id: UUID) -> Set<UUID> {
        Set(store.sessionMetadata(for: id)?.power.map(\.id) ?? [])
    }

    private static func sidecarFollowsALandedWrite() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let journal = Journal()
            let rig = SplitStoreChecks.rig(journal: { journal.save() })
            defer { MemoryDefaults.remove(named: rig.suite) }
            let store = rig.store
            let record = SplitStoreChecks.ended(rig)
            SplitStoreChecks.seed(rig, [record])
            let early = reading(at: record.start.addingTimeInterval(600), 90)
            let late = reading(at: record.start.addingTimeInterval(3_000), 70)
            store.metadataArchive.appendPower(early, for: record.id)
            store.metadataArchive.appendPower(late, for: record.id)

            journal.failSecondSave()
            expect(!store.splitSession(recordID: record.id, at: record.start.addingTimeInterval(2_400),
                                       tail: SplitStoreChecks.choice()), "a refused journal save reported success", &problems)
            guard let split = SplitStoreChecks.halves(of: record, in: store) else {
                return problems + ["the archive did not take the split"]
            }
            expect(store.correctionError != nil && store.correctionRetry != nil && store.canUndoCorrection,
                   "the refused save did not stay shown with Retry and Undo", &problems)
            expect(store.sessionMetadata(for: split.tail.id)?.splitFrom?.head == record.id,
                   "a split that stands has no link, so no Merge Back", &problems)
            expect(power(store, split.head.id) == [early.id] && power(store, split.tail.id) == [late.id],
                   "the readings did not follow their halves after a refused journal save", &problems)
            expect(store.retryLastCorrection() && store.correctionError == nil && store.canMergeBack(recordID: split.tail.id),
                   "Retry did not finish the split: \(store.correctionError ?? "")", &problems)

            journal.failSecondSave()
            expect(!store.mergeBack(tailID: split.tail.id) && !store.engine.archive.records.contains { $0.id == split.tail.id },
                   "the merge did not land with its save refused", &problems)
            expect(power(store, record.id) == [early.id, late.id],
                   "the tail's readings stayed on a record that is gone after a refused save", &problems)
            expect(store.retryLastCorrection(), "Retry did not finish the merge", &problems)

            journal.failSecondSave()
            expect(!store.undoLastCorrection() && store.engine.archive.records.contains(split.tail),
                   "the undo of the merge did not land with its save refused", &problems)
            expect(power(store, split.head.id) == [early.id] && power(store, split.tail.id) == [late.id],
                   "undoing the merge did not send the readings back after a refused save", &problems)
            expect(store.retryLastCorrection(), "Retry did not finish the undo of the merge", &problems)

            journal.failSecondSave()
            expect(!store.undoLastCorrection() && store.engine.archive.records == [record],
                   "the undo of the split did not land with its save refused", &problems)
            expect(power(store, record.id) == [early.id, late.id] && power(store, split.tail.id).isEmpty,
                   "the readings were left on the vanished tail, to be pruned", &problems)
            expect(store.retryLastCorrection() && power(store, record.id) == [early.id, late.id],
                   "the readings did not survive Retry of the undo", &problems)
            return problems
        }
    }

    private static func refusedAutomaticSplitIsNotLost() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let away = SplitAutomaticChecks.rig() else { return ["could not create isolated preferences"] }
            defer { away.close() }
            let held = SplitAutomaticChecks.ended(away, then: SplitAutomaticChecks.design)
            // A sleep that outlasts the session's patience leaves the question open.
            away.engine.start(workType: .learning, intent: "Pending")
            away.clock.advance(20 * 60)
            away.engine.transition(on: .awayBegan(trigger: .systemSleep))
            away.clock.advance(20 * 60)
            away.engine.transition(on: .awayEnded)
            guard away.store.hasUnresolvedAwayDecision else { return ["the away question did not open"] }
            away.store.writeActivitySnapshots()
            expect(away.engine.archive.records.contains(held), "a session was cut with an away question open", &problems)
            expect(away.store.applyAwayDecision(.continueSession, reviewing: false), "the away question was not answered", &problems)
            away.store.writeActivitySnapshots()
            expect(SplitStoreChecks.halves(of: held, in: away.store) != nil,
                   "the session was never judged again once the question was answered", &problems)

            let refuse = BreakStoreChecks.Box(true)
            guard let refused = ActivityEvidenceStoreChecks.rig(session: false, journal: { refuse.value ? "The disk is full." : nil })
            else { return problems + ["could not create isolated preferences"] }
            defer { refused.close() }
            refused.store.writeActivitySnapshots()
            let record = SplitAutomaticChecks.ended(refused, then: SplitAutomaticChecks.design)
            refused.store.writeActivitySnapshots()
            expect(refused.engine.archive.records == [record] && refused.store.correctionError == nil,
                   "a refused automatic split changed the archive or showed an error nobody asked for", &problems)
            let offer = refused.store.splitOffer(for: SplitStoreChecks.row(record))
            expect(offer?.choice == .chosen(.deepWork, .builtIn),
                   "the refused split was not offered: \(String(describing: offer))", &problems)
            refuse.value = false
            if let offer {
                expect(refused.store.acceptSplit(offer), "the offer after a refusal failed: \(refused.store.correctionError ?? "")", &problems)
            }
            return problems
        }
    }

    // MARK: A build from before Phase B

    /// The correction history as the last build before Phase B declares it, frozen here: three corrections,
    /// and a version that must stay 1. Decoding is strict about the enum, which is what an older build does.
    private enum Frozen {
        enum Correction: Codable { case rename(String), workType(WorkType), removed }
        struct Fields: Codable { let name: String; let workType: WorkType }
        struct State: Codable {
            let id: UUID, sequence: Int, threadID: UUID
            let correction: Correction
            let originalFields: Fields
            let archiveRecordIDs: Set<UUID>
            let removedRecords: [SessionRecord]?
            let madeAt: Date?
            var isRemoval: Bool { if case .removed = correction { return true }; return false }
        }
        struct Transaction: Codable { let removed: [SessionRecord]; let added: [SessionRecord]; let fieldsAfter: [State] }
        struct Document: Codable { let version: Int; let fields: [State]; let pending: Transaction? }
    }

    private static func olderBuildReadsTheJournal() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let journal = Journal()
            let rig = SplitStoreChecks.rig(journal: { journal.save() })
            defer { MemoryDefaults.remove(named: rig.suite) }
            let store = rig.store
            let record = SplitStoreChecks.ended(rig)
            SplitStoreChecks.seed(rig, [record])
            let url = store.engine.archive.dataDirectoryURL.appendingPathComponent("correction-history.json")
            func older() -> Frozen.Document? {
                (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Frozen.Document.self, from: $0) }
            }
            guard store.splitSession(recordID: record.id, at: record.start.addingTimeInterval(2_400), tail: SplitStoreChecks.choice()),
                  let split = SplitStoreChecks.halves(of: record, in: store), store.mergeBack(tailID: split.tail.id) else {
                return ["the split or the merge was refused: \(store.correctionError ?? "")"]
            }
            let present = Set(store.engine.archive.records.map(\.id))
            guard let written = older() else { return ["a build from before Phase B cannot read the history after a split and a merge"] }
            expect(written.version == 1 && written.fields.count == 2 && written.fields.allSatisfy(\.isRemoval),
                   "the older build reads \(written.fields.count) corrections, versions \(written.version)", &problems)
            // Its Undo of a removal puts records back only when none is present: here one always is.
            expect(written.fields.allSatisfy { $0.removedRecords?.contains { present.contains($0.id) } == true },
                   "an older build's Undo would put a split or a merge's records back beside the present ones", &problems)

            journal.failSecondSave()
            _ = store.splitSession(recordID: record.id, at: record.start.addingTimeInterval(2_400), tail: SplitStoreChecks.choice())
            expect(older()?.pending?.fieldsAfter.count == 3 && older()?.pending?.fieldsAfter.last?.isRemoval == true,
                   "a build from before Phase B cannot read the pending split", &problems)
            return problems
        }
    }

    private static func mergeIsBitForBit() -> [String] {
        var problems: [String] = []
        let start = SelfTest.base
        var drifted = 0, tried = 0
        for index in 0..<300 {
            let work = 2_000 + Double(index) * 3.7371 + Double(index % 7) / 10
            let paused = index.isMultiple(of: 2) ? nil : [DateInterval(start: start.addingTimeInterval(1_200), duration: 600)]
            let record = SessionRecord(name: "Report", workType: .deepWork, start: start, end: start.addingTimeInterval(3_600),
                                       workSeconds: work, threadID: UUID(), isAuto: false, pausedSpans: paused,
                                       origin: .manual, categorySource: .user)
            // Early cuts, before the pause: the head then holds under half the work, where a sum of two halves
            // can round away from the whole.
            let moment = start.addingTimeInterval(100 + Double(index % 11) * 97.7)
            guard let cut = record.split(at: moment, tail: SplitStoreChecks.choice()) else { continue }
            tried += 1
            if SessionRecord.merged(head: cut.head, tail: cut.tail) != record { drifted += 1 }
        }
        expect(tried > 250 && drifted == 0, "\(drifted) of \(tried) merges differ from the record that was cut", &problems)
        return problems
    }

    private static func ownErrorAndAcceptedTail() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = SplitAutomaticChecks.rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            let thread = UUID()
            r.store.publishCorrectionError("Their own error.")
            r.store.correctionRetry = .correction(threadID: thread, correction: .removed)
            let record = SplitAutomaticChecks.ended(r, then: SplitAutomaticChecks.design)
            r.store.writeActivitySnapshots()
            expect(SplitStoreChecks.halves(of: record, in: r.store) != nil, "the session did not split itself", &problems)
            var kept = false
            if case .correction(let id, _, _, _)? = r.store.correctionRetry { kept = id == thread }
            expect(r.store.correctionError == "Their own error." && kept,
                   "a split of Daybook's own cleared the person's error or Retry: \(r.store.correctionError ?? "none")", &problems)

            guard let q = SplitAutomaticChecks.rig() else { return problems + ["could not create isolated preferences"] }
            defer { q.close() }
            let original = SplitAutomaticChecks.ended(q, then: SplitAutomaticChecks.design)
            var theirs = original
            theirs.categorySource = .user
            _ = q.engine.archive.edit(removing: [original], adding: [theirs])
            q.store.writeActivitySnapshots()
            guard let offer = q.store.splitOffer(for: SplitStoreChecks.row(theirs)), q.store.acceptSplit(offer),
                  let tail = SplitStoreChecks.halves(of: theirs, in: q.store)?.tail else {
                return problems + ["the person's offer was not taken: \(q.store.correctionError ?? "")"]
            }
            expect(tail.splitsItself && q.evidence.splitSeen?.contains(tail.id) == true,
                   "a tail from an accepted offer is left for the next pass to judge", &problems)
            return problems
        }
    }
}
