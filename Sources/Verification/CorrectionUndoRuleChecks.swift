import Foundation

/// The rules for taking one filing back, on the model alone, and the card's "Filed under" line, which
/// stands only while its correction can still be undone.
enum CorrectionUndoRuleChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A filing taken back restores the entry as it stood, vetoes included, and removes one that was new",
         takingBackRestores),
        ("Taking back an older filing of a choice made again since drops one count and goes at zero",
         takingBackAnOlderOne),
        ("A filing for another choice or another kind is not taken back from this one", otherChoicesAreLeft),
        ("A count at the limit can be taken back from without overflowing", takingBackAtTheLimit),
        ("The card's Filed under line clears once its correction is undone elsewhere", filedLineClears),
    ]
    /// Registered last, apart from `tests`, so earlier check numbers stay.
    static let laterTests: [(String, () -> [String])] = [
        ("Taking back a run of one choice in order leaves the earlier choice that stands", runTakenBackInOrder),
    ]

    private static let typical = CategoryCorrectionChecks.fingerprint()
    private static let other = CategoryCorrectionChecks.fingerprint([0, 5, 0, 0, 0, 0, 0])

    private static func takingBackRestores() -> [String] {
        var problems: [String] = []
        var corrections = CategoryCorrections()
        let start = SelfTest.base
        let first = corrections.record(fingerprint: typical, chosen: "learning", vetoed: "deepWork", at: start)
        expect(first.before == nil && first.after.chosen == "learning", "the first filing reads \(first)", &problems)
        let second = corrections.record(fingerprint: typical, chosen: "deepWork", vetoed: "learning",
                                        at: start.addingTimeInterval(60))
        corrections.forget(second, standing: [first], later: [])
        expect(corrections.entries == [first.after],
               "taking back the second left \(corrections.entries), not \(first.after)", &problems)
        corrections.forget(first, standing: [], later: [])
        expect(corrections.entries.isEmpty, "taking back the only filing left \(corrections.entries)", &problems)
        return problems
    }

    private static func takingBackAnOlderOne() -> [String] {
        var problems: [String] = []
        var corrections = CategoryCorrections()
        let filings = (0..<3).map {
            corrections.record(fingerprint: typical, chosen: "learning", vetoed: nil,
                               at: SelfTest.base.addingTimeInterval(TimeInterval($0 * 60)))
        }
        corrections.forget(filings[0], standing: [], later: [filings[1], filings[2]])
        expect(corrections.entries.first?.count == 2 && corrections.suggestion(for: typical, now: SelfTest.base) == "learning",
               "taking back the oldest of three left \(corrections.entries)", &problems)
        corrections.forget(filings[1], standing: [], later: [filings[2]])
        corrections.forget(filings[2], standing: [], later: [])
        expect(corrections.entries.isEmpty, "taking back all three left \(corrections.entries)", &problems)
        return problems
    }

    private static func otherChoicesAreLeft() -> [String] {
        var problems: [String] = []
        var corrections = CategoryCorrections()
        let learning = corrections.record(fingerprint: typical, chosen: "learning", vetoed: nil, at: SelfTest.base)
        corrections.record(fingerprint: other, chosen: "admin", vetoed: nil, at: SelfTest.base)
        corrections.record(fingerprint: typical, chosen: "meetings", vetoed: nil, at: SelfTest.base)
        let before = corrections
        corrections.forget(learning, standing: [], later: [])   // replaced by another choice since
        expect(corrections == before, "a replaced choice's filing changed \(corrections.entries)", &problems)
        let unstored = CategoryCorrection(kind: CategoryCorrections.categoryKind,
                                          fingerprint: CategoryCorrectionChecks.fingerprint(apps: ["x", ""]),
                                          chosen: "admin", vetoed: [], count: 1, lastUsed: SelfTest.base)
        corrections.forget(RememberedFiling(before: nil, after: unstored), standing: [], later: [])
        expect(corrections == before, "a filing of a kind not stored changed \(corrections.entries)", &problems)
        return problems
    }

    private static func takingBackAtTheLimit() -> [String] {
        var problems: [String] = []
        var corrections = CategoryCorrections()
        corrections.entries = [CategoryCorrection(kind: CategoryCorrections.categoryKind, fingerprint: typical,
                                                  chosen: "learning", vetoed: [], count: .max, lastUsed: SelfTest.base)]
        let filings = (1...2).map {
            corrections.record(fingerprint: typical, chosen: "learning", vetoed: nil,
                               at: SelfTest.base.addingTimeInterval(TimeInterval($0 * 60)))
        }
        corrections.forget(filings[0], standing: [], later: [filings[1]])
        expect(corrections.entries.first?.chosen == "learning" && corrections.entries.first?.count == 1,
               "taking back at the limit left \(String(describing: corrections.entries.first))", &problems)
        return problems
    }

    /// Learning, Admin, Admin: both Admin filings taken back in order leave the Learning choice that stands.
    private static func runTakenBackInOrder() -> [String] {
        var problems: [String] = []
        var corrections = CategoryCorrections()
        let filings = ["learning", "admin", "admin"].enumerated().map {
            corrections.record(fingerprint: typical, chosen: $0.element, vetoed: nil,
                               at: SelfTest.base.addingTimeInterval(TimeInterval($0.offset * 60)))
        }
        corrections.forget(filings[1], standing: [filings[0]], later: [filings[2]])
        expect(corrections.entries.first?.chosen == "admin" && corrections.entries.first?.count == 1,
               "taking back the first Admin left \(corrections.entries)", &problems)
        corrections.forget(filings[2], standing: [filings[0]], later: [])
        expect(corrections.entries == [filings[0].after],
               "taking back both Admin filings left \(corrections.entries), not the Learning choice", &problems)
        return problems
    }

    private static func filedLineClears() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let (store, clock, suite) = CorrectionsStoreChecks.make()
            defer { MemoryDefaults.remove(named: suite) }
            guard let session = CorrectionsStoreChecks.ended(store, clock, begin: CorrectionsStoreChecks.automatic("Parser")) else {
                return ["no session was made"]
            }
            expect(store.setWorkType(.learning, for: session), "the category change was refused", &problems)
            guard let made = store.lastCorrection else { return problems + ["no correction was kept"] }
            let filing = CorrectionFiling(category: .learning, correctionID: made.id)
            expect(filing.standing(in: store.corrections) == filing, "a filing with its correction did not stand", &problems)
            expect(store.undoLastCorrection(), "Edit > Undo was refused", &problems)
            expect(filing.standing(in: store.corrections) == nil,
                   "the card still said Filed under after its correction was undone", &problems)
            return problems
        }
    }
}
