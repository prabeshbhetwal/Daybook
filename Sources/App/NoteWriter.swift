import Combine
import Foundation
import FoundationModels

/// Where one place's note stands. A place nobody has asked for has no state.
enum NoteState: Equatable {
    case writing
    case written(WrittenNote)
    /// `requested` is true when the person asked for the note. A note nobody
    /// asked for that fails shows nothing.
    case failed(requested: Bool)
}

/// Asks Apple's on-device model for one note per place, checks it against the
/// facts it was written from and keeps it in memory. Only the notes' views
/// start it, and only one note is written at a time: asking for another
/// place sets the one being written aside, to be written once the newer one
/// is done unless its view goes away first. Nothing here is stored.
@MainActor final class NoteWriter: ObservableObject {
    /// Keyed by `HistoryPlace.id`.
    @Published private(set) var states: [String: NoteState] = [:]

    private weak var store: SessionStore?
    /// Keyed by place id, a newline and the facts' text, so a note is served
    /// only for the figures it was written from.
    // ponytail: never trimmed; a note is about 0.5 KB and only a request adds one, cap it if that ever matters.
    private var cache: [String: WrittenNote] = [:]
    /// The keys of notes that failed. The model is greedy, so the same facts
    /// would fail the same way; changed facts make a new key and are tried.
    // ponytail: never trimmed either, for the same reason as the cache.
    private var failedKeys: Set<String> = []
    /// The key each place's `.written` or `.failed` state was published for,
    /// so a note shown for figures that have since moved can be told.
    // ponytail: one key per place, never trimmed; cap it if that ever matters.
    private var publishedKeys: [String: String] = [:]
    private var running: Running?
    /// Places whose write was set aside for a newer request, oldest first.
    /// Each shows `.writing` until it is started again or its view cancels.
    private var pending: [Pending] = []
    /// Checks only: stands in for the model. It gets the facts and may throw.
    /// Nothing in the app sets it. It stands in for the model's availability,
    /// never for the Apple Intelligence switch.
    var responder: (@MainActor (NoteFacts) async throws -> WrittenNote)?

    private struct Pending {
        let place: HistoryPlace
        let requested: Bool
    }

    /// The note being written. Every task that is replaced or dropped is
    /// cancelled first, so a task that is not cancelled is this one.
    private struct Running {
        let place: HistoryPlace
        let placeID: String
        let key: String
        var requested: Bool
        let task: Task<Void, Never>
    }

    init(store: SessionStore) {
        self.store = store
    }

    /// The switch is on and the model is ready, read on every call: either
    /// can change while the app runs.
    var isUsable: Bool {
        guard let store, store.appleIntelligenceEnabled else { return false }
        return responder != nil || ModelGate.modelAvailable
    }

    func state(for place: HistoryPlace) -> NoteState? {
        states[place.id]
    }

    /// Writes unless a note for this place and these exact facts is cached or
    /// has already failed; a failure is shown again without asking the model.
    /// Asking for a place with no facts (no sessions, or a year) fails. A
    /// write goes first: the note being written for another place waits, and
    /// is started again when the writer is idle.
    func request(_ place: HistoryPlace, requested: Bool) {
        guard isUsable, let store else { return }
        pending.removeAll { $0.place.id == place.id }
        guard let facts = store.noteFacts(for: place) else {
            if running?.placeID == place.id { stop() }
            fail(place.id, key: Self.cacheKey(place, nil), requested: requested)
            startPending()
            return
        }
        let key = Self.cacheKey(place, facts)
        if running?.key == key {
            if requested { running?.requested = true }
            return
        }
        if running?.placeID == place.id { stop() }
        if let note = cache[key] {
            publish(.written(note), for: place.id, key: key)
            startPending()
            return
        }
        if failedKeys.contains(key) {
            fail(place.id, key: key, requested: requested)
            startPending()
            return
        }
        if let current = running {
            current.task.cancel()
            pending.append(Pending(place: current.place, requested: current.requested))
            running = nil
        }
        states[place.id] = .writing
        let task = Task { [weak self] in
            let note = try? await self?.write(facts)
            self?.finish(facts: facts, note: note)
        }
        running = Running(place: place, placeID: place.id, key: key, requested: requested, task: task)
    }

    /// For when a note's view goes away: its note is no longer written, being
    /// written or waiting to be, and the next place waiting is started.
    func cancel(_ place: HistoryPlace) {
        if running?.placeID == place.id { stop() }
        if pending.contains(where: { $0.place.id == place.id }) {
            pending.removeAll { $0.place.id == place.id }
            if states[place.id] == .writing { states[place.id] = nil }
        }
        startPending()
    }

    /// For when the model becomes unusable, the switch turned off: the note
    /// being written is stopped and those waiting are dropped, so none is left
    /// showing "Writing…". Notes already written stay in memory.
    func cancelAll() {
        stop()
        dropPending()
    }

    /// For an on-request note's view when it appears: a note or failure shown
    /// for facts that have since changed is forgotten, so the person's link
    /// comes back. A note being written is left alone.
    func forgetIfStale(_ place: HistoryPlace) {
        switch states[place.id] {
        case .written?, .failed?:
            guard let store else { return }
            if publishedKeys[place.id] != Self.cacheKey(place, store.noteFacts(for: place)) { states[place.id] = nil }
        default:
            break
        }
    }

    /// For snapshots only: shows a note without asking the model. It is
    /// cached for the place's facts too, so a view that then asks for the
    /// place is served this note and not a write.
    func present(_ note: WrittenNote, for place: HistoryPlace) {
        let facts = store?.noteFacts(for: place)
        let key = Self.cacheKey(place, facts)
        publish(.written(note), for: place.id, key: key)
        if facts != nil { cache[key] = note }
    }

    // MARK: - Writing

    /// The place and its facts' text; a place with no facts has the bare
    /// place, which no facts' key equals.
    private static func cacheKey(_ place: HistoryPlace, _ facts: NoteFacts?) -> String {
        place.id + "\n" + (facts?.text ?? "")
    }

    private func publish(_ state: NoteState, for placeID: String, key: String) {
        states[placeID] = state
        publishedKeys[placeID] = key
    }

    /// Shows a failure. One the person asked to see stays when an automatic
    /// request fails the same place again.
    private func fail(_ placeID: String, key: String, requested: Bool) {
        publish(.failed(requested: requested || states[placeID] == .failed(requested: true)), for: placeID, key: key)
    }

    /// Starts the place set aside most recently, when nothing is being written.
    /// A place whose note is already cached or has failed is settled at once
    /// and the next one is tried. A switch turned off drops them all.
    private func startPending() {
        guard running == nil else { return }
        guard isUsable else { return dropPending() }
        while running == nil, let next = pending.popLast() {
            request(next.place, requested: next.requested)
        }
    }

    private func dropPending() {
        for entry in pending where states[entry.place.id] == .writing { states[entry.place.id] = nil }
        pending.removeAll()
    }

    /// Stops the note being written and clears its writing state.
    private func stop() {
        guard let current = running else { return }
        current.task.cancel()
        if states[current.placeID] == .writing { states[current.placeID] = nil }
        running = nil
    }

    /// What the model returned, or nil when it threw. A note that fails is
    /// remembered by its key. A cancelled task has been replaced or dropped
    /// already; one that finds the switch off or the model gone leaves no
    /// state at all, and the places waiting are dropped. Otherwise the next
    /// place waiting is started.
    private func finish(facts: NoteFacts, note: WrittenNote?) {
        guard !Task.isCancelled, let current = running else { return }
        running = nil
        guard isUsable else {
            states[current.placeID] = nil
            return dropPending()
        }
        if let note = Self.tidy(note, for: facts), NoteAudit.passes(note, facts: facts) {
            cache[current.key] = note
            publish(.written(note), for: current.placeID, key: current.key)
        } else {
            failedKeys.insert(current.key)
            publish(.failed(requested: current.requested), for: current.placeID, key: current.key)
        }
        startPending()
    }

    /// The note as shown: whitespace trimmed, and a tip only on a day and
    /// only when it says something. A blank story or pattern is no note; the
    /// audit passes it, having no figures to refuse.
    private static func tidy(_ note: WrittenNote?, for facts: NoteFacts) -> WrittenNote? {
        guard let note else { return nil }
        func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
        let story = trimmed(note.story), pattern = trimmed(note.pattern), tip = trimmed(note.tip ?? "")
        guard !story.isEmpty, !pattern.isEmpty else { return nil }
        return WrittenNote(story: story, pattern: pattern, tip: facts.kind == .day && !tip.isEmpty ? tip : nil)
    }

    private func write(_ facts: NoteFacts) async throws -> WrittenNote {
        if let responder { return try await responder(facts) }
        guard #available(macOS 26, *) else { throw CocoaError(.featureUnsupported) }
        return try await Self.generate(facts)
    }

    // MARK: - The model

    /// A fresh session per note: nothing from one period leaks into the next.
    @available(macOS 26, *)
    private static func generate(_ facts: NoteFacts) async throws -> WrittenNote {
        let session = LanguageModelSession(instructions: instructions)
        let reply = try await session.respond(to: facts.text, generating: GeneratedNote.self, options: options)
        return WrittenNote(story: reply.content.story, pattern: reply.content.pattern, tip: reply.content.tip)
    }

    /// Greedy: the same facts give the same note, so a failed audit is not
    /// worth a second try. The macOS 27 SDK renames the argument and
    /// deprecates the old name.
    @available(macOS 26, *)
    private static var options: GenerationOptions {
        #if compiler(>=6.4)
        GenerationOptions(samplingMode: .greedy)
        #else
        GenerationOptions(sampling: .greedy)
        #endif
    }

    private static let instructions = "You write a short private note for the person who recorded this focus history in Daybook. "
        + "Use only the facts given. Write every figure in digits, exactly as the facts write it, and add no figure of your own. "
        + "Never total, average or compare figures yourself; use the comparisons the facts give. "
        + "Write in plain Australian English, in the second person, past tense for a finished period and present tense for one marked so far. "
        + "Do not praise or scold."
}

/// What the model fills in. The audit reads the figures in all three.
@available(macOS 26, *)
@Generable struct GeneratedNote {
    @Guide(description: "At most two sentences on what the person worked on and in what order. Quote session names exactly as written.")
    var story: String
    @Guide(description: "One sentence building on exactly one of the listed observations.")
    var pattern: String
    @Guide(description: "For a day: one sentence of advice for the next day, building on one listed observation. For a week or month: empty.")
    var tip: String
}
