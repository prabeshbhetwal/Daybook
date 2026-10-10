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
/// place cancels the one being written. Nothing here is stored.
@MainActor final class NoteWriter: ObservableObject {
    /// Keyed by `HistoryPlace.id`.
    @Published private(set) var states: [String: NoteState] = [:]

    private weak var store: SessionStore?
    /// Keyed by place id, a newline and the facts' text, so a note is served
    /// only for the figures it was written from.
    // ponytail: never trimmed; a note is about 0.5 KB and only a request adds one, cap it if that ever matters.
    private var cache: [String: WrittenNote] = [:]
    private var running: Running?
    /// Checks only: stands in for the model. It gets the facts and may throw.
    /// Nothing in the app sets it. It stands in for the model's availability,
    /// never for the Apple Intelligence switch.
    var responder: (@MainActor (NoteFacts) async throws -> WrittenNote)?

    /// The note being written. Every task that is replaced or dropped is
    /// cancelled first, so a task that is not cancelled is this one.
    private struct Running {
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

    /// Writes unless a note for this place and these exact facts is cached.
    /// Asking for a place with no facts (no sessions, or a year) fails.
    func request(_ place: HistoryPlace, requested: Bool) {
        guard isUsable, let store else { return }
        guard let facts = store.noteFacts(for: place) else {
            stop()
            states[place.id] = .failed(requested: requested)
            return
        }
        let key = place.id + "\n" + facts.text
        if running?.key == key {
            if requested { running?.requested = true }
            return
        }
        stop()
        if let note = cache[key] {
            states[place.id] = .written(note)
            return
        }
        states[place.id] = .writing
        let task = Task { [weak self] in
            let note = try? await self?.write(facts)
            self?.finish(facts: facts, note: note)
        }
        running = Running(placeID: place.id, key: key, requested: requested, task: task)
    }

    /// For when a note's view goes away. Only the note being written for
    /// this place is stopped.
    func cancel(_ place: HistoryPlace) {
        if running?.placeID == place.id { stop() }
    }

    /// For snapshots only: shows a note without asking the model.
    func present(_ note: WrittenNote, for place: HistoryPlace) {
        states[place.id] = .written(note)
    }

    // MARK: - Writing

    /// Stops the note being written and clears its writing state.
    private func stop() {
        guard let current = running else { return }
        current.task.cancel()
        if states[current.placeID] == .writing { states[current.placeID] = nil }
        running = nil
    }

    /// What the model returned, or nil when it threw. A cancelled task has
    /// been replaced and its state cleared already; one that finds the
    /// switch off or the model gone leaves no state at all.
    private func finish(facts: NoteFacts, note: WrittenNote?) {
        guard !Task.isCancelled, let current = running else { return }
        running = nil
        guard isUsable else {
            states[current.placeID] = nil
            return
        }
        guard let note = Self.tidy(note, for: facts), NoteAudit.passes(note, facts: facts) else {
            states[current.placeID] = .failed(requested: current.requested)
            return
        }
        cache[current.key] = note
        states[current.placeID] = .written(note)
    }

    /// The note as shown: whitespace trimmed, and a tip only on a day and
    /// only when it says something.
    private static func tidy(_ note: WrittenNote?, for facts: NoteFacts) -> WrittenNote? {
        guard let note else { return nil }
        func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
        let tip = trimmed(note.tip ?? "")
        return WrittenNote(story: trimmed(note.story), pattern: trimmed(note.pattern),
                           tip: facts.kind == .day && !tip.isEmpty ? tip : nil)
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
