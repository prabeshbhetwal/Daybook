import Foundation

/// Remembering a category choice, and taking it back, when the plain case does not hold: a journal save was
/// refused (after the records changed, or before), or two filings of one kind were undone out of order.
enum RememberedUndoChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("An undo of a category change whose journal save is refused forgets the choice once, and Retry does not forget it again",
         refusedSaveForgetsOnce),
        ("Two filings of one kind undone oldest first leave nothing remembered; newest first leaves the older one",
         outOfOrderUndo),
        ("An undo refused before it wrote anything forgets nothing, and Retry forgets the choice once",
         refusedBeforeTheWriteForgetsNothing),
        ("A category change that landed with its journal save refused is remembered once, and Retry does not remember it again",
         refusedFilingIsRememberedOnce),
        ("Taking back the latest filing does not bring back a count for a filing that was undone out of order",
         staleCountIsNotRestored),
    ]

    /// Registered at the end of the list, after the checks numbered before it.
    static let retriedTests: [(String, () -> [String])] = [
        ("A category change refused before its write is remembered once when Retry lands it, and Undo forgets it",
         retriedFilingIsRemembered),
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

    /// The refusal comes before the archive write, so the correction still stands and nothing was taught
    /// away: forgetting then would be undone by nothing, and Retry would forget the same choice again.
    private static func refusedBeforeTheWriteForgetsNothing() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let journal = SplitRestructureChecks.Journal()
            let (store, clock, suite) = CorrectionsStoreChecks.make(journal: { journal.save() })
            defer { MemoryDefaults.remove(named: suite) }
            guard let (first, second, third) = sessions(store, clock) else { return ["no sessions were made"] }
            expect(store.setWorkType(.learning, for: first) && store.setWorkType(.learning, for: second),
                   "the category changes were refused: \(store.correctionError ?? "no reason")", &problems)
            guard let newest = store.corrections.last else { return problems + ["no correction was kept"] }
            @MainActor func entry() -> CategoryCorrection? { CorrectionsStoreChecks.stored(store).entries.first }

            journal.failFirstSave()
            expect(!store.undoCorrection(expectedID: newest.id) && store.correctionRetry != nil
                   && store.corrections.contains { $0.id == newest.id },
                   "the undo refused before its write did not leave the correction standing with Retry offered", &problems)
            expect(entry()?.count == 2, "the refusal before any write left \(String(describing: entry())), not both filings", &problems)
            expect(store.retryLastCorrection(), "Retry did not finish the undo: \(store.correctionError ?? "no error shown")", &problems)
            expect(entry()?.count == 1 && store.correctionSuggestion(for: third) == .learning,
                   "Retry left \(String(describing: entry())), not the one filing that still stands", &problems)
            return problems
        }
    }

    /// The change landed and only the journal's last save was refused: Retry finishes that save and files
    /// nothing, so the choice has to be remembered when the change lands, not left to it.
    private static func refusedFilingIsRememberedOnce() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let journal = SplitRestructureChecks.Journal()
            let (store, clock, suite) = CorrectionsStoreChecks.make(journal: { journal.save() })
            defer { MemoryDefaults.remove(named: suite) }
            guard let (first, second, third) = sessions(store, clock) else { return ["no sessions were made"] }
            @MainActor func entry() -> CategoryCorrection? { CorrectionsStoreChecks.stored(store).entries.first }
            expect(store.setWorkType(.learning, for: first), "the first change was refused: \(store.correctionError ?? "no reason")", &problems)

            journal.failSecondSave()
            expect(!store.setWorkType(.learning, for: second) && store.correctionRetry != nil
                   && store.corrections.contains { $0.threadID == second.threadID },
                   "the change whose journal save was refused did not land with Retry offered", &problems)
            expect(entry()?.count == 2, "the change that landed left \(String(describing: entry())), not both filings", &problems)
            expect(store.retryLastCorrection(), "Retry did not finish the change: \(store.correctionError ?? "no error shown")", &problems)
            expect(entry()?.count == 2, "Retry remembered the choice again: \(String(describing: entry()))", &problems)
            guard let newest = store.corrections.last else { return problems + ["no correction was kept"] }
            expect(store.undoCorrection(expectedID: newest.id), "the undo was refused: \(store.correctionError ?? "no reason")", &problems)
            expect(entry()?.count == 1 && store.correctionSuggestion(for: third) == .learning,
                   "undoing it left \(String(describing: entry())), not the older choice", &problems)
            return problems
        }
    }

    /// The refusal comes before the archive write, so the choice is not remembered yet: Retry files the change
    /// again, and has to bring the choice, and the receipt Undo takes it back by, with it.
    private static func retriedFilingIsRemembered() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let journal = SplitRestructureChecks.Journal()
            let (store, clock, suite) = CorrectionsStoreChecks.make(journal: { journal.save() })
            defer { MemoryDefaults.remove(named: suite) }
            guard let (first, _, third) = sessions(store, clock) else { return ["no sessions were made"] }
            @MainActor func entry() -> CategoryCorrection? { CorrectionsStoreChecks.stored(store).entries.first }
            journal.failFirstSave()
            expect(!store.setWorkType(.learning, for: first) && store.correctionRetry != nil
                   && !store.corrections.contains { $0.threadID == first.threadID },
                   "the change refused before its write did not leave Retry offered with nothing kept", &problems)
            expect(entry() == nil, "the refused change remembered \(String(describing: entry()))", &problems)
            expect(store.retryLastCorrection(), "Retry did not land the change: \(store.correctionError ?? "no error shown")", &problems)
            expect(entry()?.count == 1 && store.correctionSuggestion(for: third) == .learning,
                   "Retry landed the change but left \(String(describing: entry())) remembered, not its one filing", &problems)
            guard let landed = store.corrections.last else { return problems + ["no correction was kept"] }
            expect(store.undoCorrection(expectedID: landed.id), "the undo was refused: \(store.correctionError ?? "no reason")", &problems)
            expect(entry() == nil && store.correctionSuggestion(for: third) == nil,
                   "Undo of the retried change left \(String(describing: entry())) remembered", &problems)
            return problems
        }
    }
    /// X and Y file one category, X is undone out of order, Z files another, and Z is undone: Y alone stands,
    /// so one count comes back, not the two Y's own filing left.
    private static func staleCountIsNotRestored() -> [String] {
        var problems: [String] = []
        let typical = CorrectionsStoreChecks.typical
        var corrections = CategoryCorrections()
        func at(_ minutes: Int) -> Date { SelfTest.base.addingTimeInterval(TimeInterval(minutes * 60)) }
        let x = corrections.record(fingerprint: typical, chosen: "learning", vetoed: nil, at: at(0))
        let y = corrections.record(fingerprint: typical, chosen: "learning", vetoed: nil, at: at(1))
        corrections.forget(x, standing: [], later: [y])
        let z = corrections.record(fingerprint: typical, chosen: "admin", vetoed: nil, at: at(2))
        corrections.forget(z, standing: [y], later: [])
        expect(corrections.entries.first?.chosen == "learning" && corrections.entries.first?.count == 1,
               "taking back the latest filing left \(corrections.entries), not one count of the one that stands", &problems)
        corrections.forget(y, standing: [], later: [])
        expect(corrections.entries.isEmpty, "taking back the last one standing left \(corrections.entries)", &problems)
        return problems
    }
}
