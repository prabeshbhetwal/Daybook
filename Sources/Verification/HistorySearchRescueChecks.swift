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
        ("A rescue never takes an app or category name", noNames),
        ("A rescue the model never answers ends, and the next one runs", unanswered),
        ("A rescue never changes a chip the model did not make or marks one the person typed", rereads),
    ]

    private typealias Fixture = AskLookupChecks.Fixture
    private typealias Reply = (phrases: [String], keep: [String])

    /// `SearchRescue` lives on the main actor, as the fixture's checks run.
    private static func fixture(_ body: @MainActor (Fixture, inout [String]) -> Void) -> [String] {
        AskLookupChecks.withFixture { f, problems in MainActor.assumeIsolated { body(f, &problems) } }
    }

    @MainActor private final class Asked {
        var words: [String] = []
        var gate: CheckedContinuation<Void, Never>?
    }

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
            let text = "Parser quarter before last"
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
            let text = "Parser quarter before last"
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
            field("Parser quarter", [], [], is: "Parser quarter", "no phrase and no words")
            field("Parser quarter", [], ["Parser"], is: "Parser quarter", "words alone")
            field("Parser quarter", ["sometime"], ["Parser"], is: "Parser quarter", "an unread phrase")
            field("Parser quarter", ["last week"], ["Invented"], is: "last week", "an invented word")
            field("Parser quarter", ["last week"], ["Parser", "Invented"], is: "last week", "one invented word of two")
            field("Parser quarter", ["last week"], ["Parser", "Parser"], is: "last week", "a word kept twice")
            field("Parser quarter", ["last week"], ["quarter", "Parser"], is: "last week quarter Parser",
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

    private static func noNames() -> [String] {
        fixture { f, problems in
            let text = "notes quarter"
            f.store.refreshReview()
            f.store.historyAppNames["com.apple.Notes"] = "Notes"
            let names = f.store.historyAppNames.values.sorted() + [WorkType.breakTime.displayName]
            expect(names.contains("Safari") && names.contains("Notes"), "the fixture names no app: \(names)", &problems)
            for name in names {
                let (rescue, asked) = press(f, text, [name], ["notes"])
                expect(asked.words.count == 1, "the model was not asked for \(name)", &problems)
                expect(f.store.historySearchText == text && f.store.historyFilter.appBundleID == nil
                       && f.store.historyFilter.workType == nil,
                       "\(name) changed the field to “\(f.store.historySearchText)”", &problems)
                expect(rescue.rescuedTexts.isEmpty, "\(name) was marked: \(rescue.rescuedTexts)", &problems)
            }
            // A name beside a real phrase is dropped; the phrase is taken.
            _ = press(f, text, ["Safari", "last week"], [])
            expect(f.store.historySearchText == "last week", "a name beside a phrase read “\(f.store.historySearchText)”",
                   &problems)
        }
    }

    private static func undo() -> [String] {
        fixture { f, problems in
            let manager = UndoManager()
            let text = "Parser quarter before last"
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

    /// The model never answers within the wait: it ignores cancellation and
    /// replies late. The wait ends, the text is left alone, a late reply does
    /// nothing, and a stale one does not stop a newer rescue.
    private static func unanswered() -> [String] {
        fixture { f, problems in
            let asked = Asked()
            let rescue = SearchRescue(store: f.store)
            rescue.timeout = .milliseconds(150)
            rescue.responder = { words in
                asked.words.append(words)
                if asked.words.count == 1 {
                    await withCheckedContinuation { (wake: CheckedContinuation<Void, Never>) in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { wake.resume() }
                    }
                } else {
                    await withCheckedContinuation { asked.gate = $0 }
                }
                return (["last week"], [])
            }
            f.store.setHistoryQuery("zzzz")
            rescue.rescue(undoManager: nil)
            expect(rescue.isRescuing, "a rescue was not under way", &problems)
            let ended = InstalledAppCatalog.turnRunLoop(until: { !rescue.isRescuing }, timeout: 5)
            expect(ended && f.store.historySearchText == "zzzz" && rescue.rescuedTexts.isEmpty,
                   "after the wait: ended \(ended), field “\(f.store.historySearchText)”", &problems)

            // Return again on other words; the first reply lands while this one waits.
            rescue.timeout = .seconds(10)
            f.store.setHistoryQuery("zzzz yyyy")
            rescue.rescue(undoManager: nil)
            _ = InstalledAppCatalog.turnRunLoop(until: { asked.words.count == 2 }, timeout: 5)
            expect(asked.words.count == 2 && rescue.isRescuing, "the second rescue did not run: asked \(asked.words.count)", &problems)
            _ = InstalledAppCatalog.turnRunLoop(until: { false }, timeout: 0.6)
            expect(rescue.isRescuing && f.store.historySearchText == "zzzz yyyy",
                   "a late reply ended or changed the newer rescue: \(rescue.isRescuing), “\(f.store.historySearchText)”", &problems)
            asked.gate?.resume()
            _ = InstalledAppCatalog.turnRunLoop(until: { !rescue.isRescuing }, timeout: 5)
            expect(f.store.historySearchText == "last week" && rescue.rescuedTexts == ["last week"],
                   "the second rescue read “\(f.store.historySearchText)”", &problems)

            // Typing on ends the wait at once, and the reply that follows changes nothing.
            f.store.setHistoryQuery("qqqq")
            rescue.rescue(undoManager: nil)
            _ = InstalledAppCatalog.turnRunLoop(until: { asked.words.count == 3 }, timeout: 5)
            expect(asked.words.count == 3 && rescue.isRescuing, "the third rescue did not run", &problems)
            f.store.setHistoryQuery("qqqq w")
            expect(!rescue.isRescuing, "typing left the rescue under way", &problems)
            asked.gate?.resume()
            _ = InstalledAppCatalog.turnRunLoop(until: { false }, timeout: 0.2)
            expect(f.store.historySearchText == "qqqq w" && rescue.rescuedTexts.isEmpty,
                   "a reply after typing changed “\(f.store.historySearchText)”", &problems)
        }
    }

    /// The probe's three rows: the new text must read as the phrases typed,
    /// then the model's, then the kept words. Anything else changes nothing.
    private static func rereads() -> [String] {
        fixture { f, problems in
            let rows: [(text: String, phrases: [String], keep: [String])] = [
                ("september zzzz", ["2022"], []),        // would join "september" into a September 2022 chip
                ("12 zzzz", ["october"], ["12"]),        // would swallow the kept "12" into a date
                ("last week zzzz", ["last week"], []),   // would repeat a phrase the person typed
            ]
            for row in rows {
                let (rescue, asked) = press(f, row.text, row.phrases, row.keep)
                expect(asked.words.count == 1, "the model was not asked about “\(row.text)”", &problems)
                expect(f.store.historySearchText == row.text,
                       "“\(row.text)” became “\(f.store.historySearchText)”", &problems)
                expect(rescue.rescuedTexts.isEmpty, "“\(row.text)” marked \(rescue.rescuedTexts)", &problems)
            }
            let (rescue, _) = press(f, "Parser quarter before last", ["the week before last"], ["Parser"])
            expect(f.store.historySearchText == "the week before last Parser" && rescue.rescuedTexts == ["the week before last"],
                   "a phrase the parser reads alone was not taken: “\(f.store.historySearchText)”", &problems)
        }
    }
}
