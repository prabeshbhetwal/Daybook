import Foundation

/// What pressing Return does to a History search that found nothing: the
/// model (here a `responder`, never the live one) proposes phrases for the
/// unread words and the parser decides which are taken. "Now" is Wednesday
/// 15 November 2023 (`AskLookupChecks.withFixture`), whose sessions are
/// Thesis on Mon 13 Nov, Parser on Tue 14 Nov and Thesis on Tue 17 Oct.
enum HistorySearchRescueChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A rescued phrase replaces the unread words and is marked", accepted),
        ("A phrase the parser cannot read changes nothing", rejected),
        ("The model is not asked when results exist, the switch is off, or nothing is left over", notAsked),
        ("A rescue never adds words and never empties a search without a phrase", keptWords),
        ("A failed or outdated reply changes nothing", failedOrStale),
        ("Undo restores the typed text", undo),
    ]

    private typealias Fixture = AskLookupChecks.Fixture
    private typealias Reply = (phrases: [String], keep: [String])

    /// `SearchRescue` lives on the main actor, as the fixture's checks run.
    private static func fixture(_ body: @MainActor (Fixture, inout [String]) -> Void) -> [String] {
        AskLookupChecks.withFixture { f, problems in MainActor.assumeIsolated { body(f, &problems) } }
    }

    @MainActor private final class Asked { var words: [String] = [] }

    /// Types `text`, presses Return with a model that answers `reply`, and
    /// waits for the rescue to end.
    @MainActor private static func press(_ f: Fixture, _ text: String, undo: UndoManager? = nil,
                                         reply: @escaping @MainActor (String) async throws -> Reply)
        -> (rescue: SearchRescue, asked: Asked) {
        let asked = Asked()
        let rescue = SearchRescue(store: f.store)
        rescue.responder = { words in asked.words.append(words); return try await reply(words) }
        f.store.setHistoryQuery(text)
        rescue.rescue(undoManager: undo)
        _ = InstalledAppCatalog.turnRunLoop(until: { !rescue.isRescuing }, timeout: 5)
        return (rescue, asked)
    }

    @MainActor private static func press(_ f: Fixture, _ text: String, _ phrases: [String], _ keep: [String] = [])
        -> (rescue: SearchRescue, asked: Asked) {
        press(f, text) { _ in (phrases, keep) }
    }

    private static func accepted() -> [String] {
        fixture { f, problems in
            let text = "Parser fortnight before last"
            let (rescue, asked) = press(f, text, ["the week before last"], ["Parser"])
            expect(asked.words == [text], "the model was given \(asked.words), not the unread words", &problems)
            expect(f.store.historySearchText == "the week before last Parser",
                   "the field reads “\(f.store.historySearchText)”", &problems)
            expect(rescue.rescuedTexts == ["the week before last"], "marked: \(rescue.rescuedTexts)", &problems)
            expect(f.store.historyParsedSearch.phrases.count == 1 && f.store.historyFilter.span != nil
                   && f.store.historyFilter.query == "Parser", "the filter did not follow the new text", &problems)

            // The phrases already read stay; only the unread words go.
            let (second, _) = press(f, "zzzz Mondays", ["last week"])
            expect(f.store.historySearchText == "Mondays last week",
                   "a text with a phrase already in it reads “\(f.store.historySearchText)”", &problems)
            expect(second.rescuedTexts == ["last week"], "marked: \(second.rescuedTexts)", &problems)

            // The mark goes when its words do.
            let (third, _) = press(f, "zzzz", ["last week"])
            f.store.setHistoryQuery("last month")
            expect(third.rescuedTexts.isEmpty, "a mark outlived its words: \(third.rescuedTexts)", &problems)
        }
    }

    private static func rejected() -> [String] {
        fixture { f, problems in
            let text = "Parser fortnight before last"
            for phrases in [["sometime soon"], ["last week Parser"], ["last week today"], ["Mondays over 1h"], [""]] {
                let (rescue, asked) = press(f, text, phrases, ["Parser"])
                expect(asked.words.count == 1, "the model was not asked for \(phrases)", &problems)
                expect(f.store.historySearchText == text,
                       "\(phrases) changed the field to “\(f.store.historySearchText)”", &problems)
                expect(rescue.rescuedTexts.isEmpty, "\(phrases) was marked: \(rescue.rescuedTexts)", &problems)
            }
            let (rescue, _) = press(f, text, ["sometime soon", " last week "], [])
            expect(f.store.historySearchText == "last week", "one good phrase of two read “\(f.store.historySearchText)”",
                   &problems)
            expect(rescue.rescuedTexts == ["last week"], "marked: \(rescue.rescuedTexts)", &problems)
        }
    }

    private static func notAsked() -> [String] {
        fixture { f, problems in
            @MainActor func asks(_ text: String, _ what: String) {
                let (_, asked) = press(f, text, ["last week"])
                expect(asked.words.isEmpty, "the model was asked (\(asked.words)) \(what)", &problems)
                expect(f.store.historySearchText == text, "\(what) changed the field to “\(f.store.historySearchText)”",
                       &problems)
            }
            asks("Thesis", "when the word matches sessions")
            asks("last week", "when nothing is left over")
            asks("", "on an empty field")

            f.store.engine.store.useAppleIntelligence = false
            let (rescue, asked) = press(f, "zzzz", ["last week"])
            expect(!rescue.isUsable && asked.words.isEmpty, "the model was asked with the switch off", &problems)
            expect(f.store.historySearchText == "zzzz", "the switch off changed the field", &problems)

            f.store.engine.store.useAppleIntelligence = true
            let again = SearchRescue(store: f.store)
            again.responder = { _ in (["last week"], []) }
            f.store.setHistoryQuery("zzzz")
            again.rescue(undoManager: nil)
            again.rescue(undoManager: nil)
            expect(again.isRescuing, "a rescue was not under way", &problems)
            _ = InstalledAppCatalog.turnRunLoop(until: { !again.isRescuing }, timeout: 5)
            expect(f.store.historySearchText == "last week", "the switch back on read “\(f.store.historySearchText)”",
                   &problems)
        }
    }

    // Review Focus 5.
    private static func keptWords() -> [String] {
        fixture { f, problems in
            @MainActor func field(_ text: String, _ phrases: [String], _ keep: [String], is expected: String, _ what: String) {
                _ = press(f, text, phrases, keep)
                expect(f.store.historySearchText == expected,
                       "\(what): the field reads “\(f.store.historySearchText)”, not “\(expected)”", &problems)
            }
            field("Parser fortnight", [], [], is: "Parser fortnight", "no phrase and no words")
            field("Parser fortnight", [], ["Parser"], is: "Parser fortnight", "words alone")
            field("Parser fortnight", ["sometime"], ["Parser"], is: "Parser fortnight", "an unread phrase")
            field("Parser fortnight", ["last week"], ["Invented"], is: "last week", "an invented word")
            field("Parser fortnight", ["last week"], ["Parser", "Invented"], is: "last week", "one invented word of two")
            field("Parser fortnight", ["last week"], ["Parser", "Parser"], is: "last week", "a word kept twice")
            field("Parser fortnight", ["last week"], ["fortnight", "Parser"], is: "last week fortnight Parser",
                  "typed words")
            field("zzzz \"Mondays standup\"", ["last week"], ["\"Mondays standup\""],
                  is: "last week \"Mondays standup\"", "a quoted run")
            field("zzzz \"Mondays standup\"", ["last week"], ["\"Mondays"], is: "last week", "half a quoted run")
        }
    }

    private static func failedOrStale() -> [String] {
        fixture { f, problems in
            struct Refused: Error {}
            let (failed, asked) = press(f, "zzzz") { _ in throw Refused() }
            expect(asked.words.count == 1 && f.store.historySearchText == "zzzz" && failed.rescuedTexts.isEmpty,
                   "a refusal changed the field to “\(f.store.historySearchText)”", &problems)
            expect(!failed.isRescuing, "a refusal left the rescue under way", &problems)

            // The person typed on while the model was answering.
            let (stale, _) = press(f, "zzzz") { _ in
                f.store.setHistoryQuery("zzzz yyyy")
                return (["last week"], [])
            }
            expect(f.store.historySearchText == "zzzz yyyy" && stale.rescuedTexts.isEmpty,
                   "an outdated reply changed the field to “\(f.store.historySearchText)”", &problems)

            // The switch went off while the model was answering.
            let (off, _) = press(f, "zzzz") { _ in
                f.store.engine.store.useAppleIntelligence = false
                return (["last week"], [])
            }
            expect(f.store.historySearchText == "zzzz" && off.rescuedTexts.isEmpty,
                   "a reply after the switch went off changed the field", &problems)
        }
    }

    private static func undo() -> [String] {
        fixture { f, problems in
            let manager = UndoManager()
            let text = "Parser fortnight before last"
            let (rescue, _) = press(f, text, undo: manager) { _ in (["the week before last"], ["Parser"]) }
            expect(f.store.historySearchText == "the week before last Parser", "the rescue did not run", &problems)
            expect(manager.canUndo, "the rescue registered no undo", &problems)
            manager.undo()
            expect(f.store.historySearchText == text, "undo left “\(f.store.historySearchText)”", &problems)
            expect(f.store.historyParsedSearch.leftover == text && f.store.historyFilter.span == nil,
                   "undo left the filter on the rescued phrase", &problems)
            expect(rescue.rescuedTexts.isEmpty, "undo left a mark: \(rescue.rescuedTexts)", &problems)
        }
    }
}
