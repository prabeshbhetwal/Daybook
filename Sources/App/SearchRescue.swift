import Combine
import Foundation
import FoundationModels

/// What the model fills in for the words History's search could not read: the
/// phrases it understands them as, and the search words worth keeping.
@available(macOS 26, *)
@Generable struct RescuedSearch {
    @Guide(description: "Search phrases, each in one of the forms listed. Leave empty when unsure.")
    var phrases: [String]
    @Guide(description: "The typed words that name a task or session rather than a time or length, exactly as typed.")
    var keep: [String]
}

/// On Return, when the search box lists nothing, reads the unread words with
/// Apple's on-device model. The model proposes phrases and the parser decides:
/// only a phrase `SearchQuery` reads as exactly one period, weekday or length
/// phrase is taken. An app or category is never taken: the person names those
/// with a capital, and the model is not asked for them.
/// Taken phrases replace the unread words in the field as one undoable change.
/// Nothing is stored, and the words leave the Mac nowhere.
@MainActor final class SearchRescue: ObservableObject {
    @Published private(set) var isRescuing = false
    /// The phrases the model supplied that the field still holds, so their
    /// chips can carry the Apple Intelligence mark.
    @Published private(set) var rescuedTexts: Set<String> = []

    private weak var store: SessionStore?
    private var typing: AnyCancellable?
    /// Stands in for the model in checks: the unread words in, phrases and
    /// kept words out. It stands in for the model's availability, never for
    /// the Apple Intelligence switch.
    var responder: (@MainActor (String) async throws -> (phrases: [String], keep: [String]))?

    init(store: SessionStore) {
        self.store = store
        typing = store.$historySearchText.sink { [weak self] text in
            guard let self, !rescuedTexts.isEmpty else { return }
            rescuedTexts = rescuedTexts.filter(text.contains)
        }
    }

    /// The switch is on and the model is ready, read on every call: either
    /// can change while the app runs.
    var isUsable: Bool {
        guard let store, store.appleIntelligenceEnabled else { return false }
        return responder != nil || ModelGate.modelAvailable
    }

    /// Asks only when the field has unread words and lists nothing. A reply
    /// that arrives after the field changed, or fails, changes nothing.
    func rescue(undoManager: UndoManager?) {
        guard isUsable, !isRescuing, let store else { return }
        let original = store.historySearchText
        let leftover = store.historyParsedSearch.leftover
        guard !leftover.isEmpty, store.historySearchHits().isEmpty else { return }
        isRescuing = true
        Task { [weak self] in await self?.finish(original, leftover, undoManager) }
    }

    private func finish(_ original: String, _ leftover: String, _ undoManager: UndoManager?) async {
        defer { isRescuing = false }
        guard let store, let reply = try? await ask(leftover, store),
              isUsable, store.historySearchText == original else { return }
        let phrases = accepted(reply.phrases, store)
        // A phrase-less rescue would only drop words, and nothing is added
        // that was not typed: the kept words are the typed ones or none.
        guard !phrases.isEmpty else { return }
        var unused = Self.words(leftover)
        var kept: [String] = []
        for word in reply.keep {
            guard let at = unused.firstIndex(of: word) else { kept = []; break }
            unused.remove(at: at)
            kept.append(word)
        }
        // What is left once every unread word goes is what was read: the phrases already there.
        let read = store.historyParsedSearch.phrases.map { String(original[$0.range]) }
        undoManager?.registerUndo(withTarget: store) { $0.setHistoryQuery(original) }
        store.setHistoryQuery((read + phrases + kept).joined(separator: " "))
        rescuedTexts.formUnion(phrases)
    }

    /// The phrases, trimmed, that the parser reads as one period, weekday or length phrase and nothing else.
    private func accepted(_ phrases: [String], _ store: SessionStore) -> [String] {
        var taken: [String] = []
        for phrase in phrases.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !taken.contains(phrase) {
            let parsed = SearchQuery.parse(phrase, now: store.now(), calendar: store.periodCalendar,
                                           apps: store.historyAppNames, categories: WorkType.allCases)
            if parsed.phrases.count == 1, parsed.leftover.isEmpty,
               [.period, .weekdays, .length].contains(parsed.phrases[0].kind) { taken.append(phrase) }
        }
        return taken
    }

    /// The unread words as the parser sees them: a quoted run is one word, so
    /// a quote is never broken (the same rule as `SearchTokens`).
    private static func words(_ leftover: String) -> [String] {
        let quotes: Set<Character> = ["\"", "\u{201C}", "\u{201D}"]
        var words: [String] = []
        var open = false
        for piece in leftover.split(whereSeparator: \.isWhitespace) {
            let opens = !open && quotes.contains(piece.first!)
            if open { words[words.count - 1] += " " + piece } else { words.append(String(piece)) }
            if open || opens { open = !(quotes.contains(piece.last!) && (open || piece.count > 1)) }
        }
        return words
    }

    // MARK: - The model

    private func ask(_ leftover: String, _ store: SessionStore) async throws -> (phrases: [String], keep: [String]) {
        if let responder { return try await responder(leftover) }
        guard #available(macOS 26, *) else { throw CocoaError(.featureUnsupported) }
        let today = DateFormats.australian("EEEE d MMMM yyyy", in: store.periodCalendar.timeZone).string(from: store.now())
        return try await Self.generate(leftover, today: today)
    }

    /// A fresh session per search: nothing from one search leaks into the next.
    @available(macOS 26, *)
    private static func generate(_ leftover: String, today: String) async throws -> (phrases: [String], keep: [String]) {
        let session = LanguageModelSession(instructions: instructions(today: today))
        let reply = try await session.respond(to: leftover, generating: RescuedSearch.self, options: options).content
        return (reply.phrases, reply.keep)
    }

    /// Greedy: the same words give the same phrases. The macOS 27 SDK renames
    /// the argument and deprecates the old name.
    @available(macOS 26, *)
    private static var options: GenerationOptions {
        #if compiler(>=6.4)
        GenerationOptions(samplingMode: .greedy)
        #else
        GenerationOptions(sampling: .greedy)
        #endif
    }

    private static func instructions(today: String) -> String {
        "You turn words typed into a focus app's search box into search phrases it understands. Today is \(today). "
            + "Use only these forms: today; yesterday; this week; last week; this month; last month; this year; last year; "
            + "the week before last; the month before last; N days ago; N weeks ago; N months ago; last N days; last N weeks; "
            + "a month name and year; a day, month and year; a year; a weekday in the plural such as Mondays; weekends; weekdays; "
            + "over D; under D; between D and D, where D is like 1h or 30m. "
            + "Put words that name a task or session, not a time or length, in keep, exactly as typed. Give no phrase you are unsure of."
    }
}
