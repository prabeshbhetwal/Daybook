import Foundation

/// The audit weighs a note's figures by what they measure and how much, not by
/// their digits. The digits-only audit let "9h" through because a 9:13 start
/// holds a 9, and the live probe's week note totalled "seventeen hours
/// forty-one minutes" out of a session count and a duration that were both in
/// its facts. Plain-text facts are written by hand here, in the builder's own
/// wording, so each failure is the audit's alone.
enum ReviewNoteFigureChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A figure the facts lack fails the note even when its digits are elsewhere in them", digitsAreNotFigures),
        ("A note quoting the facts' durations, times, dates and counts passes, in digits or in words", factsInOtherWords),
        ("A duration reads as one value however it is written, and separate durations are not summed", durationReading),
        ("A bare number must be a bare number in the facts, so a session name's digits pass only when quoted", bareNumbers),
        ("The live probe's invented week total fails and its digit-named day passes", probeNotes),
    ]

    private static let day = NoteFacts(
        kind: .day,
        lines: ["Day: Wednesday 15 November 2023", "Focus: 2h 15m over 2 sessions",
                "Sessions in order: Parser at 9:13 am, 1h 30m; Thesis at 2:00 pm, 45m"],
        observations: ["Longest stretch: 1h 30m in Parser, from 9:13 am", "2 sessions ran as 3 stretches"])

    private static func note(_ story: String, tip: String? = nil) -> WrittenNote {
        WrittenNote(story: story, pattern: "Nothing else.", tip: tip)
    }

    private static func digitsAreNotFigures() -> [String] {
        var problems: [String] = []
        // Each states a figure the facts do not hold; every digit in it is somewhere in them.
        let invented = [
            "You got 9h of focus.", "You worked 13 minutes.", "You had 9 sessions.", "You wrote 15 sessions.",
            "Focus began at 9:15 am.", "Focus began at 9:13 pm.", "Focus began at 9 am.", "Thesis was at 2:13 pm.",
            "That was on 13 November.", "That was 40% of the day.", "You focused on 2 days.",
            "You worked for seventeen hours forty-one minutes.", "Two sessions ran as 5 stretches.",
            "A 3h stretch.", "A 1h 15m stretch.", "That was 23 November 2013.",
        ]
        for text in invented {
            expect(!NoteAudit.passes(note(text), facts: day), "“\(text)” passed, but its figures are not in the facts", &problems)
        }
        expect(!NoteAudit.passes(note("Fine.", tip: "Start at 9h tomorrow."), facts: day),
               "an invented duration in the tip alone should fail the note", &problems)
        return problems
    }

    private static func factsInOtherWords() -> [String] {
        var problems: [String] = []
        let passing = [
            "Parser at 9:13 am for 1h 30m, then Thesis at 2:00 pm for 45m: 2h 15m over 2 sessions in 3 stretches.",
            "Parser at 9:13am for 1 hour 30 minutes, then Thesis at 2 pm for 45 minutes.",
            "Parser for one hour and thirty minutes, then Thesis for forty-five minutes: two hours fifteen minutes in all.",
            "Parser for 90 minutes, or 1.5 hours; Thesis for 45 min. Start at 09:13 again.",
            "On 15 November 2023, in two sessions and three stretches, the longest was a 1h 30m stretch from 9:13 am.",
            "On Wednesday 15th November there were two sessions; fifteen November was long.",
            "The longest stretch was a 1-hour 30-minute one in Parser.",
        ]
        for text in passing {
            let unmatched = NoteAudit.unmatched(note(text), facts: day)
            expect(unmatched.isEmpty, "“\(text)” failed on \(unmatched.map { $0.map(\.description).sorted() })", &problems)
        }
        return problems
    }

    private static func durationReading() -> [String] {
        var problems: [String] = []
        let readings = ReviewNoteWordChecks.readings
        for text in ["1h 30m", "1 hour 30 minutes", "1 hour and 30 minutes", "1 hour, 30 minutes", "1h30m", "90 minutes",
                     "1.5 hours", "ninety minutes", "one hour thirty minutes", "1-hour 30-minute"] {
            expect(readings(text) == ["duration 5400"], "“\(text)” reads as \(readings(text)), not 1h 30m", &problems)
        }
        expect(readings("1h 30m 15s") == ["duration 5415"], "hours, minutes and seconds: \(readings("1h 30m 15s"))", &problems)
        // Durations the facts list apart stay apart: a sum is a figure the facts do not hold.
        expect(readings("Xcode 1h, Safari 30m") == ["duration 3600", "duration 1800"],
               "two named durations: \(readings("Xcode 1h, Safari 30m"))", &problems)
        expect(readings("Thesis at 2:00 pm, 45m; Mail at 4:00 pm, 15m") == ["clock 840", "duration 2700", "clock 960", "duration 900"],
               "times and durations in a list: \(readings("Thesis at 2:00 pm, 45m; Mail at 4:00 pm, 15m"))", &problems)
        expect(readings("30m, then 1h") == ["duration 1800", "duration 3600"],
               "a longer unit after a shorter is not part of it: \(readings("30m, then 1h"))", &problems)
        expect(readings("09:13 and 21:13") == ["clock 1273 or clock 553", "clock 1273"],
               "a time without am or pm reads both ways: \(readings("09:13 and 21:13"))", &problems)
        expect(readings("Wednesday 15 November 2023") == ["date 1115", "year 2023"],
               "a date reads as a date and a year: \(readings("Wednesday 15 November 2023"))", &problems)
        expect(readings("3 of 7 days, 40 percent, 2 stretches") == ["bare 3", "count 7 day", "percent 40", "count 2 stretch"],
               "counts and percentages: \(readings("3 of 7 days, 40 percent, 2 stretches"))", &problems)
        return problems
    }

    private static func bareNumbers() -> [String] {
        var problems: [String] = []
        let readings = ReviewNoteWordChecks.readings
        expect(readings("Q4 plan v2, Sprint 42 review, Release 1.3") == ["bare 4", "bare 2", "bare 42", "bare 1.3"],
               "digits in names: \(readings("Q4 plan v2, Sprint 42 review, Release 1.3"))", &problems)
        func facts(named name: String) -> NoteFacts {
            NoteFacts(kind: .day, lines: ["Day: Wednesday 15 November 2023", "Focus: 30m over 1 session",
                                          "Sessions in order: \(name) at 9:13 am, 30m"],
                      observations: ["Focus began at 9:13 am with \(name)"])
        }
        for name in ["Q4 plan v2", "Sprint 42 review", "Release 1.3", "2026 tax return"] {
            expect(NoteAudit.passes(note("You spent your morning on \(name)."), facts: facts(named: name)),
                   "“\(name)” quoted from the facts failed", &problems)
            expect(!NoteAudit.passes(note("You spent your morning on \(name)."), facts: facts(named: "Plan")),
                   "“\(name)” passed with no such name in the facts", &problems)
        }
        // A bare number is not a count or a duration the facts happen to hold.
        expect(!NoteAudit.passes(note("You spent your morning on Plan 30."), facts: facts(named: "Plan")),
               "a bare 30 passed because the facts hold 30m", &problems)
        expect(!NoteAudit.passes(note("You spent your morning on Plan 2024."), facts: facts(named: "Plan")),
               "a year the facts lack passed", &problems)
        return problems
    }

    /// Wording from the 2026-10-11 live run, against the facts the app now writes for the same periods.
    private static func probeNotes() -> [String] {
        var problems: [String] = []
        let week = NoteFacts(
            kind: .period,
            lines: ["Week of Monday 28 September 2026", "Focus: 23h 41m over 17 sessions on 7 days",
                    "Most time went to: Thesis: 11h; Parser: 6h 36m; Email: 2h; "
                    + "Reviewing the quarterly budget proposal with Priya, then sending notes: 1h 35m; Reading: 1h 30m"],
            observations: ["Best day: Monday 28 September 2026 with 5h 18m", "Goal met on 3 of 7 days with focus"])
        let total = "You worked on thesis for eleven hours, then parser for six hours thirty-six minutes, then email for "
            + "two hours, and then other sessions for seventeen hours forty-one minutes over seven days."
        let spelled = "You worked on thesis for eleven hours, then parser for six hours thirty-six minutes, then email for "
            + "two hours over seven days."
        expect(!NoteAudit.passes(note(total), facts: week), "the week's invented total passed", &problems)
        expect(NoteAudit.passes(note(spelled), facts: week), "the same week without the total failed", &problems)

        let digits = NoteFacts(
            kind: .day,
            lines: ["Day: Wednesday 7 October 2026", "Focus: 4h 30m over 3 sessions", "Daily goal: 4h, met: yes",
                    "Sessions in order: Q4 plan v2 at 9:00 am, 1h 30m; Sprint 42 review at 11:00 am, 1h; "
                    + "2026 tax return at 2:00 pm, 2h",
                    "Top apps: Numbers 3h 30m, Safari 1h"],
            observations: ["Longest stretch: 2h in 2026 tax return, from 2:00 pm", "Focus began at 9:00 am with Q4 plan v2"])
        let story = "You worked on Q4 plan v2 for 1 hour 30 minutes at 9:00 am, then Sprint 42 review for 1 hour at "
            + "11:00 am, and finally 2026 tax return for 2 hours at 2:00 pm."
        let pattern = "The 2-hour stretch in 2026 tax return at 2:00 pm was the longest focus period of the day."
        expect(NoteAudit.passes(WrittenNote(story: story, pattern: pattern, tip: nil), facts: digits),
               "the digit-named day's note failed on \(NoteAudit.unmatched(WrittenNote(story: story, pattern: pattern, tip: nil), facts: digits))",
               &problems)
        return problems
    }
}
