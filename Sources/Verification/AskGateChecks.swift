import Foundation

/// The gate every lookup in one Ask answer passes through: it counts, caps at
/// five real lookups, ends the answer on the eighth, publishes a progress line,
/// and keeps provenance and sources only while the turn is open. It knows no
/// model, so these checks drive it by name, as an adapter does.
enum AskGateChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Five lookups reach the store; the sixth and seventh are told the limit", fiveRealLookupsThenLimit),
        ("The eighth lookup ends the answer, once", eighthCallEndsAnswer),
        ("The progress line names the lookup being made", progressNamesLookup),
        ("A gate whose turn has ended answers and records nothing", closedGateRecordsNothing),
        ("An unknown lookup name and a refused period each count, and neither is listed", unknownAndRefusalCount),
        ("A gate with no store answers empty, and still counts and records", noStoreAnswersEmpty),
    ]

    /// What the gate told its owner.
    private final class Heard {
        var progress: [String] = []
        var ends = 0
    }

    private static let week = ["range": "this week"]
    private static let weekTotals = AskRequest.focusTotals(.thisWeek, words: nil)

    private static func withFixture(_ body: @MainActor (AskLookupChecks.Fixture, inout [String]) -> Void) -> [String] {
        AskModelChecks.withFixture(body)
    }

    @MainActor
    private static func makeGate(_ f: AskLookupChecks.Fixture, _ heard: Heard, hasStore: Bool = true) -> AskGate {
        AskGate(store: hasStore ? f.store : nil,
                period: { AskRange.resolving($0, now: f.store.now(), calendar: f.store.periodCalendar) },
                onProgress: { heard.progress.append($0) }, onEnd: { heard.ends += 1 })
    }

    // MARK: - Checks

    private static func fiveRealLookupsThenLimit() -> [String] {
        withFixture { f, problems in
            let heard = Heard()
            let gate = makeGate(f, heard)
            let want = f.store.askLookupResult(weekTotals)
            expect(!want.text.isEmpty && !want.links.isEmpty, "the store gave no totals to compare with", &problems)
            for call in 1...7 {
                let text = gate.lookup(name: "focusTotals", arguments: week)
                let expected = call <= AskGate.lookupLimit ? want.text : AskFacts.lookupLimitReached
                expect(text == expected, "call \(call) returned “\(text)”, not “\(expected)”", &problems)
            }
            expect(gate.calls == 7, "the gate counted \(gate.calls) calls, not 7", &problems)
            expect(gate.provenance == Array(repeating: "focus totals (this week)", count: 5),
                   "the provenance is \(gate.provenance)", &problems)
            expect(gate.lookups == Array(repeating: want.links, count: 5),
                   "the gate kept \(gate.lookups.count) lookups' sources, not 5 of the store's", &problems)
            expect(heard.progress.count == 5, "the progress line came \(heard.progress.count) times, not 5", &problems)
            expect(heard.ends == 0, "the answer ended \(heard.ends) times by the seventh call", &problems)
        }
    }

    private static func eighthCallEndsAnswer() -> [String] {
        withFixture { f, problems in
            let heard = Heard()
            let gate = makeGate(f, heard)
            for call in 1...9 {
                let text = gate.lookup(name: "focusTotals", arguments: week)
                let want = call == AskGate.endsAt || call == AskGate.endsAt + 1 ? 1 : 0
                expect(heard.ends == want, "after call \(call) the answer had ended \(heard.ends) times, not \(want)",
                       &problems)
                if call >= 6 {
                    expect(text == AskFacts.lookupLimitReached, "call \(call) returned “\(text)”", &problems)
                }
            }
            expect(gate.provenance.count == 5, "calls after the fifth were recorded: \(gate.provenance)", &problems)
        }
    }

    private static func progressNamesLookup() -> [String] {
        withFixture { f, problems in
            let heard = Heard()
            let gate = makeGate(f, heard)
            _ = gate.lookup(name: "focusTotals", arguments: week)
            expect(heard.progress == ["Looking up focus totals (this week)…"], "progress was \(heard.progress)", &problems)
            _ = gate.lookup(name: "compareFocus", arguments: ["first": "this week", "second": "last week"])
            expect(heard.progress.last == "Looking up comparison (this week with last week)…",
                   "the second lookup's progress was \(heard.progress)", &problems)
        }
    }

    private static func closedGateRecordsNothing() -> [String] {
        withFixture { f, problems in
            let heard = Heard()
            let gate = makeGate(f, heard)
            _ = gate.lookup(name: "focusTotals", arguments: week)
            _ = gate.lookup(name: "focusTotals", arguments: week)
            gate.isOpen = false
            let want = f.store.askLookupResult(weekTotals).text
            // Past the cap and the end, a closed gate still answers with the figures.
            for call in 1...9 {
                let text = gate.lookup(name: "focusTotals", arguments: week)
                expect(text == want, "closed call \(call) returned “\(text)”, not the store's text", &problems)
            }
            expect(gate.calls == 2, "a closed gate counted: \(gate.calls) calls, not 2", &problems)
            expect(gate.provenance.count == 2 && gate.lookups.count == 2,
                   "a closed gate recorded: \(gate.provenance), \(gate.lookups.count) lookups", &problems)
            expect(heard.progress.count == 2, "a closed gate published progress: \(heard.progress)", &problems)
            expect(heard.ends == 0, "a closed gate ended the answer \(heard.ends) times", &problems)
        }
    }

    private static func unknownAndRefusalCount() -> [String] {
        withFixture { f, problems in
            let heard = Heard()
            let gate = makeGate(f, heard)
            let unknown = gate.lookup(name: "nope", arguments: [:])
            expect(unknown == "No lookup called “nope”.", "an unknown name returned “\(unknown)”", &problems)
            expect(gate.calls == 1, "an unknown name made \(gate.calls) calls, not 1", &problems)
            let refusal = gate.lookup(name: "focusTotals", arguments: ["range": "31 february"])
            expect(refusal == AskFacts.noSuchPeriod("31 february"), "a refusal returned “\(refusal)”", &problems)
            expect(gate.calls == 2, "a refusal made \(gate.calls) calls in all, not 2", &problems)
            expect(gate.provenance.isEmpty && gate.lookups.isEmpty && heard.progress.isEmpty,
                   "they were recorded: \(gate.provenance), \(gate.lookups.count), \(heard.progress)", &problems)
            for _ in 3...5 { _ = gate.lookup(name: "nope", arguments: [:]) }
            let sixth = gate.lookup(name: "focusTotals", arguments: week)
            expect(sixth == AskFacts.lookupLimitReached, "after five counted calls the sixth returned “\(sixth)”",
                   &problems)
        }
    }

    private static func noStoreAnswersEmpty() -> [String] {
        withFixture { f, problems in
            let heard = Heard()
            let gate = makeGate(f, heard, hasStore: false)
            let text = gate.lookup(name: "focusTotals", arguments: week)
            expect(text.isEmpty, "a gate with no store returned “\(text)”", &problems)
            expect(gate.calls == 1 && gate.provenance == ["focus totals (this week)"] && gate.lookups == [[]],
                   "it recorded \(gate.calls) calls, \(gate.provenance), \(gate.lookups)", &problems)
        }
    }
}
