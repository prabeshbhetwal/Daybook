import Foundation

/// Where the store's note questions meet History's own figures at the edges:
/// a session resumed after another is counted once, a notice closed after
/// midnight closes the day it showed, and a period is compared only with one
/// the record holds whole. Uses the Ask fixture of `ReviewNoteStoreChecks`.
enum ReviewNoteStoreEdgeChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A day's note facts and its figures line count a resumed session once, as History does", resumedSessionCounted),
        ("Done after midnight closes the day the notice showed, and the new yesterday is still offered", doneAfterMidnight),
        ("A period is compared only with a previous period the record holds whole", previousPeriodInRecord),
    ]

    private typealias Fixture = AskLookupChecks.Fixture

    /// A moment on the day `back` days before the clock's day.
    private static func moment(_ f: Fixture, back: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let day = f.calendar.date(byAdding: .day, value: -back, to: f.calendar.startOfDay(for: f.clock.value))!
        return f.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private static func record(_ name: String, from start: Date, minutes: Double, thread: UUID = UUID()) -> SessionRecord {
        SessionRecord(name: name, workType: .deepWork, start: start, end: start.addingTimeInterval(minutes * 60),
                      workSeconds: minutes * 60, threadID: thread)
    }

    /// Sun 12 Nov has Parser, Mail, then Parser again on the same thread: the
    /// Story lists three rows, History counts two sessions.
    private static func resumedSessionCounted() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            let thread = UUID()
            let records = [record("Parser", from: moment(f, back: 3, 9), minutes: 60, thread: thread),
                           record("Mail", from: moment(f, back: 3, 10), minutes: 30),
                           record("Parser", from: moment(f, back: 3, 11), minutes: 30, thread: thread)]
            for entry in records where f.engine.archive.append(entry) != nil { problems.append("a session was not saved"); return }
            f.store.setReviewVisible(true)
            let sunday = f.store.notePlace(forDayContaining: moment(f, back: 3, 12))
            let rows = f.store.storyDayProjection(on: sunday.start, calendar: f.calendar).sessions.filter {
                if case .session = $0 { return true }
                return false
            }
            let summary = f.store.historySummary(for: sunday)
            expect(rows.count == 3 && summary.sessions == 2,
                   "the Story lists \(rows.count) rows and History counts \(summary.sessions) sessions, not 3 and 2", &problems)
            let facts = f.store.noteFacts(for: sunday)
            expect(facts?.lines.contains("Focus: 2h over 2 sessions") == true,
                   "the facts say \(facts?.lines ?? []), not 2 sessions", &problems)
            expect(facts?.observations.contains("2 sessions ran as 3 stretches") == true,
                   "the observations are \(facts?.observations ?? [])", &problems)
            let line = f.store.noteFiguresLine(for: sunday)
            expect(line.hasPrefix("2h focus") && line.hasSuffix(" · 2 sessions"), "the figures line says “\(line)”", &problems)
        }
    }

    /// The notice shows Tuesday; Wednesday has a session of its own; the Done
    /// press comes at 00:30 on Thursday, when yesterday is Wednesday.
    private static func doneAfterMidnight() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            let tuesday = f.store.notePlace(forDayContaining: moment(f, back: 1, 12))
            expect(f.store.yesterdayNotePlace() == tuesday, "the notice is for \(String(describing: f.store.yesterdayNotePlace()))",
                   &problems)
            f.engine.start(workType: .deepWork, intent: "Review")
            f.clock.advance(30 * 60)
            expect(f.engine.stop(), "the session did not stop", &problems)
            let wednesday = f.store.notePlace(forDayContaining: f.clock.value)
            f.clock.value = wednesday.span.end
            f.clock.advance(30 * 60)
            f.store.dismissYesterdayNote(tuesday)
            expect(f.store.engine.store.yesterdayNoteDismissedDay == tuesday.start,
                   "Done recorded \(String(describing: f.store.engine.store.yesterdayNoteDismissedDay)), not Tuesday", &problems)
            expect(f.store.yesterdayNotePlace() == wednesday,
                   "the new day's offer is \(String(describing: f.store.yesterdayNotePlace()))", &problems)
        }
    }

    /// The record starts on 17 October, so October, and the week of 16 October,
    /// are only partly in it; November, December and the week of 6 November are
    /// whole. Sessions are added on 24 Oct, 8 Nov and 5 Dec, before History is
    /// first read. On 15 Nov, the current week of 13 Nov and that week cut short
    /// have a whole week before them and are still not compared with it. The
    /// clock then moves to January so every period has finished.
    private static func previousPeriodInRecord() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            func date(_ month: Int, _ day: Int, hour: Int = 9, year: Int = 2023) -> Date {
                f.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: 13))!
            }
            for (start, minutes) in [(date(10, 24), 60.0), (date(11, 8), 60), (date(12, 5), 30)]
                where f.engine.archive.append(record("Review", from: start, minutes: minutes)) != nil {
                problems.append("a session was not saved")
                return
            }
            f.store.setReviewVisible(true)
            func observations(_ level: HistoryLevel, containing day: Date) -> [String] {
                let period = HistoryPlace(level: level, span: HistoryTreeBuilder.period(level, containing: day, calendar: f.calendar))
                return f.store.noteFacts(for: period)?.observations ?? ["no facts"]
            }
            // The clock is on Wed 15 Nov: the week of 6 Nov is whole and in the record.
            let running = observations(.week, containing: date(11, 14))
            expect(!running.contains { $0.contains("than the week before") },
                   "the week still running is compared with the week before: \(running)", &problems)
            let cut = HistoryPlace(level: .week, span: DateInterval(start: f.calendar.startOfDay(for: date(11, 13)),
                                                                    end: f.calendar.startOfDay(for: date(11, 15))))
            let part = f.store.noteFacts(for: cut)?.observations ?? ["no facts"]
            expect(!part.contains { $0.contains("than the week before") },
                   "a week cut short on 15 November is compared with the whole week before: \(part)", &problems)
            f.clock.value = date(1, 10, year: 2024)
            let november = observations(.month, containing: date(11, 14))
            expect(!november.contains { $0.contains("than the month before") },
                   "November is compared with a partly recorded October: \(november)", &problems)
            let october = observations(.week, containing: date(10, 24))
            expect(!october.contains { $0.contains("than the week before") },
                   "the week of 23 October is compared with a partly recorded week: \(october)", &problems)
            let week = observations(.week, containing: date(11, 14))
            expect(week.contains("1h 30m more focus than the week before"),
                   "the week of 13 November, after a whole week, says \(week)", &problems)
            let december = observations(.month, containing: date(12, 5))
            expect(december.contains("3h less focus than the month before"),
                   "December, after a whole November, says \(december)", &problems)
        }
    }
}
