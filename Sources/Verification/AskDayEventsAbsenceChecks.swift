import Foundation

/// Ask Daybook v2 part 2, after the live probe: the `dayEvents` text leads a
/// Mac row with its title and words a day's own edges ("until midnight",
/// "from midnight"), and says what the Mac's log did not record, because the
/// on-device model read silence as a yes. The shared fixture's log holds a
/// lock, a sleep across Mon 13 to Tue 14 Nov and a crash on Tue 14 Nov; it
/// holds no restart or shut down.
enum AskDayEventsAbsenceChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A day's own edges read midnight, for the Mac, breaks and answers alike", dayEdgesReadMidnight),
        ("What the log did not record is said, restart and crash apart", absencesSaid),
        ("A restart or a crash in the period is not denied", recordedEventsNotDenied),
        ("Before the log, or with no log, nothing is denied", noAbsencesWithoutLog),
        ("The absences stay whole beside the log note and the day count", absencesKeptWhole),
    ]

    private static let monday = AskRange.day(year: 2023, month: 11, day: 13)
    private static let tuesday = AskRange.day(year: 2023, month: 11, day: 14)
    private static let noRestart = "No restart or shut down was recorded."
    private static let noCrash = "No crash was recorded."

    private static func dayEdgesReadMidnight() -> [String] {
        AskDataFixture.with { f, problems in
            let rows = f.store.macAccount(on: f.moment(1, 12))?.rows ?? []
            guard let sleep = rows.first(where: { $0.span.start == f.calendar.startOfDay(for: f.moment(1, 12)) }) else {
                problems.append("Tue 14 Nov's Mac rows are \(rows.map(\.title)) at \(rows.map(\.span))"); return
            }
            let text = f.store.askLookup(.dayEvents(tuesday))
            expect(text.contains("\(sleep.title) from midnight to 7:52am"), "the sleep does not begin at midnight: \(text)", &problems)
            // A break across midnight is cut at it, and its sides say so.
            let late = SessionRecord(name: "Late", workType: .breakTime, start: f.moment(1, 23), end: f.moment(0, 1),
                                     workSeconds: 7_200)
            guard f.engine.archive.append(late) == nil else { problems.append("the break was not saved"); return }
            let before = f.store.askLookup(.dayEvents(tuesday))
            expect(before.contains("from 11:00pm until midnight \u{00B7} break \u{201C}Late\u{201D}"),
                   "Tue 14 Nov's break does not end at midnight: \(before)", &problems)
            let after = f.store.askLookup(.dayEvents(.today))
            expect(after.contains("from midnight to 1:00am \u{00B7} break \u{201C}Late\u{201D}"),
                   "Wed 15 Nov's break does not begin at midnight: \(after)", &problems)
        }
    }

    private static func absencesSaid() -> [String] {
        AskDataFixture.with { f, problems in
            let week = f.store.askLookup(.dayEvents(.thisWeek))
            expect(week.contains(noRestart) && !week.contains(noCrash), "this week says: \(week)", &problems)
            let one = f.store.askLookup(.dayEvents(monday))
            expect(one.hasSuffix("\n\(noRestart)\n\(noCrash)"),
                   "Mon 13 Nov ends “\(one.suffix(90))”", &problems)
            let crashDay = f.store.askLookup(.dayEvents(tuesday))
            expect(crashDay.contains(noRestart) && !crashDay.contains(noCrash), "Tue 14 Nov says: \(crashDay)", &problems)
        }
    }

    private static func recordedEventsNotDenied() -> [String] {
        AskDataFixture.with { f, problems in
            guard f.machineEvents.append([MachineEvent(kind: .restart, at: f.moment(1, 9))]) else {
                problems.append("could not log the restart"); return
            }
            let week = f.store.askLookup(.dayEvents(.thisWeek))
            expect(!week.contains(noRestart), "a recorded restart is denied: \(week)", &problems)
            expect(f.store.askLookup(.dayEvents(monday)).contains(noRestart), "Mon 13 Nov lost its sentence", &problems)
        }
    }

    private static func noAbsencesWithoutLog() -> [String] {
        AskDataFixture.with { f, problems in
            let before = f.store.askLookup(.dayEvents(.day(year: 2023, month: 10, day: 5)))
            expect(before.contains("No Mac events were recorded before Sun 12 Nov.") && !before.contains(noRestart)
                   && !before.contains(noCrash), "5 Oct says: \(before)", &problems)
            f.store.machineEventLog = nil
            let none = f.store.askLookup(.dayEvents(.thisWeek))
            expect(!none.contains(noRestart) && !none.contains(noCrash), "without a log: \(none)", &problems)
        }
    }

    private static func absencesKeptWhole() -> [String] {
        AskDataFixture.with(extraBreakDays: 1_000) { f, problems in
            let text = f.store.askLookup(.dayEvents(.allTime))
            expect(text.utf8.count <= 1_024, "the text is \(text.utf8.count) bytes", &problems)
            expect(text.contains("The Mac's events are recorded from Sun 12 Nov.\n\(noRestart)\nNewest "),
                   "the tail is not whole: \(text.suffix(160))", &problems)
        }
    }
}
