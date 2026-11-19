import Foundation

/// Taking back an older filing of a kind while a newer choice stands: the newer choice is kept, whichever
/// way the filings in between were undone.
enum OlderFilingUndoChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Undoing an older category filing leaves the newer choice of that kind standing, even with a filing between withdrawn",
         olderFilingBehindANewerChoice),
    ]

    /// Learning, Admin, Learning on three sessions of one kind, and a fourth to be offered what they taught.
    /// `middleFirst`: the Admin filing is undone before the oldest one, so the two Learning filings run on.
    @MainActor
    private static func run(middleFirst: Bool) -> [String] {
        var problems: [String] = []
        let (store, clock, suite) = CorrectionsStoreChecks.make()
        defer { MemoryDefaults.remove(named: suite) }
        let names = ["Parser", "Router", "Linker", "Loader"]
        let rows = names.compactMap { CorrectionsStoreChecks.ended(store, clock, begin: CorrectionsStoreChecks.automatic($0)) }
        guard rows.count == names.count else { return ["no sessions were made"] }
        let way = middleFirst ? "after the Admin filing was undone" : "with the Admin filing standing"
        expect(store.setWorkType(.learning, for: rows[0]) && store.setWorkType(.admin, for: rows[1])
               && store.setWorkType(.learning, for: rows[2]),
               "the category changes were refused: \(store.correctionError ?? "no reason")", &problems)
        let ids = store.corrections.map(\.id)
        guard ids.count == 3 else { return problems + ["\(ids.count) corrections were kept, not three"] }
        @MainActor func entry() -> CategoryCorrection? { CorrectionsStoreChecks.stored(store).entries.first }

        if middleFirst {
            expect(store.undoCorrection(expectedID: ids[1]), "the Admin undo was refused: \(store.correctionError ?? "")", &problems)
        }
        expect(store.undoCorrection(expectedID: ids[0]), "the oldest undo was refused: \(store.correctionError ?? "")", &problems)
        expect(entry()?.chosen == "learning" && entry()?.count == 1 && store.correctionSuggestion(for: rows[3]) == .learning,
               "undoing the oldest filing \(way) left \(String(describing: entry())), not the newest Learning choice", &problems)
        for id in ids.dropFirst() where store.corrections.contains(where: { $0.id == id }) {
            expect(store.undoCorrection(expectedID: id), "an undo was refused: \(store.correctionError ?? "")", &problems)
        }
        expect(entry() == nil, "every filing undone, \(way), left \(String(describing: entry())) remembered", &problems)
        return problems
    }

    private static func olderFilingBehindANewerChoice() -> [String] {
        MainActor.assumeIsolated { run(middleFirst: false) + run(middleFirst: true) }
    }
}
