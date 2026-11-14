/// Checks for splitting History's day record into its parts.
enum HistorySplitChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Slivers fold into Other, so no label reads 0%", slivers),
        ("The largest category is never folded", largestKept),
        ("A category sharing its neighbour's colour is drawn muted", mutedNeighbours),
        ("Nothing in, nothing out", nothing)
    ]

    private static func share(_ type: WorkType, _ value: Double) -> WorkTypeShare {
        WorkTypeShare(workType: type, seconds: value * 1_000, share: value)
    }

    private static func slivers() -> [String] {
        var problems: [String] = []
        let folded = HistorySplit.parts([share(.deepWork, 0.98), share(.meetings, 0.008),
                                         share(.admin, 0.007), share(.learning, 0.005)])
        expect(folded.count == 2, "Three slivers did not fold into one Other: \(folded.count) parts", &problems)
        if folded.count == 2 {
            expect(folded[0].workType == .deepWork && folded[0].share == 0.98,
                   "The big category changed when slivers folded", &problems)
            expect(folded[1].workType == nil && abs(folded[1].share - 0.02) < 1e-9,
                   "Other did not hold the folded 2%", &problems)
        }
        expect(abs(folded.reduce(0) { $0 + $1.share } - 1) < 1e-9,
               "Folding changed the total away from 1", &problems)

        // 2.5% rounds to 3 and stays; 2.4% rounds to 2 and folds.
        let edge = HistorySplit.parts([share(.deepWork, 0.951), share(.meetings, 0.025), share(.admin, 0.024)])
        expect(edge.map(\.workType) == [.deepWork, .meetings, nil],
               "A 2.5% category was not kept, or a 2.4% one was: \(edge.map { $0.workType?.rawValue ?? "other" })",
               &problems)
        expect(abs(edge.reduce(0) { $0 + $1.share } - 1) < 1e-9, "The edge split no longer sums to 1", &problems)

        let whole = HistorySplit.parts([share(.deepWork, 0.6), share(.meetings, 0.4)])
        expect(whole.map(\.workType) == [.deepWork, .meetings], "Other appeared though nothing folded", &problems)
        return problems
    }

    private static func largestKept() -> [String] {
        var problems: [String] = []
        let types = (0..<50).map { WorkType(rawValue: "custom.split\($0)") }
        let shares = WorkTypeShare.shares(from: Dictionary(uniqueKeysWithValues: types.map { ($0, 60.0) }))
        let parts = HistorySplit.parts(shares)
        expect(shares.count == 50, "The fixture did not make fifty categories: \(shares.count)", &problems)
        expect(parts.count == 2, "Fifty equal slivers did not leave one category and Other: \(parts.count)", &problems)
        if parts.count == 2 {
            expect(parts[0].workType == shares[0].workType && abs(parts[0].share - 0.02) < 1e-9,
                   "The largest category was folded away", &problems)
            expect(parts[1].workType == nil && abs(parts[1].share - 0.98) < 1e-9,
                   "Other did not hold the other 98%", &problems)
        }
        return problems
    }

    private static func mutedNeighbours() -> [String] {
        var problems: [String] = []
        func custom(_ name: String, _ hue: WorkTypeHue) -> WorkTypeDefinition {
            WorkTypeDefinition(id: "custom.\(name)", name: name, symbolName: "tag.fill", hue: hue)
        }
        WorkTypeCatalog.shared.apply(customisations: [custom("a", .green), custom("b", .green),
                                                      custom("c", .green), custom("d", .green),
                                                      custom("e", .blue)])
        defer { WorkTypeCatalog.shared.apply(customisations: []) }
        func type(_ name: String) -> WorkType { WorkType(rawValue: "custom.\(name)") }
        let three = HistorySplit.parts([share(type("a"), 0.5), share(type("b"), 0.3), share(type("c"), 0.2)])
        expect(three.map(\.isMuted) == [false, true, false],
               "Three neighbours of one colour did not alternate: \(three.map(\.isMuted))", &problems)
        let mixed = HistorySplit.parts([share(type("a"), 0.4), share(type("b"), 0.3), share(type("c"), 0.2),
                                        share(type("d"), 0.05), share(type("e"), 0.03), share(.admin, 0.02)])
        expect(mixed.map(\.isMuted) == [false, true, false, true, false, false],
               "Four of one colour, a new colour and Other did not mute as expected: \(mixed.map(\.isMuted))",
               &problems)
        expect(mixed.last?.workType == nil, "Other was missing from the end", &problems)
        return problems
    }

    private static func nothing() -> [String] {
        var problems: [String] = []
        expect(HistorySplit.parts([]).isEmpty, "An empty month produced parts", &problems)
        return problems
    }
}
