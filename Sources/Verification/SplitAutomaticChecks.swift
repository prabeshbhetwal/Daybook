import Foundation

/// An automatic session that ends with its work moved on splits itself, once, from beats the way the app
/// records them, and only where Daybook may choose the tail's category (plan Task 6, rulings B8 and B11).
enum SplitAutomaticChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("An automatic session that ended with its work moved on to other focused work splits itself, keeps Merge Back, and Undo is final",
         splitsItself),
        ("A remembered correction files the tail under the person's category, as a correction",
         correctionFilesTheTail),
        ("An automatic session whose tail is not focused work stays whole, and one the person made theirs gets the offer instead",
         staysWholeOrOffers),
        ("Only a session that ends after launch is judged, and a manual, a rule's or a one-piece session is never split by itself",
         onlyNewAutomaticSessions),
    ]

    typealias Rig = ActivityEvidenceStoreChecks.Rig

    static var start: Date { ActivitySnapshotChecks.t0 }

    /// Thirty minutes of the editor, then twenty-five of `second`, as beats in the store's evidence.
    @MainActor
    static func ended(_ r: Rig, then second: BeatTrace.Step? = nil, origin: SessionOrigin = .automatic,
                      type: WorkType = .learning) -> SessionRecord {
        let steps = [ActivityTraces.step(ActivityTraces.editor, 30, .keys)] + (second.map { [$0] } ?? [])
        let beats = BeatTrace.beats(steps, from: start)
        for beat in beats { try? r.evidence.archive.append(beat) }
        let end = beats.last?.end ?? start
        let record = SessionRecord(name: "Coding", workType: type, start: start, end: end,
                                   workSeconds: end.timeIntervalSince(start), detectedApp: ActivityTraces.editor,
                                   threadID: UUID(), isAuto: origin != .manual, pausedSpans: [], origin: origin,
                                   categorySource: origin == .automatic ? .builtIn : origin == .rule ? .rule : .user,
                                   nameByApp: origin == .automatic)
        _ = r.engine.archive.append(record)
        r.clock.value = end.addingTimeInterval(600)
        return record
    }

    static let design = ActivityTraces.step(ActivityTraces.designApp, 25, .clicks(5))
    static let chat = ActivityTraces.step(ActivityTraces.messaging, 25, .keys)

    @MainActor
    static func rig() -> Rig? {
        let r = ActivityEvidenceStoreChecks.rig(session: false)
        // The first pass of a launch only notes what is there.
        r?.store.writeActivitySnapshots()
        return r
    }

    private static func splitsItself() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            let record = ended(r, then: design)
            r.store.refresh()
            let before = SplitStoreChecks.figures(r.store, r.clock, withGoal: false)
            expect(before.today > 0, "the fixture shows no work", &problems)
            r.store.writeActivitySnapshots()
            guard let halves = SplitStoreChecks.halves(of: record, in: r.store) else {
                return problems + ["the session did not split: \(r.engine.archive.records.count) records, \(r.store.correctionError ?? "no error")"]
            }
            let (head, tail) = (halves.head, halves.tail)
            expect(abs(tail.start.timeIntervalSince(start) - 1_800) < 120 && head.end == tail.start,
                   "the cut is at \(tail.start.timeIntervalSince(start)) s", &problems)
            expect(head.name == "Coding" && head.workType == .learning && head.categorySource == .builtIn
                   && head.threadID == record.threadID, "the head changed: \(head)", &problems)
            expect(tail.origin == .automatic && tail.isAuto && tail.workType == .deepWork && tail.categorySource == .builtIn
                   && tail.name == "Design" && tail.nameByApp == true && tail.detectedApp == ActivityTraces.designApp
                   && tail.threadID != head.threadID, "the tail is \(tail)", &problems)
            expect(r.store.canMergeBack(recordID: tail.id), "Merge Back is not offered on the tail", &problems)
            expect(r.store.corrections.count == 1 && r.store.editUndoKind == .split("Coding"), "the split is not one correction", &problems)
            expect(SplitStoreChecks.figures(r.store, r.clock, withGoal: false) == before, "the split moved a figure", &problems)
            // Judged once: another sweep cuts nothing more, and Undo is not undone by the next one.
            r.store.writeActivitySnapshots()
            expect(r.engine.archive.records.count == 2, "a second sweep cut again", &problems)
            expect(r.store.undoLastCorrection() && r.engine.archive.records == [record],
                   "Undo did not give back the one record: \(r.store.correctionError ?? "")", &problems)
            r.store.writeActivitySnapshots()
            r.store.refresh()
            expect(r.engine.archive.records == [record], "the next sweep split the session Undo had joined", &problems)
            return problems
        }
    }

    private static func correctionFilesTheTail() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            let record = ended(r, then: design)
            guard let at = r.store.splitMoment(in: record),
                  let fingerprint = r.store.endedShape(of: record, within: DateInterval(start: at, end: record.end))?.fingerprint
            else { return ["no cut or no fingerprint for the tail"] }
            let remembered = CorrectionsStore(directory: r.engine.archive.dataDirectoryURL)
            expect(remembered.record(fingerprint: fingerprint, chosen: WorkType.admin.rawValue, vetoed: nil, at: r.clock.value) == nil,
                   "the correction was not saved", &problems)
            r.store.writeActivitySnapshots()
            let tail = SplitStoreChecks.halves(of: record, in: r.store)?.tail
            expect(tail?.workType == .admin && tail?.categorySource == .correction,
                   "the tail is \(String(describing: tail))", &problems)
            return problems
        }
    }

    private static func staysWholeOrOffers() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let r = rig() else { return ["could not create isolated preferences"] }
            defer { r.close() }
            let record = ended(r, then: chat)
            let before = r.engine.archive.revision
            r.store.writeActivitySnapshots()
            expect(r.engine.archive.records == [record] && r.engine.archive.revision == before && r.store.corrections.isEmpty,
                   "a session with a chat for a tail was split by Daybook's choice", &problems)
            expect(r.store.splitOffer(for: SplitStoreChecks.row(record)) == nil,
                   "an automatic session of Daybook's own was offered a cut", &problems)
            if let shape = r.store.endedShape(of: record) {
                expect(shape.splitCandidates.count == 1 && shape.label == .activity(.coding),
                       "the detour is not in the evidence: \(shape.splitCandidates) \(shape.label)", &problems)
            } else { problems.append("no evidence for the session") }

            guard let q = rig() else { return problems + ["could not create isolated preferences"] }
            defer { q.close() }
            let original = ended(q, then: design)
            var theirs = original
            theirs.categorySource = .user
            _ = q.engine.archive.edit(removing: [original], adding: [theirs])
            q.store.writeActivitySnapshots()
            expect(q.engine.archive.records == [theirs], "a session the person filed was split by itself", &problems)
            let offer = q.store.splitOffer(for: SplitStoreChecks.row(theirs))
            expect(offer?.choice == .chosen(.deepWork, .builtIn) && offer?.purpose == .design,
                   "the person's session was offered \(String(describing: offer))", &problems)
            if let offer {
                expect(q.store.acceptSplit(offer), "taking the offer was refused: \(q.store.correctionError ?? "")", &problems)
                expect(q.engine.archive.records.count == 2, "taking the offer did not cut", &problems)
            }
            return problems
        }
    }

    private static func onlyNewAutomaticSessions() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            // Recorded before the app looked: left alone, however it would have been judged.
            guard let old = ActivityEvidenceStoreChecks.rig(session: false) else { return ["could not create isolated preferences"] }
            defer { old.close() }
            let earlier = ended(old, then: design)
            // A relaunch: the first pass notes what the archive holds and judges none of it.
            old.evidence.splitSeen = nil
            old.store.writeActivitySnapshots()
            old.store.writeActivitySnapshots()
            expect(old.engine.archive.records == [earlier], "a session recorded before launch was split", &problems)

            for (label, origin) in [("manual", SessionOrigin.manual), ("rule", .rule)] {
                guard let r = rig() else { return problems + ["could not create isolated preferences"] }
                defer { r.close() }
                let record = ended(r, then: design, origin: origin)
                r.store.writeActivitySnapshots()
                expect(r.engine.archive.records == [record], "a \(label) session was split by itself", &problems)
            }
            guard let one = rig() else { return problems + ["could not create isolated preferences"] }
            defer { one.close() }
            let whole = ended(one)
            one.store.writeActivitySnapshots()
            expect(one.engine.archive.records == [whole], "a session of one piece of work was split", &problems)
            return problems
        }
    }
}
