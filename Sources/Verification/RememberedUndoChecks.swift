import Foundation

/// Taking a category choice back from what Daybook remembers when Undo is not the plain case: its journal
/// save was refused after the records changed, or two filings of one kind were undone out of order.
enum RememberedUndoChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("An undo of a category change whose journal save is refused forgets the choice once, and Retry does not forget it again",
         refusedSaveForgetsOnce),
        ("Two filings of one kind undone oldest first leave nothing remembered; newest first leaves the older one",
         outOfOrderUndo),
    ]

    /// Three ended sessions of one kind: two to file, one that is offered what they taught.
    @MainActor
    private static func sessions(_ store: SessionStore, _ clock: TestClock) -> (DaySession, DaySession, DaySession)? {
        guard let first = CorrectionsStoreChecks.ended(store, clock, begin: CorrectionsStoreChecks.automatic("Parser")),
              let second = CorrectionsStoreChecks.ended(store, clock, begin: CorrectionsStoreChecks.automatic("Router")),
              let third = CorrectionsStoreChecks.ended(store, clock, begin: CorrectionsStoreChecks.automatic("Linker"))
        else { return nil }
        return (first, second, third)
    }

    private static func refusedSaveForgetsOnce() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let journal = SplitRestructureChecks.Journal()
            let (store, clock, suite) = CorrectionsStoreChecks.make(journal: { journal.save() })
            defer { MemoryDefaults.remove(named: suite) }
            guard let (first, second, third) = sessions(store, clock) else { return ["no sessions were made"] }
            expect(store.setWorkType(.learning, for: first) && store.setWorkType(.learning, for: second),
                   "the category changes were refused: \(store.correctionError ?? "no reason")", &problems)
            guard let newest = store.lastCorrection else { return problems + ["no correction was kept"] }
            @MainActor func entry() -> CategoryCorrection? { CorrectionsStoreChecks.stored(store).entries.first }
            expect(entry()?.count == 2, "the two filings left \(String(describing: entry()))", &problems)

            journal.failSecondSave()
            expect(!store.undoCorrection(expectedID: newest.id) && store.correctionRetry != nil
                   && !store.corrections.contains { $0.id == newest.id },
                   "the undo whose journal save was refused did not land with Retry offered", &problems)
            expect(entry()?.count == 1,
                   "the undo that landed left \(String(describing: entry())) remembered, not one filing", &problems)
            expect(store.retryLastCorrection(), "Retry did not finish the undo: \(store.correctionError ?? "no error shown")", &problems)
            expect(entry()?.count == 1 && store.correctionSuggestion(for: third) == .learning,
                   "Retry forgot the choice again: \(String(describing: entry()))", &problems)
            return problems
        }
    }

    private static func outOfOrderUndo() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            for oldestFirst in [true, false] {
                let (store, clock, suite) = CorrectionsStoreChecks.make()
                defer { MemoryDefaults.remove(named: suite) }
                guard let (first, second, third) = sessions(store, clock) else { return problems + ["no sessions were made"] }
                expect(store.setWorkType(.learning, for: first) && store.setWorkType(.admin, for: second),
                       "the category changes were refused: \(store.correctionError ?? "no reason")", &problems)
                let ids = store.corrections.map(\.id)
                guard ids.count == 2 else { problems.append("\(ids.count) corrections were kept, not two"); continue }
                let order = oldestFirst ? ids : Array(ids.reversed())
                let way = oldestFirst ? "oldest" : "newest"
                expect(store.undoCorrection(expectedID: order[0]), "the \(way) undo was refused: \(store.correctionError ?? "")", &problems)
                if !oldestFirst {
                    let entry = CorrectionsStoreChecks.stored(store).entries.first
                    expect(entry?.chosen == "learning" && entry?.count == 1 && store.correctionSuggestion(for: third) == .learning,
                           "undoing the newer filing left \(String(describing: entry)), not the older one", &problems)
                }
                expect(store.undoCorrection(expectedID: order[1]), "the second undo was refused: \(store.correctionError ?? "")", &problems)
                let left = CorrectionsStoreChecks.stored(store).entries
                expect(left.isEmpty && store.correctionSuggestion(for: third) == nil,
                       "both filings undone, \(way) first, left \(left) remembered", &problems)
            }
            return problems
        }
    }
}
