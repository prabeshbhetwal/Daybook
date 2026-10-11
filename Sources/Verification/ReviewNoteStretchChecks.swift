import Foundation

/// What a day's facts say about its focus. A paused session's span is longer
/// than the work in it, so "Longest stretch" must come from the work, as the
/// Story's does (the span read "Longest stretch: 2h" of a session with 1h of
/// work, more than the day's focus). A session left unnamed is the kind's name
/// everywhere, as the Story titles it. A day is weighed against the person's
/// typical day, never the day before alone.
/// Uses the Ask fixture: Parser on Tue 14 Nov 2:00 to 3:30 pm after Thesis on
/// Mon 13 Nov 9 to 10 am, the clock on Wed 15 Nov at 9:13.
enum ReviewNoteStretchChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A pause inside a session is not focus: the longest stretch is the work and matches the Story's", pausedStretch),
        ("A session left unnamed is called by its kind in the facts, as the Story calls it", unnamedSession),
        ("A day is weighed against the median of the days with focus before it, not the day before", typicalDay),
    ]

    private typealias Fixture = AskLookupChecks.Fixture

    /// A moment on the day `back` days before the clock's day.
    private static func moment(_ f: Fixture, back: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let day = f.calendar.date(byAdding: .day, value: -back, to: f.calendar.startOfDay(for: f.clock.value))!
        return f.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private static func facts(_ f: Fixture, back: Int) -> NoteFacts? {
        f.store.noteFacts(for: f.store.notePlace(forDayContaining: moment(f, back: back, 12)))
    }

    /// Lexer ran from 9:00 to 11:00 on Sat 11 Nov with the hour from 9:30 to 10:30 paused.
    private static func pausedStretch() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            let start = moment(f, back: 4, 9)
            let lexer = SessionRecord(name: "Lexer", workType: .deepWork, start: start,
                                      end: start.addingTimeInterval(7_200), workSeconds: 3_600,
                                      pausedSpans: [DateInterval(start: start.addingTimeInterval(1_800),
                                                                 end: start.addingTimeInterval(5_400))])
            guard f.engine.archive.append(lexer) == nil else { problems.append("the session was not saved"); return }
            guard let saturday = facts(f, back: 4) else { problems.append("Saturday has no facts"); return }
            expect(saturday.observations.contains("Longest stretch: 1h in Lexer, from 9:00 am"),
                   "Saturday's observations are \(saturday.observations)", &problems)
            expect(saturday.lines.contains("Focus: 1h over 1 session") && !saturday.text.contains("2h"),
                   "Saturday's facts count the pause: \(saturday.text)", &problems)
            let place = f.store.notePlace(forDayContaining: moment(f, back: 4, 12))
            expect(f.store.storyLongestFocusStretch(in: place.span)?.seconds == 3_600,
                   "the Story's longest stretch is not the facts' 1h", &problems)
        }
    }

    private static func unnamedSession() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            let start = moment(f, back: 4, 9)
            let blank = SessionRecord(name: "", workType: .deepWork, start: start,
                                      end: start.addingTimeInterval(1_800), workSeconds: 1_800)
            guard f.engine.archive.append(blank) == nil else { problems.append("the session was not saved"); return }
            guard let saturday = facts(f, back: 4) else { problems.append("Saturday has no facts"); return }
            let title = WorkType.deepWork.sessionTitle(named: "")
            expect(!title.isEmpty && saturday.lines.contains("Most time went to: \(title): 30m"),
                   "an unnamed session is listed as “\(saturday.lines)”", &problems)
            expect(saturday.observations.contains("Longest stretch: 30m in \(title), from 9:00 am"),
                   "an unnamed session is named as “\(saturday.observations)”", &problems)
        }
    }

    /// Lexer for 1h on Sat 11 and Sun 12 Nov, before the fixture's Monday and Tuesday.
    private static func typicalDay() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            for back in [4, 3] {
                let start = moment(f, back: back, 9)
                let lexer = SessionRecord(name: "Lexer", workType: .deepWork, start: start,
                                          end: start.addingTimeInterval(3_600), workSeconds: 3_600)
                guard f.engine.archive.append(lexer) == nil else { problems.append("a session was not saved"); return }
            }
            // Monday has two days with focus before it: too few for a typical day.
            guard let monday = facts(f, back: 2) else { problems.append("Monday has no facts"); return }
            expect(!monday.text.contains("typical") && !monday.text.contains("day before"),
                   "Monday is weighed against \(monday.observations)", &problems)
            // Tuesday's 1h 30m against Saturday's, Sunday's and Monday's 1h each.
            guard let tuesday = facts(f, back: 1) else { problems.append("Tuesday has no facts"); return }
            expect(tuesday.observations.first == "30m more focus than your typical day of 1h "
                   + "(the median of 3 days with focus in your last 14)",
                   "Tuesday's observations are \(tuesday.observations)", &problems)
            // Wednesday so far has 30m; the day before alone (1h 30m) is not the measure.
            let early = SessionRecord(name: "Early", workType: .deepWork, start: moment(f, back: 0, 8),
                                      end: moment(f, back: 0, 8, 30), workSeconds: 1_800)
            guard f.engine.archive.append(early) == nil else { problems.append("the session was not saved"); return }
            guard let wednesday = facts(f, back: 0) else { problems.append("Wednesday has no facts"); return }
            expect(wednesday.observations.first == "30m less focus than your typical day of 1h "
                   + "(the median of 4 days with focus in your last 14)" && !wednesday.text.contains("day before"),
                   "Wednesday's observations are \(wednesday.observations)", &problems)
        }
    }
}
