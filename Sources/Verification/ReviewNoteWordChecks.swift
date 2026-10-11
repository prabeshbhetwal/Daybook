import Foundation

/// What the live note probe found the model doing: spelling figures out
/// ("five hours and forty-six minutes", "two thousand twenty-six"), which a
/// digits-only audit let through unread; and a session name's comma or trailing
/// number running into the figures in a week's most-time list.
enum ReviewNoteWordChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The audit reads numbers a note spells out as the digits they stand for", wordFigures),
        ("A spelled-out figure the facts lack drops the note; one they hold, or a session name's, passes", wordsInTheAudit),
        ("A week's most-time list keeps a name with a comma or a trailing number as one item", periodListSeparators),
    ]

    private static func wordFigures() -> [String] {
        var problems: [String] = []
        let cases: [(String, Set<String>)] = [
            ("forty-six minutes", ["46"]),
            ("five hours and forty-six minutes", ["5", "46"]),
            ("two thousand twenty-six", ["2026"]),
            ("two thousand five hundred", ["2500"]),
            ("sixty-eight hours", ["68"]),
            ("Fifteen September", ["15"]),
            ("ten hours thirty minutes", ["10", "30"]),
            ("five thirty", ["5", "30"]),
            ("twenty-one days and twenty one more", ["21"]),
            ("one hundred", ["100"]),
            ("a stretch of nine", ["9"]),
            ("zero sessions", ["0"]),
            ("Forty-Six", ["46"]),
            // A lone "one" is a pronoun too; ordinals, "half" and a word that merely holds a number are not read.
            ("no one was there, one hour", []),
            ("the second tenth, a half, a stone", []),
            ("none here", []),
        ]
        for (text, want) in cases {
            let got = NoteAudit.wordRuns(in: text)
            expect(got == want, "“\(text)” reads as \(got.sorted()), not \(want.sorted())", &problems)
        }
        expect(NoteAudit.figures(in: "at 9:13 for forty-six minutes") == ["9", "13", "46"],
               "digits and words together: \(NoteAudit.figures(in: "at 9:13 for forty-six minutes").sorted())", &problems)
        return problems
    }

    private static func note(_ story: String, tip: String? = nil) -> WrittenNote {
        WrittenNote(story: story, pattern: "Nothing else.", tip: tip)
    }

    private static func wordsInTheAudit() -> [String] {
        var problems: [String] = []
        let facts = NoteFacts(kind: .day, lines: ["Focus: 1h 30m over 2 sessions",
                                                  "Sessions in order: Seven habits at 9:00 am, 1h"],
                              observations: [])
        expect(NoteAudit.passes(note("You focused for one hour and thirty minutes over two sessions."), facts: facts),
               "figures in words that the facts hold should pass", &problems)
        expect(!NoteAudit.passes(note("You worked for forty-six minutes."), facts: facts),
               "a spelled-out 46, which the facts lack, should fail", &problems)
        expect(!NoteAudit.passes(note("Fine.", tip: "Try five hours tomorrow."), facts: facts),
               "a spelled-out figure in the tip alone should fail the note", &problems)
        expect(NoteAudit.passes(note("You read Seven habits at 9:00 am."), facts: facts),
               "a number word in a session name is in the facts and should pass", &problems)
        let plain = NoteFacts(kind: .day, lines: ["Focus: 1h 30m over 2 sessions"], observations: [])
        expect(!NoteAudit.passes(note("You read Seven habits."), facts: plain),
               "the same word with no such name in the facts should fail", &problems)
        return problems
    }

    private static func periodListSeparators() -> [String] {
        var problems: [String] = []
        let calendar = SelfTest.gregorian
        let monday = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: SelfTest.base))!
        let nextMonday = calendar.date(byAdding: .day, value: 7, to: monday)!
        let summary = HistorySummary(focused: 9_000, tracked: 10_000, focusedDays: 2, sessions: 2, best: nil)
        let input = NotePeriodInput(span: DateInterval(start: monday, end: nextMonday), level: .week, isCurrent: false,
                                    summary: summary,
                                    sessionTotals: [("Budget, then notes", 6_000), ("Release 1.3", 3_000)],
                                    goal: 0, goalMetDays: 0, previousFocused: 0)
        let lines = NoteFacts.period(input, calendar: calendar)?.lines ?? []
        expect(lines.contains("Most time went to: Budget, then notes: 1h 40m; Release 1.3: 50m"),
               "the most-time list reads \(lines)", &problems)
        return problems
    }
}
