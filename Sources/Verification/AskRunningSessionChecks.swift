import Foundation

/// A search reads saved sessions, so a session still running is not in what it
/// finds, though the timer shows it. Ask says so, whenever the range holds
/// today and a session runs, on the answers that come from a search.
enum AskRunningSessionChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Ask says a running session is not counted in word searches over a range holding today",
         searchesNameTheRunningSession),
        ("A long Ask answer keeps the running-session sentence inside the byte cap", sentenceSurvivesTheCap),
    ]

    private static let sentence = " A session running now is not counted until it ends."

    private static func searchesNameTheRunningSession() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            f.engine.start(workType: .deepWork, intent: "Thesis")
            f.clock.advance(20 * 60)

            func says(_ request: AskRequest, _ text: String, _ wantSentence: Bool) {
                let got = f.store.askLookup(request)
                let want = wantSentence ? text + sentence : text
                expect(got == want, "\(request.provenance) says “\(got)”, not “\(want)”", &problems)
            }

            // The timer shows Thesis today, and the search cannot see it.
            says(.focusTotals(.today, words: "thesis"), "No sessions match “thesis” today.", true)
            says(.focusTotals(.thisWeek, words: "thesis"),
                 "Sessions matching “thesis” this week: 1h over 1 session on 1 day.", true)
            says(.findSessions(words: "thesis", .today), "No sessions match “thesis” today.", true)
            says(.findSessions(words: "thesis", .thisWeek), "Mon 13 Nov · Thesis · 1h", true)
            says(.appTime(.thisWeek, app: "safari"), "Safari this week: 1h in front; used in 1 session.", true)
            says(.appTime(.today, app: "safari"), "No app called “safari” was used today.", true)

            // Ranges that end before today do not hold the session.
            says(.focusTotals(.lastWeek, words: "thesis"), "No sessions match “thesis” last week.", false)
            says(.findSessions(words: "thesis", .yesterday), "No sessions match “thesis” yesterday.", false)
            says(.appTime(.lastWeek, app: "safari"), "No app called “safari” was used last week.", false)

            // Answers that already count the running session, or take no words, are left alone.
            says(.focusTotals(.today, words: nil), "Today: 20m focused over 1 session on 1 day.", false)
            says(.appTime(.today, app: nil), "No app use recorded today.", false)
            says(.bestHours(.today), "Not enough focus today to tell; it needs at least 30m.", false)

            // Once the session ends it is in the record, and the sentence goes.
            expect(f.engine.stop(), "the session did not stop", &problems)
            says(.focusTotals(.today, words: "thesis"),
                 "Sessions matching “thesis” today: 20m over 1 session on 1 day.", false)
        }
    }

    private static func sentenceSurvivesTheCap() -> [String] {
        var problems: [String] = []
        // The cap includes the sentence, which is kept whole after the cut.
        let cut = AskFacts.capped(String(repeating: "a", count: 2_000), keeping: sentence)
        expect(cut.utf8.count == AskFacts.maximumBytes && cut.hasSuffix("…" + sentence),
               "a cut text is \(cut.utf8.count) bytes and ends “\(cut.suffix(70))”", &problems)
        expect(AskFacts.capped("short", keeping: sentence) == "short" + sentence, "a short text lost its sentence",
               &problems)

        let note = String(repeating: "n", count: 80)
        let hits = (0..<200).map { (day: "Tue 14 Nov", name: "Session \($0)", worked: 3_600.0, note: Optional(note)) }
        let list = AskFacts.sessions(.thisWeek, words: "session", hits: hits, sessionRunning: true)
        expect(list.utf8.count <= AskFacts.maximumBytes && list.hasSuffix("…" + sentence),
               "a cut list is \(list.utf8.count) bytes and ends “\(list.suffix(70))”", &problems)
        let lines = String(list.dropLast(sentence.count + 1)).components(separatedBy: "\n")
        expect(lines.allSatisfy { $0.hasSuffix("note: " + note) }, "the cut left a partial line", &problems)

        let days = (0..<100).map { (label: "Day \($0)", focused: 60.0) }
        let totals = AskFacts.focusTotals(.thisWeek, words: "session", focused: 24_000, sessions: 5, focusedDays: 4,
                                          best: (unit: "day", label: "Tue 14 Nov", focused: 7_500),
                                          parts: (name: "day", items: days), sessionRunning: true)
        expect(totals.utf8.count <= AskFacts.maximumBytes && totals.hasSuffix("…" + sentence),
               "a cut total is \(totals.utf8.count) bytes and ends “\(totals.suffix(70))”", &problems)
        return problems
    }
}
