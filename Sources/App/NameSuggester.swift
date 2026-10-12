import Combine
import Foundation
import FoundationModels

/// What the model fills in for one unnamed session: which earlier name fits,
/// or a name of its own.
@available(macOS 26, *)
@Generable struct SuggestedName {
    @Guide(description: "1, 2 or 3 to reuse that earlier name, new for a fresh name, none when nothing fits.")
    var choice: String
    @Guide(description: "The fresh name, one to four words, when choice is new. Otherwise empty.")
    var name: String
}

/// A name on offer for an unnamed session, and how to say what it is for.
struct NameSuggestion: Equatable {
    let session: DaySession
    let name: String
    /// "this morning's 1h 20m session"
    let lead: String
}

/// Asks Apple's on-device model what to call each unnamed session, once, and
/// publishes the first answer that survives `NameAudit` for a session that is
/// still unnamed. Answers live in memory for this run; the words leave the
/// Mac nowhere. Only the notice starts it, through `refresh()`: the targets
/// and facts are rebuilt from the archive on every call, so nothing here
/// runs on the 1 Hz ticker.
@MainActor final class NameSuggester: ObservableObject {
    @Published private(set) var current: NameSuggestion?
    @Published private(set) var isAsking = false

    private weak var store: SessionStore?
    /// How long to wait for the model; checks shorten it.
    var timeout: Duration = .seconds(10)
    /// Stands in for the model in checks: the facts in, the model's choice
    /// out. It stands in for the model's availability, never for the Apple
    /// Intelligence switch.
    var responder: (@MainActor (NameFacts) async throws -> NameChoice)?

    /// The audited name per `NameFacts.cacheKey`; a nil value is a session
    /// the model had nothing for. A changed note makes a new key, asked again.
    // ponytail: never trimmed; an entry is a key and a name, and only two days of sessions add them.
    private var cache: [String: String?] = [:]
    /// Keys of names the person took with Name it. If they Undo, the session
    /// is not offered again this run.
    private var accepted: Set<String> = []
    /// The key `current` was published for.
    private var currentKey: String?
    /// Which question is under way, counted up whenever one starts or ends: a
    /// reply or a timer from an earlier one finds it is not current and does nothing.
    private var generation = 0
    private var asking: Task<Void, Never>?
    private var timer: Task<Void, Never>?

    init(store: SessionStore) {
        self.store = store
    }

    /// The switch is on and the model is ready, read on every call: either
    /// can change while the app runs.
    var isUsable: Bool {
        guard let store, store.appleIntelligenceEnabled else { return false }
        return responder != nil || ModelGate.modelAvailable
    }

    /// Offers the first unnamed session with a cached name; asks the model
    /// about the first one with no answer yet, and comes back here when it
    /// has one. A session with neither app evidence nor a note has no facts
    /// and is passed over unasked.
    func refresh() {
        guard isUsable, let store else { return cancelAll() }
        for session in store.nameSuggestionTargets() {
            guard let facts = store.nameFacts(for: session), !accepted.contains(facts.cacheKey) else { continue }
            guard let answer = cache[facts.cacheKey] else {
                offer(nil, key: nil)
                if !isAsking { ask(session, facts) }
                return
            }
            if let name = answer {
                offer(NameSuggestion(session: session, name: name, lead: store.nameSuggestionLead(for: session)),
                      key: facts.cacheKey)
                return
            }
        }
        offer(nil, key: nil)
    }

    /// Name it. A name the store refuses is not offered again.
    func accept() {
        guard let store, let offered = current, let key = currentKey else { return }
        if store.acceptNameSuggestion(offered.name, for: offered.session) {
            accepted.insert(key)
        } else {
            cache.updateValue(nil, forKey: key)
        }
        refresh()
    }

    /// Keep as is.
    func keep() {
        guard let store, let offered = current else { return }
        store.keepSessionUnnamed(offered.session)
        refresh()
    }

    /// For when the switch is turned off: nothing is offered and the question
    /// being asked is no longer waited for.
    func cancelAll() {
        end(generation)
        offer(nil, key: nil)
    }

    private func offer(_ suggestion: NameSuggestion?, key: String?) {
        if current != suggestion { current = suggestion }
        currentKey = key
    }

    // MARK: - Asking

    private func ask(_ session: DaySession, _ facts: NameFacts) {
        isAsking = true
        generation &+= 1
        let mine = generation
        asking = Task { [weak self] in await self?.finish(mine, session, facts) }
        // A sleeping timer, not a race: the model may ignore cancellation, and
        // a group would wait for it.
        timer = Task { [weak self, wait = timeout] in
            try? await Task.sleep(for: wait)
            self?.timedOut(mine, facts.cacheKey)
        }
    }

    /// Stops waiting for question `id`, unless another has begun since.
    private func end(_ id: Int) {
        guard id == generation, isAsking else { return }
        generation &+= 1
        isAsking = false
        asking?.cancel()
        timer?.cancel()
    }

    private func timedOut(_ id: Int, _ key: String) {
        guard id == generation, isAsking else { return }
        cache.updateValue(nil, forKey: key)
        end(id)
        refresh()
    }

    /// An error leaves the session with nothing to offer. A reply is dropped,
    /// and not remembered, when the wait was given up (the timeout or the
    /// switch), the switch is off, or the session is no longer a target:
    /// named on its card, kept, or gone.
    private func finish(_ id: Int, _ session: DaySession, _ facts: NameFacts) async {
        let choice = try? await asked(facts)
        guard let store, id == generation else { return }
        end(id)
        if isUsable, store.nameSuggestionTargets().contains(where: { $0.threadID == session.threadID }) {
            let name = choice.flatMap {
                NameAudit.resolve($0, candidates: facts.candidates, earlierNames: store.earlierSessionNames(),
                                  categories: WorkType.startable, appNames: facts.appNames)
            }
            cache.updateValue(name, forKey: facts.cacheKey)
        }
        refresh()
    }

    private func asked(_ facts: NameFacts) async throws -> NameChoice {
        if let responder { return try await responder(facts) }
        guard #available(macOS 26, *) else { throw CocoaError(.featureUnsupported) }
        return try await Self.generate(facts)
    }

    // MARK: - The model

    /// A fresh session per question: nothing from one session leaks into the next.
    @available(macOS 26, *)
    private static func generate(_ facts: NameFacts) async throws -> NameChoice {
        let session = LanguageModelSession(instructions: instructions)
        let reply = try await session.respond(to: facts.text, generating: SuggestedName.self, options: options).content
        return choice(reply.choice, reply.name)
    }

    /// 1, 2 or 3 reuse an earlier name, new takes the model's own; anything
    /// else is none. `NameAudit` decides what is shown.
    nonisolated static func choice(_ answer: String, _ name: String) -> NameChoice {
        switch answer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1": return .earlier(1)
        case "2": return .earlier(2)
        case "3": return .earlier(3)
        case "new": return .fresh(name)
        default: return .none
        }
    }

    /// Greedy: the same facts give the same answer. The macOS 27 SDK renames
    /// the argument and deprecates the old name.
    @available(macOS 26, *)
    private static var options: GenerationOptions {
        #if compiler(>=6.4)
        GenerationOptions(samplingMode: .greedy)
        #else
        GenerationOptions(sampling: .greedy)
        #endif
    }

    private static let instructions = "You name a stretch of focused work for the person who did it. You get the session's facts and up to three "
        + "earlier names they used for similar work. Answer 1, 2 or 3 to reuse an earlier name when it fits the work. "
        + "Answer new, with a name of one to four words, only when no earlier name fits and the note or the apps say "
        + "clearly what the work was. Otherwise answer none. Never put times, durations or numbers in a name."
}
