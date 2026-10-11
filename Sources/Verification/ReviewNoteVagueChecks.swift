import Foundation

/// The audit fails closed. A review of the typed audit found that an amount
/// written without a number passed unchecked: with a 45m session in the facts,
/// "an hour", "half an hour", "a couple of hours", "an hour and a half", "one
/// and a half hours" and "a quarter of an hour" all passed, though the
/// audit's whole bar is that no figure is invented, and "an hour" is the
/// likeliest way for the model to invent one. A weekday beside a date was not
/// compared either: "Tuesday 7 October" passed against Wednesday 7 October.
/// Facts are written by hand in the builder's wording.
enum ReviewNoteVagueChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("An amount written without a number fails the note, though the facts hold a duration it could mean",
         numberlessAmounts),
        ("A wording the facts use themselves, such as a session named Office hours, still passes", wordingInTheFacts),
        ("A weekday written beside a date must be that date's weekday in the facts", weekdayMatchesDate),
    ]

    private static func note(_ story: String, tip: String? = nil) -> WrittenNote {
        WrittenNote(story: story, pattern: "Nothing else.", tip: tip)
    }

    private static let day = NoteFacts(
        kind: .day,
        lines: ["Day: Wednesday 7 October 2026", "Focus: 2h 15m over 2 sessions",
                "Sessions in order: Parser at 9:13 am, 45m; Thesis at 2:00 pm, 1h 30m"],
        observations: ["Longest stretch: 1h 30m in Thesis, from 2:00 pm"])

    private static func numberlessAmounts() -> [String] {
        var problems: [String] = []
        let numberless = [
            "You worked for an hour.", "You worked for half an hour.", "You worked for a couple of hours.",
            "You worked for an hour and a half.", "You worked for one and a half hours.",
            "You worked for a quarter of an hour.", "You spent hours on Thesis.", "Parser took a few minutes.",
            "Parser took a minute.", "You came back to Thesis twice.", "You had a couple of sessions.",
            "You worked for the second half of the day.", "Thesis ran for an hour, which the facts call 1h 30m.",
        ]
        for text in numberless {
            expect(!NoteAudit.passes(note(text), facts: day), "“\(text)” passed, but states an amount with no number", &problems)
        }
        expect(!NoteAudit.passes(note("Fine.", tip: "Start with an hour of Thesis."), facts: day),
               "an amount with no number in the tip alone should fail the note", &problems)
        // The same amounts with their numbers are the audit's ordinary business.
        for text in ["You worked for 45m on Parser.", "Parser took 45 minutes, then Thesis 1 hour 30 minutes.",
                     "Thesis was your longest stretch at 1h 30m."] {
            expect(NoteAudit.passes(note(text), facts: day), "“\(text)” failed on \(NoteAudit.unmatched(note(text), facts: day))", &problems)
        }
        return problems
    }

    private static func wordingInTheFacts() -> [String] {
        var problems: [String] = []
        let facts = NoteFacts(
            kind: .day,
            lines: ["Day: Wednesday 7 October 2026", "Focus: 1h 45m over 3 sessions",
                    "Sessions in order: Office hours at 9:00 am, 45m; Minute taking at 10:00 am, 30m; "
                    + "Half marathon plan at 11:00 am, 30m"],
            observations: ["Longest stretch: 45m in Office hours, from 9:00 am"])
        let quoting = "You spent 45m on Office hours, then 30m on Minute taking and 30m on Half marathon plan."
        expect(NoteAudit.passes(note(quoting), facts: facts),
               "quoted names failed on \(NoteAudit.unmatched(note(quoting), facts: facts))", &problems)
        // The names do not excuse an amount of the note's own.
        for text in ["You spent an hour on Office hours.", "You spent half an hour on Minute taking.",
                     "You spent hours on Half marathon plan."] {
            expect(!NoteAudit.passes(note(text), facts: facts), "“\(text)” passed", &problems)
        }
        return problems
    }

    private static func weekdayMatchesDate() -> [String] {
        var problems: [String] = []
        let week = NoteFacts(
            kind: .period,
            lines: ["Week of Monday 5 October 2026", "Focus: 9h over 4 sessions on 3 days",
                    "Most time went to: Thesis: 6h; Parser: 3h"],
            observations: ["Best day: Wednesday 7 October 2026 with 5h", "Longest stretch: 3h in Thesis, on Tuesday 6 October 2026 from 9:00 am"])
        let passing = [
            "Your best day was Wednesday 7 October 2026 with 5h.", "Your best day was Wednesday 7 October with 5h.",
            "Your best day was Wed 7 Oct with 5h.", "Your best day was Wednesday, 7th October with 5h.",
            "Your best day was 7 October with 5h.", "Your best day was Wednesday the 7th of October with 5h.",
            "The longest stretch was on Tuesday 6 October.", "The longest stretch was on Tue 6 October 2026.",
        ]
        for text in passing {
            expect(NoteAudit.passes(note(text), facts: week), "“\(text)” failed on \(NoteAudit.unmatched(note(text), facts: week).map { $0.map(\.description) })", &problems)
        }
        let wrong = [
            "Your best day was Tuesday 7 October with 5h.", "Your best day was Tue 7 Oct with 5h.",
            "Your best day was Thursday, 7th October with 5h.", "The longest stretch was on Monday 6 October.",
            "The longest stretch was on Wednesday 6 October 2026.", "Your best day was Tuesday 8 October with 5h.",
        ]
        for text in wrong {
            expect(!NoteAudit.passes(note(text), facts: week), "“\(text)” passed with a wrong weekday or date", &problems)
        }
        let readings = ReviewNoteWordChecks.readings
        expect(readings("Tuesday, 7th October 2026") == ["date 1007 tuesday", "year 2026"],
               "a weekday beside a date: \(readings("Tuesday, 7th October 2026"))", &problems)
        expect(readings("Tuesday 7 October") != readings("Wednesday 7 October"), "two weekdays read as one date", &problems)
        return problems
    }
}
