import Foundation
/// A note written on the part a split cut off is the person's own. Undo of the split takes that part's record
/// away and the sidecar drops what is kept for it, so Undo is refused while the note stands, as Merge Back is.
enum SplitUndoNoteChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Undo of a split is refused while its second part holds a saved note, and goes ahead once the note is gone",
         undoDoesNotDiscardTheNote),
    ]
    private static func undoDoesNotDiscardTheNote() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let rig = SplitStoreChecks.rig()
            defer { MemoryDefaults.remove(named: rig.suite) }
            let record = SplitStoreChecks.ended(rig)
            SplitStoreChecks.seed(rig, [record])
            let store = rig.store
            guard store.splitSession(recordID: record.id, at: record.start.addingTimeInterval(2_400), tail: SplitStoreChecks.choice()),
                  let split = SplitStoreChecks.halves(of: record, in: store),
                  let made = store.corrections.last else { return ["the split was refused"] }
            store.beginNoteEditing(for: split.tail.id)
            store.setNoteDraft("Send the figures to the client", for: split.tail.id)
            expect(store.saveNote(for: split.tail.id), "the note on the second part was not saved", &problems)
            if store.undoCorrection(expectedID: made.id) {
                return problems + ["Undo of the split went ahead over a saved note on its second part: it now reads "
                                   + "\(String(describing: store.sessionMetadata(for: split.tail.id)?.note))"]
            }
            expect(store.correctionError != nil, "the refused Undo said nothing", &problems)
            expect(store.engine.archive.records.count == 2 && store.corrections.contains { $0.id == made.id }
                   && store.sessionMetadata(for: split.tail.id)?.note == "Send the figures to the client",
                   "the refused Undo changed the halves, the correction or the note", &problems)
            // The note cleared (an empty save removes it), the split is undone as any other.
            store.metadataArchive.saveNote(nil, for: split.tail.id)
            expect(store.undoCorrection(expectedID: made.id), "Undo was refused with no note left: \(store.correctionError ?? "no reason")", &problems)
            expect(store.engine.archive.records == [record], "Undo did not give back the one record", &problems)
            return problems
        }
    }
}
