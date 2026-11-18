import Foundation

/// Activity-aware sessions: the sweep. Each row of `ActivityTraces.all` is derived
/// and held to its expected label, depth, phases, splits and credited seconds.
enum ActivitySweepChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = ActivityTraces.all.map { row in
        ("Sweep: \(row.name) is \(text(row.expect.label))", { check(row.input, row.expect) })
    }

    static func text(_ label: ActivityLabel) -> String {
        switch label {
        case .activity(let purpose): return purpose.displayName
        case .mixed: return "Mixed"
        case .unsorted: return "Unsorted"
        }
    }

    private static func check(_ input: DerivationInput, _ expected: SweepExpectation) -> [String] {
        var problems: [String] = []
        let shape = ActivityDerivation.derive(input)
        let seen = "label \(shape.label), depth \(shape.depth.map(\.rawValue) ?? "nil"), phases \(shape.phases.map(\.activity)), "
            + "counted \(shape.phases.map(\.counted)), splits \(shape.splitCandidates.count), credited \(shape.credited)"
        expect(shape.label == expected.label, "label should be \(expected.label); \(seen)", &problems)
        if let depth = expected.depth {
            expect(shape.depth == depth, "depth should be \(depth.rawValue); \(seen)", &problems)
        }
        if let phases = expected.phases {
            expect(shape.phases.map(\.activity) == phases, "phases should be \(phases); \(seen)", &problems)
        }
        if let counted = expected.counted {
            expect(shape.phases.map(\.counted) == counted, "phases counted should be \(counted); \(seen)", &problems)
        }
        if let splits = expected.splitCandidates {
            expect(shape.splitCandidates.count == splits, "split candidates should be \(splits); \(seen)", &problems)
        }
        if let credited = expected.creditedSeconds {
            let total = shape.credited.values.reduce(0, +)
            expect(abs(total - credited) <= 30, "credited seconds should be \(Int(credited)); \(seen)", &problems)
        }
        for (purpose, seconds) in expected.purposeSeconds ?? [:] {
            let got = shape.credited[purpose.rawValue] ?? 0
            expect(abs(got - seconds) <= 30, "\(purpose.rawValue) should be \(Int(seconds)) s; \(seen)", &problems)
        }
        return problems
    }
}
