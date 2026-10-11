import Foundation

/// What a day's facts say about its focus. A paused session's span is longer
/// than the work in it, so "Longest stretch" must come from the work, as the
/// Story's does (the span read "Longest stretch: 2h" of a session with 1h of
/// work, more than the day's focus). A session left unnamed is the kind's name
/// everywhere, as the Story titles it. A tip may build on any observation but
/// a drop in focus from the day before, which the probe found it scolding for.
/// Uses the Ask fixture: Parser on Tue 14 Nov 2:00 to 3:30 pm after Thesis on
/// Mon 13 Nov 9 to 10 am, the clock on Wed 15 Nov at 9:13.
enum ReviewNoteStretchChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A pause inside a session is not focus: the longest stretch is the work and matches the Story's", pausedStretch),
        ("A session left unnamed is called by its kind in the facts, as the Story calls it", unnamedSession),
        ("A tip may build on every observation except a drop in focus from the day before", tipObservations),
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
            expect(saturday.observations.first == "Longest stretch: 1h in Lexer, from 9:00 am",
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
            expect(!title.isEmpty && saturday.lines.contains("Sessions in order: \(title) at 9:00 am, 30m"),
                   "an unnamed session is listed as “\(saturday.lines)”", &problems)
            expect(saturday.observations.first == "Longest stretch: 30m in \(title), from 9:00 am"
                   && saturday.observations.contains("Focus began at 9:00 am with \(title)"),
                   "an unnamed session is named as “\(saturday.observations)”", &problems)
        }
    }

    private static func tipObservations() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            // Tuesday has 30m more focus than Monday: usable, like every other observation.
            guard let tuesday = facts(f, back: 1) else { problems.append("Tuesday has no facts"); return }
            expect(tuesday.observations.contains("30m more focus than the day before"),
                   "Tuesday's observations are \(tuesday.observations)", &problems)
            expect(tuesday.tipObservations == Set(tuesday.observations),
                   "Tuesday's tip may build on \(tuesday.tipObservations) of \(tuesday.observations)", &problems)
            expect(tuesday.text.contains("- 30m more focus than the day before" + NoteFacts.tipMark),
                   "the rise is not marked usable: \(tuesday.text)", &problems)

            // Wednesday so far has 30m against Tuesday's 1h 30m.
            let early = SessionRecord(name: "Early", workType: .deepWork, start: moment(f, back: 0, 8),
                                      end: moment(f, back: 0, 8, 30), workSeconds: 1_800)
            guard f.engine.archive.append(early) == nil else { problems.append("the session was not saved"); return }
            guard let wednesday = facts(f, back: 0) else { problems.append("Wednesday has no facts"); return }
            let drop = "1h less focus than the day before"
            expect(wednesday.observations.contains(drop), "Wednesday's observations are \(wednesday.observations)", &problems)
            expect(wednesday.tipObservations == Set(wednesday.observations).subtracting([drop]),
                   "Wednesday's tip may build on \(wednesday.tipObservations)", &problems)
            expect(wednesday.text.hasSuffix("- " + drop) && wednesday.text.components(separatedBy: NoteFacts.tipMark).count == 3,
                   "the drop should be the one bullet with no mark: \(wednesday.text)", &problems)
        }
    }
}
