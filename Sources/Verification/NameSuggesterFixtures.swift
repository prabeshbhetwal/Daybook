import Foundation

/// The fixtures `NameSuggesterChecks` runs over: two unnamed sessions, A today
/// 7:00-7:30 in Xcode and B yesterday 14:00-14:45 in Xcode and Terminal, over
/// an earlier name, and a suggester whose model is a closure.
extension NameSuggesterChecks {
    private typealias Checks = NameSuggestionStoreChecks
    typealias Fixture = NameSuggestionStoreChecks.Fixture

    struct Refused: Error {}

    @MainActor final class Calls {
        var facts: [NameFacts] = []
    }

    static func pair(_ body: @MainActor (Fixture, UUID, UUID, inout [String]) -> Void) -> [String] {
        let (a, b) = (UUID(), UUID())
        return Checks.withFixture(records: { days in [
            Checks.record(days.at(0, 7), days.at(0, 7, 30), thread: a),
            Checks.record(days.at(1, 14), days.at(1, 14, 45), thread: b),
            Checks.record(days.at(3, 9), days.at(3, 10), name: "Daybook"),
        ] }, usage: { days in [
            Checks.app("Xcode", days.at(0, 7), 25 * 60), Checks.app("Xcode", days.at(1, 14), 20 * 60),
            Checks.app("Terminal", days.at(1, 14, 20), 20 * 60),
            Checks.app("Xcode", days.at(3, 9), 25 * 60), Checks.app("Terminal", days.at(3, 9, 25), 25 * 60),
        ] }) { f, _, problems in body(f, a, b, &problems) }
    }

    /// A suggester whose model is `reply`, given how many questions have been
    /// asked, this one included. Every check sets a responder: none may reach
    /// the live model.
    @MainActor static func make(
        _ f: Fixture, _ calls: Calls,
        reply: @escaping @MainActor (Int) async throws -> NameChoice = { _ in .earlier(1) }
    ) -> NameSuggester {
        f.persistence.useAppleIntelligence = true
        let suggester = NameSuggester(store: f.store)
        suggester.responder = { facts in
            calls.facts.append(facts)
            return try await reply(calls.facts.count)
        }
        return suggester
    }

    @MainActor static func settle(_ s: NameSuggester) {
        _ = InstalledAppCatalog.turnRunLoop(until: { !s.isAsking }, timeout: 5)
    }

    @MainActor static func run(_ s: NameSuggester) {
        s.refresh()
        settle(s)
    }

    /// A wait the task cannot cancel: a model that ignores cancellation.
    @MainActor static func pause(_ seconds: Double) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { continuation.resume() }
        }
    }

    @MainActor static func undoLastCorrection(_ f: Fixture) -> Bool {
        guard let correction = f.store.lastCorrection else { return false }
        return f.store.undoCorrection(expectedID: correction.id)
    }
}
