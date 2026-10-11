import Foundation

/// Where each Ask lookup's figures come from: the places in History a lookup
/// returns beside its text, in the order the text reaches them. The text
/// itself is held by the other Ask suites, which pass untouched.
enum AskLookupLinkChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Focus totals list the period, its best day and the longest session", totalsThisWeek),
        ("All-time totals list History itself, then the best day, week, month and longest session", totalsAllTime),
        ("One day's totals list that day alone", totalsOneDay),
        ("Totals matching words list the period and the longest matching session", totalsMatchingWords),
        ("A comparison lists both periods", compareBothPeriods),
        ("A session search lists the period and each session found", findSessionsListsSessions),
        ("A widened search keeps the period asked about and lists the sessions found elsewhere",
         widenedSearchKeepsAskedPeriod),
        ("Best hours and app time list the period they read", bestHoursAndAppTimeNameTheirPeriod),
        ("A period still to come has no sources", refusalsHaveNoSources),
        ("A session that crosses midnight is listed under the first day of the range it has work in",
         sessionDayIsFirstDayInRange),
        ("A lookup's text is the same whether or not its sources are asked for", textUnchanged),
    ]

    private typealias Fixture = AskLookupChecks.Fixture
    private static let dot = "\u{00B7}"
    private static let dash = "\u{2013}"

    // MARK: - Expected places, built from the fixture's calendar

    /// Midnight at the start of the day, in 2023.
    private static func date(_ f: Fixture, _ month: Int, _ day: Int) -> Date {
        f.calendar.date(from: DateComponents(year: 2023, month: month, day: day))!
    }

    private static func dayLink(_ f: Fixture, _ month: Int, _ day: Int, _ label: String, _ role: AskSourceRole) -> AskLink {
        AskLink(target: .day(date(f, month, day)), label: label, role: role)
    }

    /// A week, month or year row, from its first day to the first day after it.
    private static func periodLink(_ f: Fixture, _ level: HistoryLevel, from start: (Int, Int), to end: (Int, Int),
                                   _ label: String, _ role: AskSourceRole) -> AskLink {
        let span = DateInterval(start: date(f, start.0, start.1), end: date(f, end.0, end.1))
        return AskLink(target: .period(HistoryPlace(level: level, span: span)), label: label, role: role)
    }

    private static func week13to19(_ f: Fixture, _ role: AskSourceRole) -> AskLink {
        periodLink(f, .week, from: (11, 13), to: (11, 20), "13 Nov \(dash) 19 Nov", role)
    }

    private static func history(_ label: String, _ role: AskSourceRole) -> AskLink {
        AskLink(target: .history, label: label, role: role)
    }

    /// A fixture session on its day, under the thread the archive gave it.
    private static func sessionLink(_ f: Fixture, _ name: String, on day: Date, _ dayLabel: String,
                                    _ role: AskSourceRole, thread: UUID? = nil) -> AskLink {
        let found = thread ?? f.engine.archive.records
            .first { $0.name == name && f.calendar.startOfDay(for: $0.start) == day }?.threadID
        return AskLink(target: .session(thread: found ?? UUID(), day: day), label: "\(name) \(dot) \(dayLabel)",
                       role: role, sessionName: name)
    }

    private static func expectLinks(_ request: AskRequest, _ f: Fixture, _ want: [AskLink], _ problems: inout [String]) {
        let got = f.store.askLookupResult(request).links
        expect(got == want, "\(request.provenance) lists \(got), not \(want)", &problems)
    }

    // MARK: - Checks

    private static func totalsThisWeek() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            expectLinks(.focusTotals(.thisWeek, words: nil), f, [
                week13to19(f, .totals),
                dayLink(f, 11, 14, "Tue 14 Nov", .bestDay),
                sessionLink(f, "Parser", on: date(f, 11, 14), "Tue 14 Nov", .longestSession),
            ], &problems)
        }
    }

    private static func totalsAllTime() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            // The best week and month are History's own rows, which end at today
            // while the week and month are not over: the text says 13 Nov – 15 Nov.
            expectLinks(.focusTotals(.allTime, words: nil), f, [
                history("All time", .totals),
                dayLink(f, 10, 17, "Tue 17 Oct", .bestDay),
                periodLink(f, .week, from: (11, 13), to: (11, 16), "13 Nov \(dash) 15 Nov", .bestWeek),
                periodLink(f, .month, from: (11, 1), to: (11, 16), "November 2023", .bestMonth),
                sessionLink(f, "Thesis", on: date(f, 10, 17), "Tue 17 Oct", .longestSession),
            ], &problems)
        }
    }

    private static func totalsOneDay() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            // One session that day, so the text names no longest session either.
            expectLinks(.focusTotals(.day(year: 2023, month: 11, day: 13), words: nil), f,
                        [dayLink(f, 11, 13, "Mon 13 Nov", .totals)], &problems)
        }
    }

    private static func totalsMatchingWords() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            expectLinks(.focusTotals(.allTime, words: "thesis"), f, [
                history("All time", .totals),
                sessionLink(f, "Thesis", on: date(f, 10, 17), "Tue 17 Oct", .longestSession),
            ], &problems)
        }
    }

    private static func compareBothPeriods() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            expectLinks(.compare(.thisWeek, with: .day(year: 2023, month: 10, day: 17), words: nil), f, [
                week13to19(f, .compared),
                dayLink(f, 10, 17, "Tue 17 Oct", .compared),
            ], &problems)
        }
    }

    private static func findSessionsListsSessions() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            expectLinks(.findSessions(words: "thesis", .allTime), f, [
                history("All time", .totals),
                sessionLink(f, "Thesis", on: date(f, 11, 13), "Mon 13 Nov", .session),
                sessionLink(f, "Thesis", on: date(f, 10, 17), "Tue 17 Oct", .session),
            ], &problems)
        }
    }

    private static func widenedSearchKeepsAskedPeriod() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            // Nothing today mentions "outline"; the 13 Nov Thesis note does.
            let result = f.store.askLookupResult(.findSessions(words: "outline", .today))
            expect(result.text.contains("Mon 13 Nov"), "the widened search says “\(result.text)”", &problems)
            expectLinks(.findSessions(words: "outline", .today), f, [
                dayLink(f, 11, 15, "Wed 15 Nov", .totals),
                sessionLink(f, "Thesis", on: date(f, 11, 13), "Mon 13 Nov", .session),
            ], &problems)
        }
    }

    private static func bestHoursAndAppTimeNameTheirPeriod() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            // The last 30 days is no row of History's: its source is History, with the dates.
            expectLinks(.bestHours(.last30Days), f,
                        [history("Last 30 days (17 Oct \(dash) 15 Nov)", .bestHours)], &problems)
            expectLinks(.bestHours(.today), f, [dayLink(f, 11, 15, "Wed 15 Nov", .bestHours)], &problems)
            expectLinks(.appTime(.thisWeek, app: "Safari"), f, [week13to19(f, .appTime)], &problems)
            expectLinks(.appTime(.thisWeek, app: nil), f, [week13to19(f, .appTime)], &problems)
            expectLinks(.appTime(.thisMonth, app: "Safari"), f,
                        [periodLink(f, .month, from: (11, 1), to: (12, 1), "November 2023", .appTime)], &problems)
        }
    }

    private static func refusalsHaveNoSources() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            let later = AskRange.day(year: 2023, month: 11, day: 16)
            let requests: [AskRequest] = [
                .focusTotals(later, words: nil), .focusTotals(later, words: "thesis"), .bestHours(later),
                .findSessions(words: "thesis", later), .appTime(later, app: "Safari"),
                .compare(later, with: .thisWeek, words: nil), .compare(.thisWeek, with: .year(2024), words: nil),
            ]
            for request in requests {
                let result = f.store.askLookupResult(request)
                expect(result.links.isEmpty, "\(request.provenance) lists \(result.links) for “\(result.text)”",
                       &problems)
            }
        }
    }

    /// "Thesis" saved from 23:00 yesterday to 01:00 today: an hour on each day.
    private static func sessionDayIsFirstDayInRange() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            let today = f.calendar.startOfDay(for: f.clock.value)
            let yesterday = f.calendar.date(byAdding: .day, value: -1, to: today)!
            let overnight = SessionRecord(
                name: "Thesis", workType: .deepWork,
                start: f.calendar.date(bySettingHour: 23, minute: 0, second: 0, of: yesterday)!,
                end: f.calendar.date(bySettingHour: 1, minute: 0, second: 0, of: today)!, workSeconds: 7_200)
            guard f.engine.archive.append(overnight) == nil else {
                problems.append("could not save the overnight session")
                return
            }
            let thread = overnight.threadID
            // It began yesterday, but today it has work from midnight on.
            expectLinks(.findSessions(words: "thesis", .today), f, [
                dayLink(f, 11, 15, "Wed 15 Nov", .totals),
                sessionLink(f, "Thesis", on: today, "Wed 15 Nov", .session, thread: thread),
            ], &problems)
            expectLinks(.findSessions(words: "thesis", .yesterday), f, [
                dayLink(f, 11, 14, "Tue 14 Nov", .totals),
                sessionLink(f, "Thesis", on: yesterday, "Tue 14 Nov", .session, thread: thread),
            ], &problems)
            // Over the week it is one session, named by its first day in the range.
            expectLinks(.focusTotals(.thisWeek, words: "thesis"), f, [
                week13to19(f, .totals),
                sessionLink(f, "Thesis", on: yesterday, "Tue 14 Nov", .longestSession, thread: thread),
            ], &problems)
        }
    }

    private static func textUnchanged() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            let later = AskRange.day(year: 2023, month: 11, day: 16)
            let requests: [AskRequest] = [
                .focusTotals(.thisWeek, words: nil), .focusTotals(.allTime, words: nil),
                .focusTotals(.day(year: 2023, month: 11, day: 13), words: nil), .focusTotals(.allTime, words: "thesis"),
                .compare(.thisWeek, with: .day(year: 2023, month: 10, day: 17), words: nil),
                .findSessions(words: "thesis", .allTime), .findSessions(words: "outline", .today),
                .bestHours(.last30Days), .appTime(.thisWeek, app: "Safari"), .focusTotals(later, words: nil),
            ]
            for request in requests {
                let result = f.store.askLookupResult(request).text
                let text = f.store.askLookup(request)
                expect(result == text, "\(request.provenance): the result says “\(result)”, askLookup “\(text)”",
                       &problems)
            }
        }
    }
}
