import Foundation

/// Details of what Ask's lookups say: which day its best-hours reading ran
/// to, how a long list is cut, where a breakdown starts, and what it says to
/// a search with nothing to search for.
enum AskLookupDetailChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Ask's best hours name the last day actually read", bestHoursNameTheLastDayRead),
        ("Ask says how many sessions matched when it lists only the newest ten", longListsSayHowManyMatched),
        ("Ask's breakdown starts at the first recorded day", breakdownStartsAtRecord),
        ("Ask asks for words when a session search has none", searchNeedsWords),
    ]

    private static func bestHoursNameTheLastDayRead() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            // Insights reads whole weeks: October's last week runs to Sun 5 Nov.
            let month = f.store.askLookup(.bestHours(.lastMonth))
            expect(month.hasPrefix("Over the 6 weeks to 5 Nov: most focus 9–11am"),
                   "last month's best hours say “\(month)”", &problems)
            // A week that is not over is read to today.
            let thisWeek = f.store.askLookup(.bestHours(.thisWeek))
            expect(thisWeek.hasPrefix("Over the week to 15 Nov: most focus 2–4pm"),
                   "this week's best hours say “\(thisWeek)”", &problems)
        }
    }

    private static func longListsSayHowManyMatched() -> [String] {
        AskLookupChecks.withFixture(extraThesisDays: 12) { f, problems in
            let many = f.store.askLookup(.findSessions(words: "thesis", .allTime))
            expect(many.hasSuffix(" Newest 10 of 14."), "14 matches end “\(many.suffix(40))”", &problems)
            let lines = many.components(separatedBy: "\n")
            expect(lines.count == 10, "the list has \(lines.count) lines, not 10", &problems)

            let few = f.store.askLookup(.findSessions(words: "thesis", .thisWeek))
            expect(few == "Mon 13 Nov · Thesis · 1h", "one match says “\(few)”", &problems)
        }
    }

    private static func breakdownStartsAtRecord() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            // The record begins on Tue 17 Oct, in the week of 16 Oct: the weeks
            // of October before it hold nothing to list.
            let text = f.store.askLookup(.focusTotals(.lastMonth, words: nil))
            expect(text.contains(" By week: 16 Oct – 22 Oct 2h"), "last month's breakdown reads “\(text)”", &problems)
            for week in ["1 Oct – 1 Oct", "2 Oct – 8 Oct", "9 Oct – 15 Oct"] {
                expect(!text.contains(week), "the breakdown lists \(week), before the first record: “\(text)”",
                       &problems)
            }
        }
    }

    private static func searchNeedsWords() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            for words in ["", "   ", " \n\t "] {
                let got = f.store.askLookup(.findSessions(words: words, .thisWeek))
                expect(got == "Give one or more words to search for.", "words “\(words)” say “\(got)”", &problems)
            }
        }
    }
}
