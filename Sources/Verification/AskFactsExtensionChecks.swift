import Foundation

/// Ask Daybook v2 part 2: what the lookups say beyond part 1's facts. A
/// session list says when each session began with “from”, so the model
/// cannot read `2:00pm · Parser · 4h` as 2h 00m, and shows each session's
/// note, not only a note that matched the words.
enum AskFactsExtensionChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A session line says when it began with “from”", sessionLineSaysFrom),
        ("Every listed session shows its note", everyListedSessionShowsItsNote),
        ("A note line that matches the words wins over the first line", matchingNoteLineWins),
    ]

    private static func sessionLineSaysFrom() -> [String] {
        var problems: [String] = []
        let timed = AskFacts.sessions(.allTime, words: "", lines: [
            AskSessionLine(day: "Tue 15 Sep", time: "2:00pm", name: "Parser", worked: 14_400)])
        expect(timed == "Tue 15 Sep · Parser · from 2:00pm · 4h", "a timed session says “\(timed)”", &problems)
        let untimed = AskFacts.sessions(.allTime, words: "", lines: [
            AskSessionLine(day: "Tue 15 Sep", time: "", name: "Parser", worked: 14_400)])
        expect(untimed == "Tue 15 Sep · Parser · 4h", "a session with no time says “\(untimed)”", &problems)
        return problems
    }

    private static func everyListedSessionShowsItsNote() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            let text = f.store.askLookup(.findSessions(words: "", .allTime))
            expect(text.contains("Thesis · from 9:00am · 1h · note: chapter two outline"),
                   "Mon 13 Nov's Thesis is listed as “\(text)”", &problems)
            // The other sessions have no note, so none is invented for them.
            expect(text.contains("Parser · from 2:00pm · 1h 30m"), "Parser is listed as “\(text)”", &problems)
            expect(!text.contains("Parser · from 2:00pm · 1h 30m · note"),
                   "Parser, which has no note, is listed with one: “\(text)”", &problems)
        }
    }

    private static func matchingNoteLineWins() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            guard let thesis = f.store.metadataArchive.allMetadata.first(where: { $0.note == "chapter two outline" }),
                  case .saved = f.store.metadataArchive.saveNote("first line\nchapter two outline", for: thesis.recordID)
            else { problems.append("could not save the two-line note"); return }
            let matched = f.store.askLookup(.findSessions(words: "outline", .allTime))
            expect(matched.contains("note: chapter two outline") && !matched.contains("note: first line"),
                   "a search for “outline” says “\(matched)”", &problems)
            let all = f.store.askLookup(.findSessions(words: "", .allTime))
            expect(all.contains("note: first line") && !all.contains("note: chapter two outline"),
                   "a search with no words says “\(all)”", &problems)
        }
    }
}
