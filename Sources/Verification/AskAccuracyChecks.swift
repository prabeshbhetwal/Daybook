import Foundation

/// What Ask's lookups hand the model, so that it can answer the question
/// asked rather than a nearby one. Asked for the most focused day of the
/// year, it was handed only the best month and said "September 2026"; asked
/// about August, it could name only last month. Each check here is one of the
/// wrong answers a probe of the live model gave (2026-10-10), on the Ask
/// fixture: Wed 15 Nov 2023, sessions on Mon 13 Nov, Tue 14 Nov and Tue 17 Oct.
enum AskAccuracyChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Ask names the most focused day of any range, and its best week and month", bestDayOfAnyRange),
        ("Ask looks up a named day, month or year, and says when one is still to come", namedPeriods),
        ("Ask gives a day's first start and a range's longest session and average", startsAndLongest),
        ("Ask compares two periods by the minutes it shows", comparesPeriods),
        ("Ask's search for an app's name brings the app's own time in front", appWordsBringAppTime),
        ("A search that finds nothing in its range says what the whole record holds", emptySearchWidens),
        ("A widened search keeps its count and running note whole when cut", widenedSearchKeepsItsTail),
        ("A session running since before midnight is named in yesterday's searches", overnightSessionIsNamed),
        ("A session continued on another day is one session when Ask names the longest", continuedSessionIsOne),
        ("Ask's best hours say when a range is longer than the 14 weeks Insights reads", bestHoursSayWhenCut),
    ]

    private static func bestDayOfAnyRange() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            let all = f.store.askLookup(.focusTotals(.allTime, words: nil))
            let want = "In all your history: 4h 30m focused over 3 sessions on 3 days, "
                + "an average of 1h 30m on each day with focus; the most focused day was Tue 17 Oct, with 2h; "
                + "the most focused week so far is this week (13 Nov – 15 Nov), with 2h 30m; "
                + "the most focused month so far is this month (November 2023), with 2h 30m; "
                + "the longest finished session was Thesis on Tue 17 Oct, 2h."
            expect(all.hasPrefix(want), "all time says “\(all)”, not “\(want)…”", &problems)

            let year = f.store.askLookup(.focusTotals(.thisYear, words: nil))
            expect(year.hasPrefix("This year (2023): 4h 30m focused over 3 sessions on 3 days")
                   && year.contains("; the most focused day was Tue 17 Oct, with 2h;"),
                   "this year says “\(year)”", &problems)

            let week = f.store.askLookup(.focusTotals(.thisWeek, words: nil))
            expect(week.contains("; the most focused day was Tue 14 Nov, with 1h 30m;")
                   && !week.contains("most focused week"),
                   "a week names its best day only: “\(week)”", &problems)
        }
    }

    private static func namedPeriods() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            let october = f.store.askLookup(.focusTotals(.month(year: 2023, month: 10), words: nil))
            let last = f.store.askLookup(.focusTotals(.lastMonth, words: nil))
            expect(october.hasPrefix("In October 2023: 2h focused over 1 session on 1 day"),
                   "October 2023 says “\(october)”", &problems)
            expect(october.replacingOccurrences(of: "In October 2023", with: "Last month (October 2023)") == last,
                   "October 2023 and last month differ: “\(october)” against “\(last)”", &problems)

            let day = f.store.askLookup(.focusTotals(.day(year: 2023, month: 11, day: 13), words: nil))
            expect(day == "On Mon 13 Nov 2023: 1h focused over 1 session on 1 day; the first session began at 9:00am.",
                   "Mon 13 Nov says “\(day)”", &problems)

            let empty = f.store.askLookup(.focusTotals(.year(2022), words: nil))
            expect(empty == "No focus recorded in 2022.", "2022 says “\(empty)”", &problems)

            for (range, want) in [(AskRange.day(year: 2023, month: 11, day: 16), "Thu 16 Nov 2023 is still to come."),
                                  (.month(year: 2024, month: 1), "January 2024 is still to come.")] {
                for request in [AskRequest.focusTotals(range, words: nil), .findSessions(words: "", range),
                                .compare(.thisWeek, with: range, words: nil)] {
                    let got = f.store.askLookup(request)
                    expect(got == want, "\(request.provenance) says “\(got)”, not “\(want)”", &problems)
                }
            }
        }
    }

    private static func startsAndLongest() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            let yesterday = f.store.askLookup(.focusTotals(.yesterday, words: nil))
            expect(yesterday == "Yesterday (Tue 14 Nov): 1h 30m focused over 1 session on 1 day; the first session began at 2:00pm.",
                   "yesterday says “\(yesterday)”", &problems)
            let week = f.store.askLookup(.focusTotals(.thisWeek, words: nil))
            expect(week.hasPrefix("This week (13 Nov – 19 Nov): 2h 30m focused over 2 sessions on 2 days, "
                                  + "an average of 1h 15m on each day with focus;")
                   && week.contains("; the longest finished session was Parser on Tue 14 Nov, 1h 30m."),
                   "this week says “\(week)”", &problems)
        }
    }

    private static func comparesPeriods() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            let got = f.store.askLookup(.compare(.thisWeek, with: .month(year: 2023, month: 10), words: nil))
            let want = "Focus this week so far (13 Nov – 19 Nov): 2h 30m; in October 2023: 2h. "
                + "This week so far (13 Nov – 19 Nov) has 30m more than October 2023."
            expect(got == want, "the comparison says “\(got)”, not “\(want)”", &problems)
            let thesis = f.store.askLookup(.compare(.lastMonth, with: .thisMonth, words: "thesis"))
            expect(thesis == "Sessions matching “thesis” last month (October 2023): 2h; this month so far (November 2023): 1h. "
                   + "Last month (October 2023) has 1h more than this month so far (November 2023).",
                   "the comparison of thesis says “\(thesis)”", &problems)
        }
    }

    private static func appWordsBringAppTime() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            let got = f.store.askLookup(.focusTotals(.thisWeek, words: "safari"))
            let want = "Sessions matching “safari” this week (13 Nov – 19 Nov): 1h 30m over 1 session on 1 day. "
                + "Safari itself was in front for 1h this week."
            expect(got == want, "a search for safari says “\(got)”, not “\(want)”", &problems)
            let thesis = f.store.askLookup(.focusTotals(.thisWeek, words: "thesis"))
            expect(!thesis.contains("itself"), "a word that names no app brought an app: “\(thesis)”", &problems)
        }
    }

    private static func emptySearchWidens() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            let got = f.store.askLookup(.findSessions(words: "thesis", .lastWeek))
            let want = "No sessions match “thesis” last week. In all your history:\n"
                + "Mon 13 Nov · 9:00am · Thesis · 1h\nTue 17 Oct · 9:00am · Thesis · 2h"
            expect(got == want, "a search with nothing last week says “\(got)”, not “\(want)”", &problems)
            let nowhere = f.store.askLookup(.findSessions(words: "zebra", .lastWeek))
            expect(nowhere == "No sessions match “zebra” last week.", "a word found nowhere says “\(nowhere)”",
                   &problems)
            let listing = f.store.askLookup(.findSessions(words: "", .lastWeek))
            expect(listing == "No sessions recorded last week.", "an empty week's list says “\(listing)”", &problems)
        }
    }

    /// Cut as two texts, the widened list lost "Newest 10 of 37." and the
    /// running note whenever its notes ran long: the model then called ten
    /// sessions all there were.
    private static func widenedSearchKeepsItsTail() -> [String] {
        var problems: [String] = []
        for length in [30, 40, 55, 70, 80] {
            let lines = (0..<10).map {
                AskSessionLine(day: "Tue 14 Nov", time: "9:00am", name: "Thesis \($0)", worked: 3_600,
                               note: String(repeating: "n", count: length))
            }
            let text = AskFacts.sessionsElsewhere(.today, words: "thesis", lines: lines, matched: 37, sessionRunning: true)
            let tail = " Newest 10 of 37." + AskFacts.runningNote
            expect(text.utf8.count <= AskFacts.maximumBytes && text.hasSuffix(tail)
                   && text.hasPrefix("No sessions match “thesis” today. In all your history:\nTue 14 Nov · 9:00am · Thesis 0"),
                   "with \(length)-character notes the widened list reads “…\(text.suffix(80))”", &problems)
        }
        return problems
    }

    /// Begun at 11pm on Tuesday and still going at 12:30am on Wednesday:
    /// yesterday holds some of it, so its searches say they cannot see it.
    private static func overnightSessionIsNamed() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            let today = f.calendar.startOfDay(for: f.clock.value)
            f.clock.value = today.addingTimeInterval(-3_600)
            f.engine.start(workType: .deepWork, intent: "Night")
            f.clock.value = today.addingTimeInterval(1_800)
            let list = f.store.askLookup(.findSessions(words: "", .yesterday))
            expect(list == "Tue 14 Nov · 2:00pm · Parser · 1h 30m" + AskFacts.runningNote,
                   "yesterday's list says “\(list)”", &problems)
            let words = f.store.askLookup(.focusTotals(.yesterday, words: "parser"))
            expect(words.hasSuffix(AskFacts.runningNote), "yesterday's word totals say “\(words)”", &problems)
            let lastWeek = f.store.askLookup(.findSessions(words: "", .lastWeek))
            expect(lastWeek == "No sessions recorded last week.", "last week's list says “\(lastWeek)”", &problems)
        }
    }

    /// Thesis on Monday continued for an hour on Wednesday is two hours of
    /// one session, longer than Parser's 1h 30m. Listed a day at a time, it
    /// lost to Parser (Codex review, PR #30).
    private static func continuedSessionIsOne() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            let today = f.calendar.startOfDay(for: f.clock.value)
            guard let monday = f.engine.archive.records.first(where: {
                $0.name == "Thesis" && $0.start >= today.addingTimeInterval(-3 * 86_400)
            }) else { return problems.append("the fixture has no Thesis this week") }
            let more = SessionRecord(name: "Thesis", workType: .deepWork, start: today.addingTimeInterval(8 * 3_600),
                                     end: today.addingTimeInterval(9 * 3_600), workSeconds: 3_600,
                                     threadID: monday.threadID)
            _ = f.engine.archive.append(more)
            let week = f.store.askLookup(.focusTotals(.thisWeek, words: nil))
            expect(week.contains("; the longest finished session was Thesis on Mon 13 Nov, 2h."),
                   "this week's longest reads “\(week)”", &problems)
        }
    }

    /// "When do I focus best?" reads all time, and Insights reads 14 weeks
    /// at most: an answer over a longer record must not pass for the whole.
    private static func bestHoursSayWhenCut() -> [String] {
        var problems = AskLookupChecks.withFixture(extraThesisDays: 120) { f, problems in
            let long = f.store.askLookup(.bestHours(.allTime))
            expect(long.hasPrefix("Over the latest 14 weeks to 15 Nov, as far back as Insights reads: most focus"),
                   "a record of 23 weeks says “\(long)”", &problems)
        }
        problems += AskLookupChecks.withFixture { f, problems in
            let short = f.store.askLookup(.bestHours(.allTime))
            expect(short.hasPrefix("Over the 5 weeks to 15 Nov: most focus"), "a record of 5 weeks says “\(short)”",
                   &problems)
        }
        return problems
    }
}
