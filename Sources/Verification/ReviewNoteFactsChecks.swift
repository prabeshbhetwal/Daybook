import Foundation

/// Guards the plain-text facts a review note is written from, and the audit
/// that drops a note stating a figure those facts do not hold. Fixture dates
/// come from `SelfTest.base` and a Gregorian calendar in the Mac's own zone,
/// so the clock times read the same wherever the checks run.
enum ReviewNoteFactsChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A day's note facts name where the time went and weigh the day against a typical one", dayFactsOrder),
        ("A day with ten sessions names its three busiest, and a difference under a minute is left out", dayFactsCap),
        ("A day's facts count sessions as History does, not by the rows the Story lists", dayFactsSessionCount),
        ("A day without sessions has no note facts, even with breaks and app use", dayWithoutSessions),
        ("A period's note facts carry History's figures and its best day", periodFacts),
        ("The figures line says focus, goal and sessions, the goal's counted time when missed", figuresLine),
        ("The audit passes a note whose figures are all in the facts", auditPasses),
        ("The audit drops a note with a figure the facts do not hold", auditFails),
        ("Digits in a session name are facts, so they pass the audit", auditNameDigits),
    ]

    private static let calendar = SelfTest.gregorian

    /// `hour:minute` on the base day (or `day`).
    private static func at(_ hour: Int, _ minute: Int, on day: Date = SelfTest.base) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private static func session(_ name: String, spans: [DateInterval], worked: TimeInterval) -> DaySession {
        DaySession(id: UUID(), threadID: UUID(), name: name, workType: .deepWork,
                   start: spans[0].start, end: spans[spans.count - 1].end, worked: worked,
                   stretches: spans.count, spans: spans, isRunning: false)
    }

    private static func app(_ name: String, _ total: TimeInterval, share: Double) -> AppRank {
        AppRank(bundleID: "test." + name.lowercased(), appName: name, total: total, share: share, longest: total)
    }

    /// `count` is the sessions as History counts them; one row per session when nil. The longest
    /// stretch is the longest span, as for sessions that were never paused.
    private static func dayInput(_ sessions: [DaySession], count: Int? = nil, apps: [AppRank] = [],
                                 isCurrent: Bool = false, goal: TimeInterval = 0, goalCredit: TimeInterval = 0,
                                 typical: TimeInterval = 0, typicalStretch: TimeInterval = 0, typicalDays: Int = 14,
                                 parts: [NoteDayPart: TimeInterval] = [:]) -> NoteDayInput {
        let longest = sessions.flatMap { session in
            session.spans.map { NoteStretch(name: session.name, start: $0.start, worked: $0.duration) }
        }.max { $0.worked < $1.worked }
        return NoteDayInput(date: SelfTest.base, isCurrent: isCurrent, sessions: sessions,
                            sessionCount: count ?? sessions.count, apps: apps,
                            focused: sessions.reduce(0) { $0 + $1.worked }, goal: goal, goalCredit: goalCredit,
                            typicalFocused: typical, typicalStretch: typicalStretch, typicalDays: typicalDays,
                            longestStretch: longest, focusByPart: parts)
    }

    /// Parser 9:13 to 10:13 and 10:30 to 11:00 (1h 30m), Thesis 2:00 to 2:45 pm (45m).
    /// Handed over latest first, so the order in the facts is the facts' own.
    private static func parserAndThesis() -> NoteFacts {
        let parser = session("Parser",
                             spans: [DateInterval(start: SelfTest.base, end: SelfTest.base.addingTimeInterval(3_600)),
                                     DateInterval(start: at(10, 30), end: at(11, 0))], worked: 5_400)
        let thesis = session("Thesis", spans: [DateInterval(start: at(14, 0), end: at(14, 45))], worked: 2_700)
        let apps = [app("Xcode", 3_600, share: 0.45), app("Safari", 1_800, share: 0.22), app("Idle", 0, share: 0)]
        let input = dayInput([thesis, parser], apps: apps, goal: 7_200, goalCredit: 8_100, typical: 7_200,
                             typicalStretch: 3_600, parts: [.morning: 5_400, .afternoon: 2_700])
        return NoteFacts.day(input, calendar: calendar)!
    }

    private static func dayFactsOrder() -> [String] {
        var problems: [String] = []
        let facts = parserAndThesis()
        expect(facts.kind == .day, "a day's facts have kind day, got \(facts.kind)", &problems)
        expect(facts.lines == ["Day: Wednesday 15 November 2023", "Focus: 2h 15m over 2 sessions",
                               "Daily goal: 2h; counted towards it: 2h 15m of focus with hands-on app use; met: yes",
                               "Most time went to: Parser: 1h 30m; Thesis: 45m", "Top apps: Xcode 1h, Safari 30m"],
               "lines wrong (top apps stop at the first with no time): \(facts.lines)", &problems)
        expect(facts.observations == ["15m more focus than your typical day of 2h (the median of 14 days with focus in your last 14)",
                                      "The most focus came in the morning, between 5 am and noon: 1h 30m",
                                      "Focus ran as 3 stretches averaging 45m; your typical stretch is 1h",
                                      "Longest stretch: 1h in Parser, from 9:13 am"],
               "observations are not the four rules in order: \(facts.observations)", &problems)
        expect(facts.text == facts.lines.joined(separator: "\n") + "\nObservations:\n- "
               + facts.observations.joined(separator: "\n- "),
               "text is not lines, then Observations:, then bullets: \(facts.text)", &problems)
        return problems
    }

    private static func dayFactsCap() -> [String] {
        var problems: [String] = []
        // Job A is 5m, B 10m, … J 50m, one an hour from 8 am: A and B are the two shortest.
        let jobs = "ABCDEFGHIJ".enumerated().map { index, letter -> DaySession in
            let start = at(8 + index, 0)
            return session("Job \(letter)",
                           spans: [DateInterval(start: start, end: start.addingTimeInterval(TimeInterval(300 * (index + 1))))],
                           worked: TimeInterval(300 * (index + 1)))
        }
        let input = dayInput(jobs.reversed(), isCurrent: true, goal: 10_800, goalCredit: 1_000, typical: 20_000)
        guard let facts = NoteFacts.day(input, calendar: calendar) else { return ["a day with ten sessions produced no facts"] }
        expect(facts.lines.contains("Most time went to: Job J: 50m; Job I: 45m; Job H: 40m"),
               "the three busiest are not named, busiest first: \(facts.lines)", &problems)
        expect(facts.lines.first == "Day: Wednesday 15 November 2023 (so far)",
               "a current day should say so: \(facts.lines)", &problems)
        expect(facts.lines.contains("Focus: 4h 35m over 10 sessions"),
               "focus line wrong: \(facts.lines)", &problems)
        expect(facts.lines.contains("Daily goal: 3h; counted towards it: 16m of focus with hands-on app use; met: no"),
               "a missed goal should say no: \(facts.lines)", &problems)
        expect(facts.observations.first == "58m less focus than your typical day of 5h 33m "
               + "(the median of 14 days with focus in your last 14)",
               "the drop from the typical day is missing: \(facts.observations)", &problems)
        expect(!facts.observations.contains { $0.hasPrefix("The most focus came") },
               "no focus by part of the day should mean no line for it: \(facts.observations)", &problems)
        // A difference under a minute is no observation.
        let flat = NoteFacts.day(dayInput(jobs, typical: 16_500 + 30), calendar: calendar)!
        expect(!flat.observations.contains { $0.contains("typical day") },
               "a difference under a minute should be left out: \(flat.observations)", &problems)
        return problems
    }

    /// Parser, Mail, then Parser again on its own thread: three rows, two sessions.
    private static func dayFactsSessionCount() -> [String] {
        var problems: [String] = []
        let rows = [session("Parser", spans: [DateInterval(start: at(9, 0), end: at(10, 0))], worked: 3_600),
                    session("Mail", spans: [DateInterval(start: at(10, 0), end: at(10, 30))], worked: 1_800),
                    session("Parser", spans: [DateInterval(start: at(11, 0), end: at(11, 30))], worked: 1_800)]
        guard let counted = NoteFacts.day(dayInput(rows, count: 2), calendar: calendar),
              let listed = NoteFacts.day(dayInput(rows), calendar: calendar) else { return ["a day with sessions produced no facts"] }
        expect(counted.lines.contains("Focus: 2h over 2 sessions"), "two sessions over three rows say \(counted.lines)", &problems)
        expect(counted.observations.contains("Focus ran as 3 stretches averaging 40m"),
               "two sessions over three stretches say \(counted.observations)", &problems)
        expect(counted.lines.contains("Most time went to: Parser: 1h 30m; Mail: 30m"),
               "the two Parser rows are not one name's time: \(counted.lines)", &problems)
        expect(listed.lines.contains("Focus: 2h over 3 sessions"), "three sessions say \(listed.lines)", &problems)
        // A single stretch has nothing to say about stretches.
        let single = NoteFacts.day(dayInput([rows[0]]), calendar: calendar)
        expect(single?.observations.contains { $0.hasPrefix("Focus ran as") } == false,
               "one stretch says \(single?.observations ?? [])", &problems)
        return problems
    }

    private static func dayWithoutSessions() -> [String] {
        var problems: [String] = []
        let input = NoteDayInput(date: SelfTest.base, isCurrent: false, sessions: [], sessionCount: 0,
                                 apps: [app("Xcode", 3_600, share: 1)], focused: 3_600, goal: 7_200,
                                 goalCredit: 3_600, typicalFocused: 1_800, typicalStretch: 1_800, typicalDays: 5,
                                 longestStretch: nil, focusByPart: [.morning: 3_600])
        expect(NoteFacts.day(input, calendar: calendar) == nil, "a day with no sessions should have no facts", &problems)
        return problems
    }

    private static func periodFacts() -> [String] {
        var problems: [String] = []
        let monday = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: SelfTest.base))!
        let tuesday = calendar.date(byAdding: .day, value: 1, to: monday)!
        let nextMonday = calendar.date(byAdding: .day, value: 7, to: monday)!
        let best = HistoryPlace(level: .day, span: DateInterval(start: tuesday, end: nextMonday))
        let summary = HistorySummary(focused: 9_000, tracked: 10_000, focusedDays: 2, sessions: 2,
                                     best: (place: best, focused: 5_400))
        let input = NotePeriodInput(span: DateInterval(start: monday, end: nextMonday), level: .week, isCurrent: false,
                                    summary: summary, sessionTotals: [("Parser", 6_000), ("Thesis", 3_000)],
                                    goal: 7_200, goalMetDays: 1, previousFocused: 5_400)
        guard let facts = NoteFacts.period(input, calendar: calendar) else { return ["a week with sessions produced no facts"] }
        expect(facts.kind == .period, "a period's facts have kind period, got \(facts.kind)", &problems)
        expect(facts.lines.first == "Week of Monday 13 November 2023", "week line wrong: \(facts.lines)", &problems)
        expect(facts.lines.contains("Focus: 2h 30m over 2 sessions on 2 days"), "focus line wrong: \(facts.lines)", &problems)
        expect(facts.lines.contains("Most time went to: Parser: 1h 40m; Thesis: 50m"),
               "session totals line wrong: \(facts.lines)", &problems)
        expect(facts.observations == ["Best day: Tuesday 14 November 2023 with 1h 30m",
                                      "1h more focus than the week before",
                                      "Goal met on 1 of 2 days with focus",
                                      "Parser took 1h 40m of the week"],
               "observations are not the four rules in order: \(facts.observations)", &problems)

        let month = NotePeriodInput(span: input.span, level: .month, isCurrent: true, summary: summary,
                                    sessionTotals: [], goal: 0, goalMetDays: 0, previousFocused: 0)
        let monthFacts = NoteFacts.period(month, calendar: calendar)
        expect(monthFacts?.lines.first == "Month: November 2023 (so far)",
               "month line wrong: \(monthFacts?.lines ?? [])", &problems)
        expect(monthFacts?.lines.contains { $0.hasPrefix("Most time went to") } == false,
               "no session totals should mean no totals line", &problems)

        let empty = HistorySummary(focused: 0, tracked: 0, focusedDays: 0, sessions: 0, best: nil)
        let quiet = NotePeriodInput(span: input.span, level: .week, isCurrent: false, summary: empty,
                                    sessionTotals: [], goal: 0, goalMetDays: 0, previousFocused: 0)
        expect(NoteFacts.period(quiet, calendar: calendar) == nil, "a period with no sessions should have no facts", &problems)
        return problems
    }

    private static func figuresLine() -> [String] {
        var problems: [String] = []
        let met = NoteFacts.figuresLine(focused: 15_000, sessions: 3, goal: 14_400, goalCredit: 14_400)
        expect(met == "4h 10m focus · goal met · 3 sessions", "met line wrong: \(met)", &problems)
        let missed = NoteFacts.figuresLine(focused: 5_400, sessions: 2, goal: 7_200, goalCredit: 5_400)
        expect(missed == "1h 30m focus · 1h 30m towards 2h goal · 2 sessions", "missed line wrong: \(missed)", &problems)
        // More focus than the goal, missed: the goal counts only focus with hands-on use.
        let short = NoteFacts.figuresLine(focused: 20_400, sessions: 4, goal: 14_400, goalCredit: 14_340)
        expect(short == "5h 40m focus · 3h 59m towards 4h goal · 4 sessions", "short line wrong: \(short)", &problems)
        let none = NoteFacts.figuresLine(focused: 3_600, sessions: 1, goal: 0, goalCredit: 0)
        expect(none == "1h focus · 1 session", "no-goal line wrong: \(none)", &problems)
        return problems
    }

    private static func note(story: String = "A steady day.", pattern: String = "Mornings were strongest.") -> WrittenNote {
        WrittenNote(story: story, pattern: pattern)
    }

    private static func auditPasses() -> [String] {
        var problems: [String] = []
        let facts = parserAndThesis()
        expect(NoteAudit.passes(note(story: "Parser from 9:13 am for 1h 30m"), facts: facts),
               "a note quoting only figures in the facts should pass", &problems)
        expect(NoteAudit.passes(note(story: "No figures at all"), facts: facts),
               "a note with no digits should pass", &problems)
        expect(NoteAudit.passes(note(pattern: "Start at 09:13 again, 1h 30m was fine."), facts: facts),
               "a leading zero and a repeated figure should pass", &problems)
        expect(NoteFigure.read("09:13 am") == NoteFigure.read("9:13 am") && !NoteFigure.read("9:13 am").isEmpty,
               "a leading zero changed a time: \(NoteFigure.read("09:13 am"))", &problems)
        expect(NoteFigure.read("none").isEmpty, "text without digits has no figures", &problems)
        return problems
    }

    private static func auditFails() -> [String] {
        var problems: [String] = []
        let facts = parserAndThesis()
        expect(!NoteAudit.passes(note(pattern: "Your longest stretch was 2h 10m"), facts: facts),
               "a note with 10, which the facts do not hold, should fail", &problems)
        expect(NoteAudit.passes(note(pattern: "Your longest stretch was 2h 15m"), facts: facts),
               "the same note with a figure the facts hold should pass", &problems)
        expect(!NoteAudit.passes(note(story: "Try 25 minutes tomorrow"), facts: facts),
               "a figure in the story alone should fail the note", &problems)
        return problems
    }

    private static func auditNameDigits() -> [String] {
        var problems: [String] = []
        func facts(named name: String) -> NoteFacts {
            let work = session(name, spans: [DateInterval(start: SelfTest.base, end: SelfTest.base.addingTimeInterval(1_800))],
                               worked: 1_800)
            return NoteFacts.day(dayInput([work]), calendar: calendar)!
        }
        let quoting = note(story: "You spent your morning on Q4 plan v2.")
        expect(NoteAudit.passes(quoting, facts: facts(named: "Q4 plan v2")),
               "digits in a session name are in the facts and should pass", &problems)
        expect(!NoteAudit.passes(quoting, facts: facts(named: "Plan")),
               "the same digits with no such name in the facts should fail", &problems)
        return problems
    }
}
