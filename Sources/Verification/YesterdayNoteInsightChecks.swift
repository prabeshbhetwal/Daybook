import Foundation

/// What a Yesterday note is written from, after one read "Keep Coding sessions
/// running past midnight" over a card saying "5h 40m focus · goal missed": the
/// day's facts weigh it against the person's own typical day, say when the
/// focus came, and leave out a session carried over from the night before,
/// which is the calendar's doing; the figures line shows what the goal counted.
/// Uses the Ask fixture (Thesis on Mon 13 Nov 9 to 10 am, Parser on Tue 14 Nov
/// 2:00 to 3:30 pm with Safari in front for 1h, the clock on Wed 15 Nov at
/// 9:13), with Lexer for 1h at 9 am on Sat 11 and Sun 12 Nov and a night
/// session from 11 pm Monday to 2 am Tuesday added.
enum YesterdayNoteInsightChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Yesterday's facts weigh it against the typical day and leave out the night before's session", carriedOverDay),
        ("Yesterday's figures line says what the goal counted when the focus outran it", countedGoal),
        ("A session still running counts in the part of the day it ran in", runningPart),
        ("A typical day needs three days with focus among the fourteen before", baselineDays),
        ("Focus by part of the day follows the part edges, a part needs 40% to be named, and breaks count nowhere",
         partsAndBreaks),
    ]

    private typealias Fixture = AskLookupChecks.Fixture

    /// A moment on the day `back` days before the fixture's Wednesday.
    private static func moment(_ f: Fixture, back: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let day = f.calendar.date(byAdding: .day, value: -back, to: f.calendar.startOfDay(for: SelfTest.base))!
        return f.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private static func withDays(_ body: (Fixture, HistoryPlace, inout [String]) -> Void) -> [String] {
        AskLookupChecks.withFixture { f, problems in
            var records = [4, 3].map { back in
                SessionRecord(name: "Lexer", workType: .deepWork, start: moment(f, back: back, 9),
                              end: moment(f, back: back, 10), workSeconds: 3_600)
            }
            records.append(SessionRecord(name: "Night build", workType: .deepWork, start: moment(f, back: 2, 23),
                                         end: moment(f, back: 1, 2), workSeconds: 3 * 3_600))
            for record in records where f.engine.archive.append(record) != nil {
                problems.append("a session was not saved")
                return
            }
            body(f, f.store.notePlace(forDayContaining: moment(f, back: 1, 12)), &problems)
        }
    }

    private static func carriedOverDay() -> [String] {
        withDays { f, tuesday, problems in
            guard let facts = f.store.noteFacts(for: tuesday) else { problems.append("Tuesday has no facts"); return }
            // Saturday, Sunday and Monday (Thesis 1h and the night's first hour) make the baseline.
            // The longest stretch is the night's, carried over, so it is left out.
            expect(facts.observations == [
                "2h 30m more focus than your typical day of 1h (the median of 3 days with focus in your last 14)",
                "The most focus came at night, after 10 pm or before 5 am: 2h",
                "Focus ran as 2 stretches averaging 1h 45m; your typical stretch is 1h",
            ], "Tuesday's observations are \(facts.observations)", &problems)
            expect(facts.lines.contains("Most time went to: Night build: 2h; Parser: 1h 30m"),
                   "Tuesday's lines are \(facts.lines)", &problems)
            for artefact in ["midnight", "carried", "12:00 am", "began", "Sessions in order", "day before"] {
                expect(!facts.text.contains(artefact), "Tuesday's facts say “\(artefact)”: \(facts.text)", &problems)
            }
        }
    }

    private static func countedGoal() -> [String] {
        withDays { f, tuesday, problems in
            // 3h 30m of focus, of which Safari was in front for 1h.
            f.engine.store.dailyGoal = 7_200
            let line = f.store.noteFiguresLine(for: tuesday)
            expect(line == "3h 30m focus · 1h towards 2h goal · 2 sessions", "the figures line says “\(line)”", &problems)
            let goal = f.store.noteFacts(for: tuesday)?.lines.first { $0.hasPrefix("Daily goal") }
            expect(goal == "Daily goal: 2h; counted towards it: 1h of focus with hands-on app use; met: no",
                   "the goal line says \(String(describing: goal))", &problems)
        }
    }

    /// Late runs from 10:30 pm on Tuesday and is still running at 12:30 am Wednesday.
    private static func runningPart() -> [String] {
        withDays { f, tuesday, problems in
            f.clock.value = moment(f, back: 1, 22, 30)
            guard f.engine.start(workType: .deepWork, intent: "Late") else { problems.append("Late did not start"); return }
            f.clock.value = moment(f, back: 0, 0, 30)
            let facts = f.store.noteFacts(for: tuesday)
            expect(facts?.observations.contains("The most focus came at night, after 10 pm or before 5 am: 3h 30m") == true,
                   "Tuesday's observations are \(facts?.observations ?? [])", &problems)
        }
    }

    private static func baselineDays() -> [String] {
        var problems: [String] = []
        let two = NoteBaseline.typical([(3_600, 1), (7_200, 2), (0, 0), (5_000, 0)])
        expect(two.focused == 0 && two.stretch == 0 && two.days == 0, "two days with focus made a baseline: \(two)", &problems)
        let three = NoteBaseline.typical([(3_600, 1), (7_200, 2), (10_800, 1), (0, 0)])
        expect(three.focused == 7_200 && three.stretch == 3_600 && three.days == 3,
               "three days made \(three), not 2h and 1h from 3 days", &problems)
        let four = NoteBaseline.typical([(3_600, 1), (7_200, 1), (10_800, 1), (14_400, 1)])
        expect(four.focused == 9_000, "four days' median is \(four.focused), not the middle two's mean 2h 30m", &problems)
        return problems
    }

    /// On Sat 11 Nov, an hour across each part edge (4:30 am, 11:30 am, 4:30 pm and 9:30 pm) and a break
    /// from 1 to 4 pm: each part holds 1h, a quarter of the focus, and the break is in none of it.
    private static func partsAndBreaks() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            var records = [(4, 30), (11, 30), (16, 30), (21, 30)].map { hour, minute in
                SessionRecord(name: "Edge", workType: .deepWork, start: moment(f, back: 4, hour, minute),
                              end: moment(f, back: 4, hour + 1, minute), workSeconds: 3_600)
            }
            records.append(SessionRecord(name: "Break", workType: .breakTime, start: moment(f, back: 4, 13),
                                         end: moment(f, back: 4, 16), workSeconds: 10_800))
            for record in records where f.engine.archive.append(record) != nil {
                problems.append("a session was not saved")
                return
            }
            let saturday = f.store.notePlace(forDayContaining: moment(f, back: 4, 12))
            let parts = f.store.noteFocusByPart(saturday.span)
            expect(parts == [.night: 3_600, .morning: 3_600, .afternoon: 3_600, .evening: 3_600],
                   "Saturday's parts are \(parts)", &problems)
            let facts = f.store.noteFacts(for: saturday)
            expect(facts?.observations.contains { $0.hasPrefix("The most focus came") } == false,
                   "a part with a quarter of the focus was named: \(facts?.observations ?? [])", &problems)
            let earlier = f.store.noteEarlierDays(before: moment(f, back: 3, 12))
            expect(earlier.first?.focused == 4 * 3_600 && earlier.first?.stretches == 4 && earlier.count == 14,
                   "Saturday in Sunday's baseline is \(String(describing: earlier.first)) of \(earlier.count) days", &problems)
        }
    }
}
