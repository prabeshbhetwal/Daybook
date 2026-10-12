import Foundation
import FoundationModels

/// Ask Daybook v2 part 2: what happened between sessions. The `dayEvents`
/// lookup lists breaks, answers about time away (and absences not answered
/// yet) and what the Mac did, worded from the readers the day story draws
/// from, and says where the Mac's event log begins. Mon 13 Nov in the shared
/// fixture holds all three kinds; Tue 14 holds the Mac's crash.
enum AskDayEventsChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("One day lists breaks, answers and the Mac's rows in time order", oneDayInOrder),
        ("Items that start together keep the order breaks, answers, Mac", tiesKeepOrder),
        ("A crash is told with when it was found", crashFound),
        ("A longer period is one line a day, newest first", longerPeriodLines),
        ("The event log's first day is said", logFirstDay),
        ("With no event log, nothing is said about the Mac", noEventLog),
        ("An absence not yet answered says so", pendingAbsence),
        ("Nothing to tell says so", nothingToTell),
        ("A day that yields nothing is not counted in \u{201C}Newest N of M days.\u{201D}", emptyCandidateDay),
        ("A long history stays within 1 KB and counts every day", longHistory),
        ("What happened lists the period and each day it names", linksListPeriodAndDays),
        ("The catalogue's sixth entry is dayEvents, with part 1's period guide", catalogueEntry),
    ]

    private static let monday = AskRange.day(year: 2023, month: 11, day: 13)
    private static let dot = "\u{00B7}"

    // MARK: - Items

    private static func oneDayInOrder() -> [String] {
        AskDataFixture.with { f, problems in
            let text = f.store.askLookup(.dayEvents(monday))
            expect(text.hasPrefix("Mon 13 Nov:\n"), "Mon 13 Nov starts “\(text.prefix(20))”", &problems)
            let rows = f.store.macAccount(on: f.moment(2, 12))?.rows ?? []
            guard let lock = rows.first(where: { $0.span.start == f.moment(2, 12, 25) }),
                  let sleep = rows.first(where: { $0.span.start == f.moment(2, 23, 48) })
            else { problems.append("Mon 13 Nov's Mac rows are \(rows.map(\.title))"); return }
            let lines = [
                "from 10:40am to 11:05am \(dot) away \(dot) answered: Counted as focus, 25m \(dot) no reason recorded",
                "from 12:25pm to 1:10pm \(dot) break “Lunch” \(dot) 45m",
                "\(lock.title) from 12:25pm to 1:10pm",
                "from 3:40pm to 3:55pm \(dot) break \(dot) 15m",
                "from 4:10pm to 4:30pm \(dot) away \(dot) answered: Recorded as a break \(dot) named “Coffee”",
                "\(sleep.title) from 11:48pm until midnight",
            ]
            expectInOrder(text, lines, &problems)
            expect(text.contains("Mac asleep from 11:48pm until midnight") && text.contains("Mac locked from 12:25pm to 1:10pm"),
                   "the Mac rows do not lead with their title: \(text)", &problems)
            for row in rows { expect(text.contains(row.title), "the Mac row “\(row.title)” is missing: \(text)", &problems) }
        }
    }

    private static func tiesKeepOrder() -> [String] {
        AskDataFixture.with { f, problems in
            leaveAndReturn(f)
            guard let away = f.engine.pendingAwayRange else { problems.append("no absence is waiting for an answer"); return }
            // A break that begins in the same instant as the absence.
            let walk = SessionRecord(name: "Walk", workType: .breakTime, start: away.start,
                                     end: away.start.addingTimeInterval(600), workSeconds: 600)
            if f.engine.archive.append(walk) != nil { problems.append("could not save the break"); return }
            let text = f.store.askLookup(.dayEvents(.today))
            let lines = text.split(separator: "\n").map(String.init)
            let first = lines.firstIndex { $0.contains("break “Walk” \(dot) 10m") }
            let second = lines.firstIndex { $0.contains("away, not answered yet") }
            expect(first != nil && second != nil && first! < second!, "the order is \(lines)", &problems)
        }
    }

    private static func crashFound() -> [String] {
        AskDataFixture.with { f, problems in
            let tuesday = AskRange.day(year: 2023, month: 11, day: 14)
            // The fixture's crash has no launch after it yet: some time in its window, found at no time.
            let before = f.store.askLookup(.dayEvents(tuesday))
            expect(before.contains("from 8:00am to 8:02am \(dot) Daybook crashed \(dot) some time in this window\n"),
                   "a crash not yet found says: \(before)", &problems)
            // The launch that found it, at 8:02am.
            guard f.machineEvents.append([MachineEvent(kind: .daybookStarted, at: f.moment(1, 8, 2))]) else {
                problems.append("could not log the launch"); return
            }
            let rows = f.store.macAccount(on: f.moment(1, 12))?.rows ?? []
            guard let crash = rows.first(where: { $0.foundAt == f.moment(1, 8, 2) }) else {
                problems.append("no Mac row on Tue 14 Nov was found at 8:02am: \(rows.map(\.title))"); return
            }
            let text = f.store.askLookup(.dayEvents(tuesday))
            let line = "from 8:00am to 8:02am \(dot) \(crash.title) \(dot) some time in this window; "
                + "found when Daybook opened at 8:02am"
            expect(text.contains(line), "Tue 14 Nov does not tell “\(line)”: \(text)", &problems)
        }
    }

    private static func emptyCandidateDay() -> [String] {
        AskDataFixture.with { f, problems in
            // A break with no length leaves no break on the day, though the archive holds it.
            let blip = SessionRecord(name: "Blip", workType: .breakTime, start: f.moment(4, 10), end: f.moment(4, 10),
                                     workSeconds: 0)
            if f.engine.archive.append(blip) != nil { problems.append("could not save the break"); return }
            let text = f.store.askLookup(.dayEvents(.allTime))
            expect(text.contains("Mon 13 Nov") && text.contains("Tue 14 Nov") && !text.contains("Sat 11 Nov"),
                   "all time lists: \(text)", &problems)
            expect(!text.contains("Newest"), "a list that was not cut says it was: \(text)", &problems)
        }
    }

    private static func pendingAbsence() -> [String] {
        AskDataFixture.with { f, problems in
            leaveAndReturn(f)
            let text = f.store.askLookup(.dayEvents(.today))
            expect(text.contains("from 9:23am to 9:45am \(dot) away, not answered yet"),
                   "an unanswered absence says: \(text)", &problems)
            let week = f.store.askLookup(.dayEvents(.thisWeek))
            expect(week.contains("Wed 15 Nov \(dot) 1 absence not answered yet"), "this week says: \(week)", &problems)
        }
    }

    /// A session begun now, left for 22 minutes ten minutes in, and not yet
    /// answered: the absence is 9:23am to 9:45am on Wed 15 Nov.
    private static func leaveAndReturn(_ f: AskDataFixture) {
        f.engine.start(workType: .deepWork, intent: "Writing")
        f.clock.advance(600)
        f.engine.transition(on: .awayBegan(trigger: .screenLock))
        f.clock.advance(22 * 60)
        f.engine.transition(on: .awayEnded)
        f.store.catchUpWithEngine()
    }

    // MARK: - Periods

    private static func longerPeriodLines() -> [String] {
        AskDataFixture.with { f, problems in
            let text = f.store.askLookup(.dayEvents(.thisWeek))
            let summary = f.store.macAccount(on: f.moment(2, 12))?.summary ?? "none"
            let mondayLine = "Mon 13 Nov \(dot) 2 breaks, 1h \(dot) 2 answers about time away \(dot) \(summary)"
            expectInOrder(text, ["Tue 14 Nov \(dot) ", mondayLine], &problems)
            expect(!text.contains("Newest"), "a week that fits says it is cut: \(text)", &problems)
        }
    }

    private static func logFirstDay() -> [String] {
        AskDataFixture.with { f, problems in
            let week = f.store.askLookup(.dayEvents(.lastWeek))
            expect(week.contains("The Mac's events are recorded from Sun 12 Nov."), "last week says: \(week)", &problems)
            let before = f.store.askLookup(.dayEvents(.day(year: 2023, month: 10, day: 5)))
            expect(before.contains("No Mac events were recorded before Sun 12 Nov."), "5 Oct says: \(before)", &problems)
            let inside = f.store.askLookup(.dayEvents(monday))
            expect(!inside.contains("recorded from") && !inside.contains("recorded before"),
                   "a day inside the log carries its caveat: \(inside)", &problems)
        }
    }

    private static func noEventLog() -> [String] {
        AskDataFixture.with { f, problems in
            f.store.machineEventLog = nil
            let text = f.store.askLookup(.dayEvents(monday))
            expect(!text.contains("Mac"), "without a log the text speaks of the Mac: \(text)", &problems)
            expect(text.contains("break “Lunch” \(dot) 45m") && text.contains("answered: Counted as focus"),
                   "breaks and answers are not listed: \(text)", &problems)
        }
    }

    private static func nothingToTell() -> [String] {
        AskDataFixture.with { f, problems in
            let text = f.store.askLookup(.dayEvents(.today))
            // Today is inside the log, so what the log did not record is said too.
            expect(text == "No breaks, time away or Mac events recorded today. No restart or shut down was recorded. "
                   + "No crash was recorded.", "an empty day says “\(text)”", &problems)
        }
    }

    private static func longHistory() -> [String] {
        AskDataFixture.with(extraBreakDays: 1_000) { f, problems in
            let text = f.store.askLookup(.dayEvents(.allTime))
            expect(text.utf8.count <= 1_024, "the text is \(text.utf8.count) bytes", &problems)
            // The days of the fixture itself with anything to tell, from the readers: the extra
            // days begin 40 days back.
            let own = (0..<40).filter { back in
                let day = f.moment(back, 12)
                let projection = f.store.storyDayProjection(on: day, calendar: f.calendar)
                let rests = projection.sessions.contains { if case .rest = $0 { return true } else { return false } }
                let answers = projection.chronology.contains {
                    switch $0 {
                    case .decision, .pending: return true
                    default: return false
                    }
                }
                return rests || answers || f.store.macAccount(on: day) != nil
            }.count
            guard let tail = text.split(separator: "\n").last,
                  let match = tail.wholeMatch(of: #/Newest (\d+) of (\d+) days\./#),
                  let shown = Int(match.1), let total = Int(match.2) else {
                problems.append("the text does not end with its count: \(text.suffix(60))"); return
            }
            let lines = text.split(separator: "\n").filter { $0.contains(" \(dot) ") }.count
            expect(shown == lines && shown < total, "it says \(shown) of \(total) days with \(lines) lines", &problems)
            expect(total == 1_000 + own, "it counts \(total) days, not \(1_000 + own)", &problems)
            expect(text.contains("The Mac's events are recorded from Sun 12 Nov."), "no log note: \(text.suffix(120))", &problems)
        }
    }

    // MARK: - Sources and catalogue

    private static func linksListPeriodAndDays() -> [String] {
        AskDataFixture.with { f, problems in
            func day(_ back: Int, _ label: String) -> AskLink {
                AskLink(target: .day(f.calendar.startOfDay(for: f.moment(back, 12))), label: label, role: .whatHappened)
            }
            let week = HistoryPlace(level: .week, span: DateInterval(start: f.moment(2, 0), end: f.moment(-5, 0)))
            let weekLink = AskLink(target: .period(week), label: "13 Nov \u{2013} 19 Nov", role: .whatHappened)
            let got = f.store.askLookupResult(.dayEvents(.thisWeek)).links
            expect(got == [weekLink, day(1, "Tue 14 Nov"), day(2, "Mon 13 Nov")], "this week lists \(got)", &problems)
            // A day asked about is its own anchor, not listed twice.
            let one = f.store.askLookupResult(.dayEvents(monday)).links
            expect(one == [day(2, "Mon 13 Nov")], "Mon 13 Nov lists \(one)", &problems)
            let future = f.store.askLookupResult(.dayEvents(.day(year: 2023, month: 11, day: 20)))
            expect(future.links.isEmpty && future.text.hasSuffix("is still to come."), "a later day says: \(future.text)", &problems)
            expect(AskRequest.dayEvents(.thisWeek).provenance == "what happened (this week)", "provenance differs", &problems)
        }
    }

    private static func catalogueEntry() -> [String] {
        guard #available(macOS 26, *) else { return [] }
        var problems: [String] = []
        let description = "Lists what happened between sessions in a period: breaks, time away from the Mac with "
            + "what the user said they were doing and whether it counted as focus, and what the Mac did, such as "
            + "sleep, lock, restart or a crash, with their times."
        let guide = AskLookups.all[0].spec.parameters[0].description
        let want = AskLookupSpec(name: "dayEvents", description: description,
                                 parameters: [AskParameter(name: "range", description: guide, required: true)])
        expect(AskLookups.all.count >= 6 && AskLookups.all[5].spec == want,
               "the sixth entry is \(String(describing: AskLookups.all.dropFirst(5).first?.spec))", &problems)
        expect(AskLookups.named("dayEvents")?.spec == want, "named(dayEvents) is not that entry", &problems)
        if let entry = AskLookups.named("dayEvents") {
            guard let schema = try? AskOnDeviceTool.schema(for: entry.spec),
                  let expected = try? AskOnDeviceTool.schema(for: want) else {
                problems.append("the schema could not be built"); return problems
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let got = (try? encoder.encode(schema)).flatMap { String(data: $0, encoding: .utf8) }
            let wanted = (try? encoder.encode(expected)).flatMap { String(data: $0, encoding: .utf8) }
            expect(got != nil && got == wanted, "the schema is \(got ?? "unencodable"), not \(wanted ?? "?")", &problems)
            let call = entry.read(["range": "yesterday"]) { AskRange(rawValue: $0) }
            expect(call == .request(.dayEvents(.yesterday)), "yesterday reads as \(call)", &problems)
            let refused = entry.read(["range": "31 february"]) { AskRange(rawValue: $0) }
            expect(refused == .refusal(AskFacts.noSuchPeriod("31 february")), "a bad date reads as \(refused)", &problems)
        }
        return problems
    }

    // MARK: - Helpers

    /// Each line appears in the text, after the one before it.
    private static func expectInOrder(_ text: String, _ lines: [String], _ problems: inout [String]) {
        var from = text.startIndex
        for line in lines {
            guard let found = text.range(of: line, range: from..<text.endIndex) else {
                problems.append("“\(line)” is missing, or out of order, in: \(text)")
                return
            }
            from = found.upperBound
        }
    }
}
