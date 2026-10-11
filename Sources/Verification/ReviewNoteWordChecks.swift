import Foundation

/// What the live note probe found the model doing: spelling figures out
/// ("five hours and forty-six minutes", "two thousand twenty-six"), which a
/// digits-only audit let through unread; and a session name's comma or trailing
/// number running into the figures in a week's most-time list. The figures
/// themselves are typed (`ReviewNoteFigureChecks`).
enum ReviewNoteWordChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The audit reads numbers a note spells out as the figures they stand for", wordFigures),
        ("A spelled-out figure the facts lack drops the note; one they hold, or a session name's, passes", wordsInTheAudit),
        ("A week's most-time list keeps a name with a comma or a trailing number as one item", periodListSeparators),
    ]

    /// Each mention as `kind value`, a time that reads two ways joined by " or ".
    static func readings(_ text: String) -> [String] {
        NoteFigure.read(text).map { $0.map(\.description).sorted().joined(separator: " or ") }
    }

    private static func wordFigures() -> [String] {
        var problems: [String] = []
        let cases: [(String, [String])] = [
            ("forty-six minutes", ["duration 2760"]),
            ("five hours and forty-six minutes", ["duration 20760"]),
            ("two thousand twenty-six", ["year 2026"]),
            ("two thousand five hundred", ["bare 2500"]),
            ("sixty-eight hours", ["duration 244800"]),
            ("Fifteen September", ["date 915"]),
            ("ten hours thirty minutes", ["duration 37800"]),
            ("five thirty", ["bare 5", "bare 30"]),
            ("twenty-one days and twenty one more", ["count 21 day", "bare 21"]),
            ("one hundred", ["bare 100"]),
            ("a stretch of nine", ["bare 9"]),
            ("zero sessions", ["count 0 session"]),
            ("Forty-Six", ["bare 46"]),
            // A lone "one" is a pronoun too; it is a number before a unit or a thing counted. Ordinals and a word
            // that merely holds a number are not read.
            ("no one was there, one hour", ["duration 3600"]),
            ("one of them, one's own", []),
            ("the second tenth, a stone", []),
            ("none here", []),
        ]
        for (text, want) in cases {
            let got = readings(text)
            expect(got == want, "“\(text)” reads as \(got), not \(want)", &problems)
        }
        expect(readings("at 9:13 am for forty-six minutes") == ["clock 553", "duration 2760"],
               "a time and a spelled duration together: \(readings("at 9:13 am for forty-six minutes"))", &problems)
        return problems
    }

    private static func note(_ story: String, pattern: String = "Nothing else.") -> WrittenNote {
        WrittenNote(story: story, pattern: pattern)
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
        expect(!NoteAudit.passes(note("Fine.", pattern: "Try five hours tomorrow."), facts: facts),
               "a spelled-out figure in the pattern alone should fail the note", &problems)
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
