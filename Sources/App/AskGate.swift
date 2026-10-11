import Foundation

/// The one gate every lookup in one answer passes through, whichever model
/// asks. It knows no model: an adapter hands it a lookup's name and the
/// arguments the model sent, and takes back the text the model reads.
///
/// Lookups 1 to 5 are real: the catalogue reads the arguments, the store
/// answers, and the gate keeps the provenance and the sources and publishes a
/// progress line. Lookups 6 and 7 are told the limit and ask nothing. The 8th
/// ends the answer. An unknown name and a refused period count like any other.
///
/// The owner of the answer sets `isOpen` to false when the turn ends (stopped,
/// a new chat, a dropped session). A closed gate still answers a late call
/// from a model that has not heard, but counts and records nothing, so a
/// lookup from an answer that is over is never listed under the next one.
/// FoundationModels may call tools concurrently; the gate is on the main
/// actor, so calls are taken one at a time, in the order they arrive.
@MainActor
final class AskGate {
    /// Lookups that reach the store; the calls after them are told the limit.
    static let lookupLimit = 5
    /// The call that ends the answer.
    static let endsAt = 8

    private let store: SessionStore?
    private let period: (String) -> AskRange?
    private let onProgress: (String) -> Void
    private let onEnd: () -> Void

    /// The clock and calendar as the answer was asked. The source picker reads
    /// "today" and "yesterday" against these, not against the moment the answer
    /// finishes, which can be after midnight.
    let asked: Date
    let calendar: Calendar

    /// Lookups made while the gate was open, whether or not they were answered.
    private(set) var calls = 0
    /// `AskRequest.provenance` of each real lookup, in call order.
    private(set) var provenance: [String] = []
    /// The places each real lookup's figures came from, one entry per lookup,
    /// in call order: what the source picker reads.
    private(set) var lookups: [[AskLink]] = []
    var isOpen = true

    /// `period` reads a period as `AskModel.range(_:)` does. `onEnd` is called
    /// once, on the call that ends the answer.
    init(store: SessionStore?, period: @escaping (String) -> AskRange?,
         onProgress: @escaping (String) -> Void, onEnd: @escaping () -> Void) {
        self.store = store
        self.period = period
        self.onProgress = onProgress
        self.onEnd = onEnd
        asked = store?.now() ?? Date()
        calendar = store?.periodCalendar ?? Calendar.current.forPeriods
    }

    func lookup(name: String, arguments: [String: String]) -> String {
        if isOpen {
            calls += 1
            if calls > Self.lookupLimit {
                if calls == Self.endsAt { onEnd() }
                return AskFacts.lookupLimitReached
            }
        }
        guard let entry = AskLookups.named(name) else { return AskFacts.unknownLookup(name) }
        switch entry.read(arguments, period) {
        case let .refusal(text): return text
        case let .request(request): return run(request)
        }
    }

    /// With no store the text is empty, as it was before the gate existed.
    private func run(_ request: AskRequest) -> String {
        if isOpen { onProgress("Looking up \(request.provenance)…") }
        let result = store?.askLookupResult(request) ?? AskLookupResult(text: "", links: [])
        if isOpen {
            provenance.append(request.provenance)
            lookups.append(result.links)
        }
        return result.text
    }
}
