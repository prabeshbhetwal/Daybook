import Foundation

/// What the category assistant leaves alone (Phase C, rulings C4, C24 and C30): a session an Undo, a Merge Back
/// or an away answer still holds by its exact value, any write while a correction is pending, a session that
/// ended before the app opened however it came by a new identity, and a record whose answer could not be
/// saved. Every check drives a responder; none reaches the live model.
enum CategoryAssistantHeldChecks: CheckSuite {
    private typealias Rig = CategoryAssistantRig
    private typealias Spec = CategoryAssistantRig.Spec
    private typealias Box = BreakStoreChecks.Box

    static let tests: [(String, () -> [String])] = [
        ("Neither half of a split is asked about or written, so Merge Back and Undo of the split still hold", splitHalvesAreHeld),
        ("A stretch an away answer counted in is not asked about, so Undo of the answer still holds", awayReceiptIsHeld),
        ("Nothing is written while a correction is pending", nothingWhilePending),
        ("A session that ended before launch is not asked about when a split, merge or Undo gives it a new identity", oldSessionsStayOld),
        ("A pick or a label is written only once its answer is saved", writesFollowTheSave),
        ("The model is not asked while the label file cannot be saved", nothingAskedWithoutAPlaceToKeepIt),
        ("A correction to the session that leaves the record as it was still stops the write", correctionHoldsAnUnchangedRecord),
    ]

    private static func splitHalvesAreHeld() -> [String] {
        Rig.withRig(reply: { _, _ in Rig.answer("2") }) { rig, problems in
            rig.mode.assigns = true
            let whole = rig.record, tailID = UUID()
            let tail = SplitTail(name: "Tail", workType: .deepWork, source: .builtIn, nameByApp: true)
            // Each half as the sweep leaves it: a summary of its own, unclear on purpose.
            guard rig.f.store.splitSession(recordID: whole.id, at: whole.start.addingTimeInterval(900), tail: tail, tailID: tailID),
                  let head = rig.stored(), let second = rig.f.engine.archive.records.first(where: { $0.id == tailID }),
                  rig.f.metadata.saveActivityShape(Rig.shape(for: head, Spec(seed: 1)), for: head.id) == .saved,
                  rig.f.metadata.saveActivityShape(Rig.shape(for: second, Spec(seed: 2)), for: tailID) == .saved
            else { return problems.append("the split was not set up: \(rig.f.store.correctionError ?? "no error")") }
            rig.ask()
            rig.ask(id: tailID)
            expect(rig.calls.questions.isEmpty, "a half of a split was asked about: \(rig.calls.questions.count)", &problems)
            expect(rig.stored() == head && rig.f.engine.archive.records.contains(second),
                   "a half of a split was written: \(String(describing: rig.stored()))", &problems)
            expect(rig.f.store.canMergeBack(recordID: tailID), "Merge Back was refused after the assistant had answered", &problems)
            expect(rig.f.store.undoLastCorrection() && rig.f.engine.archive.records == [whole],
                   "Undo of the split was refused: \(rig.f.store.correctionError ?? "")", &problems)
        }
    }

    private static func awayReceiptIsHeld() -> [String] {
        let rest = SessionRecord(name: "Away", workType: .breakTime, start: SelfTest.base.addingTimeInterval(1_800),
                                 end: SelfTest.base.addingTimeInterval(3_000), workSeconds: 1_200)
        return Rig.withRig(reply: { _, _ in Rig.answer("2") }, prepare: { f in _ = f.engine.archive.append(rest) }) { rig, problems in
            rig.mode.assigns = true
            // A legacy break counted into the session: the answer's receipt holds the record it wrote in.
            guard rig.f.engine.reclassifyLegacyBreak(recordID: rest.id, decision: .mergeTime, focusTargetID: rig.record.id),
                  let counted = rig.f.engine.lastAwayDecision?.insertedRecord,
                  rig.f.metadata.saveActivityShape(Rig.shape(for: counted, Spec(seed: 2)), for: counted.id) == .saved
            else { return problems.append("the break was not counted in: \(rig.f.engine.awayDecisionError ?? "no error")") }
            rig.ask(id: counted.id)
            expect(rig.calls.questions.isEmpty, "a stretch an away answer holds was asked about", &problems)
            expect(rig.f.engine.archive.records.contains(counted), "a stretch an away answer holds was written", &problems)
            expect(rig.f.engine.undoAwayDecision(), "Undo of the away answer was refused: \(rig.f.engine.awayDecisionError ?? "")", &problems)
        }
    }

    private static func nothingWhilePending() -> [String] {
        let writes = Box(0), failAt = Box(-1)
        return Rig.withRig([Spec(seed: 1), Spec(seed: 2)],
                           journal: { writes.value += 1; return writes.value == failAt.value ? "The disk is full." : nil },
                           reply: { _, _ in Rig.answer("2") }) { rig, problems in
            rig.mode.assigns = true
            // A split of the other session whose journal save is refused leaves its correction pending.
            let other = rig.records[1]
            failAt.value = writes.value + 2
            _ = rig.f.store.splitSession(recordID: other.id, at: other.start.addingTimeInterval(900),
                                         tail: SplitTail(name: "Tail", workType: .deepWork, source: .builtIn, nameByApp: true))
            guard rig.f.engine.decisionHistory.document.pending != nil else { return problems.append("no correction was left pending") }
            rig.ask(0)
            expect(rig.calls.questions.count == 1, "the session was not asked about: \(rig.calls.questions.count)", &problems)
            expect(rig.stored(0) == rig.records[0], "a pick was written while a correction was pending: \(String(describing: rig.stored(0)))", &problems)
        }
    }

    private static func oldSessionsStayOld() -> [String] {
        Rig.withRig { rig, problems in
            rig.f.store.installCategoryAssistant(rig.assistant)
            // The first pass of a launch only notes what is there, and when.
            rig.f.store.writeActivitySnapshots()
            let old = rig.record, start = rig.f.clock.value
            func session(_ name: String, from start: Date, to end: Date) -> SessionRecord {
                SessionRecord(name: name, workType: .deepWork, start: start, end: end, workSeconds: end.timeIntervalSince(start),
                              isAuto: true, origin: .automatic, categorySource: .builtIn)
            }
            // A split, a merge or an Undo after launch hands the same stretch to a record with a new id; one that
            // really ended after launch is the control.
            let again = session("Again", from: old.start, to: old.end)
            let later = session("Later", from: start, to: start.addingTimeInterval(1_800))
            guard rig.f.engine.archive.edit(removing: [old], adding: [again]) == nil, rig.f.engine.archive.append(later) == nil,
                  rig.f.metadata.saveActivityShape(Rig.shape(for: again, Spec(seed: 1)), for: again.id) == .saved,
                  rig.f.metadata.saveActivityShape(Rig.shape(for: later, Spec(seed: 3)), for: later.id) == .saved
            else { return problems.append("the sessions were not set up") }
            rig.f.clock.advance(3_600)
            rig.f.store.writeActivitySnapshots()
            rig.settle(0.05)
            expect(rig.calls.questions.map(\.fingerprint) == [AIFixture.fingerprint(3)],
                   "not just the session that ended after launch was asked about: \(rig.calls.questions.map(\.fingerprint))", &problems)
        }
    }

    private static func writesFollowTheSave() -> [String] {
        Rig.withRig([Spec(seed: 1), Spec(seed: 2)]) { rig, problems in
            // A label made for sessions of the first kind, in a file that is then lost: a plain file takes its folder's place.
            let folder = SelfTest.scratchDirectory()
            var book = AILabelBook()
            book.labels = [AIFixture.label("ai.films", "Films", seed: 1)]
            guard AILabelStore(directory: folder).save(book, at: SelfTest.base) == nil else {
                return problems.append("the label book was not saved")
            }
            let lost = AILabelStore(directory: folder)
            try? FileManager.default.removeItem(at: folder)
            guard (try? Data().write(to: folder)) != nil, lost.book.labels.count == 1 else {
                return problems.append("the label file was not put out of reach")
            }
            let asked = Box(0)
            let assistant = CategoryAssistant(store: rig.f.store, labels: lost, assigns: { true })
            assistant.responder = { _ in asked.value += 1; return Rig.answer("2") }
            // The first kind has its label and the second is asked: an answer of each sort, neither of them saved.
            rig.records.forEach { assistant.sessionEnded($0.id) }
            _ = InstalledAppCatalog.turnRunLoop(until: { assistant.isIdle }, timeout: 5)
            expect(asked.value == 1, "the sessions were not answered as set up: asked \(asked.value) times", &problems)
            expect(rig.stored(0) == rig.records[0] && rig.stored(1) == rig.records[1],
                   "a record was written though its answer could not be saved: \(String(describing: rig.stored(0))) \(String(describing: rig.stored(1)))", &problems)
        }
    }

    private static func nothingAskedWithoutAPlaceToKeepIt() -> [String] {
        Rig.withRig { rig, problems in
            // A label file that cannot be read and cannot be set aside: the store refuses every save.
            let folder = SelfTest.scratchDirectory(), manager = FileManager.default
            guard (try? manager.createDirectory(at: folder, withIntermediateDirectories: true)) != nil,
                  (try? Data("not json".utf8).write(to: folder.appendingPathComponent(AILabelStore.fileName))) != nil,
                  (try? manager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)) != nil
            else { return problems.append("the label file was not put out of reach") }
            defer { try? manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
            let stuck = AILabelStore(directory: folder)
            guard stuck.failure != nil else { return problems.append("the label store was not left unable to save") }
            let asked = Box(0)
            let assistant = CategoryAssistant(store: rig.f.store, labels: stuck, assigns: { true })
            assistant.responder = { _ in asked.value += 1; return Rig.answer("2") }
            assistant.sessionEnded(rig.record.id)
            _ = InstalledAppCatalog.turnRunLoop(until: { assistant.isIdle }, timeout: 5)
            expect(asked.value == 0, "the model was asked though its answer could not be saved: \(asked.value) times", &problems)
            expect(rig.stored() == rig.record, "a record was written though its answer could not be saved", &problems)
        }
    }

    private static func correctionHoldsAnUnchangedRecord() -> [String] {
        let hook = Rig.Hook()
        return Rig.withRig(reply: { _, _ in hook.run(); return Rig.answer("2") }) { rig, problems in
            // A later stretch of the same session, filed differently: setting the whole session to the first
            // stretch's category changes only it, and the correction's receipt holds both by identity.
            let record = rig.record
            let other = SessionRecord(name: record.name, workType: .admin, start: record.end.addingTimeInterval(60),
                                      end: record.end.addingTimeInterval(660), workSeconds: 600, threadID: record.threadID)
            guard rig.f.engine.archive.append(other) == nil else { return problems.append("the second stretch was not recorded") }
            hook.run = { _ = rig.f.store.setWorkType(record.workType, threadID: record.threadID) }
            rig.mode.assigns = true
            rig.ask()
            expect(rig.calls.questions.count == 1, "the session was not asked about: \(rig.calls.questions.count)", &problems)
            expect(rig.f.engine.archive.records.first { $0.id == other.id }?.workType == record.workType
                   && rig.f.engine.retainedCorrectionRecordIDs.contains(record.id),
                   "the correction did not land holding the record: \(rig.f.store.correctionError ?? "no error")", &problems)
            expect(rig.stored() == record, "an answer was written over a record a correction holds: \(String(describing: rig.stored()))", &problems)
            expect(rig.reloaded().book.answers.isEmpty && rig.assistant.suggestions.isEmpty,
                   "an answer for a record a correction holds was cached or offered", &problems)
            expect(rig.f.store.undoLastCorrection() && rig.f.engine.archive.records.first { $0.id == other.id }?.workType == .admin,
                   "Undo of the correction was refused: \(rig.f.store.correctionError ?? "")", &problems)
        }
    }
}
