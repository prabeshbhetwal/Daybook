import Foundation

/// The facts a review note is written from, read from a real store: a day's
/// are the Story's own figures and a week's or month's are History's, and the
/// questions the surfaces ask (is it current, is Yesterday or Wrap up offered)
/// follow the clock. Uses the Ask fixture: sessions on Mon 13 Nov, Tue 14 Nov
/// and Tue 17 Oct 2023, and the clock on Wed 15 Nov at 9:13.
enum ReviewNoteStoreChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A past day's note facts match the day History shows", dayFactsMatchHistory),
        ("A note's day place is the same place History opens", dayPlaceIsHistorysPlace),
        ("A week's note facts carry History's week figures", weekFactsMatchHistory),
        ("An empty day and a year have no note facts", noFactsWhereNoNote),
        ("Yesterday is finished just after midnight", yesterdayFinishedAfterMidnight),
        ("A session running across midnight leaves yesterday's facts as they were and changes today's",
         runningAcrossMidnight),
        ("Today and this week are current, so their notes wait for a request", currentPeriods),
        ("A finished period is compared with the one before it, a partial one is not", finishedPeriodsCompare),
        ("The Yesterday notice is offered once per day until dismissed", yesterdayOffer),
        ("Yesterday's figures line is right when History has never been open", figuresLineWithoutHistory),
        ("Wrap up today is offered only when today has a session and none is running", wrapUpOffer),
    ]

    private typealias Fixture = AskLookupChecks.Fixture

    /// A moment on the day `back` days before the clock's day.
    private static func moment(_ f: Fixture, back: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let day = f.calendar.date(byAdding: .day, value: -back, to: f.calendar.startOfDay(for: f.clock.value))!
        return f.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private static func place(_ level: HistoryLevel, containing date: Date, _ f: Fixture) -> HistoryPlace {
        HistoryPlace(level: level, span: HistoryTreeBuilder.period(level, containing: date, calendar: f.calendar))
    }

    private static func dayFactsMatchHistory() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            f.store.setReviewVisible(true)
            let tuesday = f.store.notePlace(forDayContaining: moment(f, back: 1, 14))
            let summary = f.store.historySummary(for: tuesday)
            let facts = f.store.noteFacts(for: tuesday)
            expect(facts?.kind == .day, "Tuesday's facts are \(String(describing: facts?.kind))", &problems)
            let lines = facts?.lines ?? []
            expect(lines.first == "Day: Tuesday 14 November 2023", "the heading is “\(lines.first ?? "none")”", &problems)
            expect(lines.contains("Focus: 1h 30m over 1 session"), "Tuesday says \(lines)", &problems)
            expect(lines.contains("Focus: \(DurationText.compact(summary.focused)) over \(summary.sessions) session"),
                   "History shows \(summary.focused)s over \(summary.sessions), the facts say \(lines)", &problems)
            expect(lines.contains { $0.hasPrefix("Top apps: Safari 1h") }, "Safari's hour is missing from \(lines)", &problems)
            expect(!f.store.noteIsCurrent(tuesday), "a finished day reads as current", &problems)
        }
    }

    /// One note per day depends on every surface naming the day by the same id.
    private static func dayPlaceIsHistorysPlace() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            f.store.setReviewVisible(true)
            let tuesday = moment(f, back: 1, 14)
            var parent: HistoryPlace?
            var row: HistoryRow?
            while let next = f.store.historyRows(under: parent).first(where: { $0.place.span.holds(tuesday) }) {
                row = next
                parent = next.place
                if next.place.level == .day { break }
            }
            let mine = f.store.notePlace(forDayContaining: tuesday)
            expect(row?.place.level == .day, "History's path to Tuesday ended at \(String(describing: row?.place.level))",
                   &problems)
            expect(row?.id == mine.id, "History's day row is \(row?.id ?? "none"), the note's place \(mine.id)", &problems)
            expect(mine.level == .day && mine.span.holds(tuesday), "the note's place is \(mine)", &problems)
        }
    }

    private static func weekFactsMatchHistory() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            f.store.setReviewVisible(true)
            let week = place(.week, containing: f.clock.value, f)
            let summary = f.store.historySummary(for: week)
            let facts = f.store.noteFacts(for: week)
            let lines = facts?.lines ?? []
            expect(facts?.kind == .period, "the week's facts are \(String(describing: facts?.kind))", &problems)
            expect(lines.first == "Week of Monday 13 November 2023 (so far)", "the heading is “\(lines.first ?? "none")”",
                   &problems)
            expect(lines.contains { $0.hasPrefix("Focus: \(DurationText.compact(summary.focused)) over \(summary.sessions) sessions") },
                   "History shows \(summary.focused)s over \(summary.sessions), the facts say \(lines)", &problems)
            expect(lines.contains("Most time went to: Parser 1h 30m, Thesis 1h"), "the week's names are in \(lines)", &problems)
            expect(f.store.noteIsCurrent(week), "this week is not current", &problems)
        }
    }

    private static func noFactsWhereNoNote() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            f.store.setReviewVisible(true)
            let now = f.clock.value
            let empty = f.store.notePlace(forDayContaining: moment(f, back: 6, 12))
            expect(f.store.noteFacts(for: empty) == nil, "a day with nothing has facts", &problems)
            let year = place(.year, containing: now, f)
            expect(f.store.noteFacts(for: year) == nil, "a year has facts", &problems)
            let september = place(.month, containing: moment(f, back: 60, 12), f)
            expect(f.store.noteFacts(for: september) == nil, "an empty month has facts", &problems)
            let lastWeek = place(.week, containing: moment(f, back: 7, 12), f)
            expect(f.store.noteFacts(for: lastWeek) == nil, "an empty week has facts", &problems)
        }
    }

    private static func yesterdayFinishedAfterMidnight() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            let wednesday = f.store.notePlace(forDayContaining: f.clock.value)
            expect(f.store.noteIsCurrent(wednesday), "Wednesday morning is not current", &problems)
            // Exactly midnight is Thursday's: a day ends before its end instant.
            f.clock.value = wednesday.span.end
            expect(!f.store.noteIsCurrent(wednesday), "Wednesday is still current at its own end", &problems)
            f.clock.advance(30 * 60)
            expect(!f.store.noteIsCurrent(wednesday), "Wednesday is current at 00:30 on Thursday", &problems)
            expect(f.store.noteIsCurrent(f.store.notePlace(forDayContaining: f.clock.value)),
                   "Thursday is not current at 00:30", &problems)
        }
    }

    private static func runningAcrossMidnight() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            let wednesday = f.store.notePlace(forDayContaining: f.clock.value)
            f.clock.value = f.calendar.date(bySettingHour: 23, minute: 30, second: 0, of: f.clock.value)!
            f.engine.start(workType: .deepWork, intent: "Night shift")
            f.clock.value = wednesday.span.end
            f.clock.advance(30 * 60)
            let thursday = f.store.notePlace(forDayContaining: f.clock.value)
            let yesterdayAt30 = f.store.noteFacts(for: wednesday)?.text
            let todayAt30 = f.store.noteFacts(for: thursday)?.text
            f.clock.advance(15 * 60)
            let yesterdayAt45 = f.store.noteFacts(for: wednesday)?.text
            let todayAt45 = f.store.noteFacts(for: thursday)?.text

            // Only the half hour before midnight is Wednesday's; it stops growing.
            expect(yesterdayAt30?.contains("Night shift at") == true && yesterdayAt30?.contains(", 30m") == true,
                   "yesterday's share is not its 30m: \(yesterdayAt30 ?? "none")", &problems)
            expect(yesterdayAt30 == yesterdayAt45, "yesterday changed as the session grew: “\(yesterdayAt30 ?? "none")” then “\(yesterdayAt45 ?? "none")”", &problems)
            expect(todayAt30?.contains(", 30m") == true && todayAt45?.contains(", 45m") == true,
                   "today's share is “\(todayAt30 ?? "none")” then “\(todayAt45 ?? "none")”", &problems)
            expect(todayAt30 != todayAt45, "today's facts did not change as the session grew", &problems)
        }
    }

    private static func currentPeriods() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            let now = f.clock.value
            let lastWeek = f.calendar.date(byAdding: .weekOfYear, value: -1, to: now)!
            expect(f.store.noteIsCurrent(f.store.notePlace(forDayContaining: now)), "today is not current", &problems)
            expect(f.store.noteIsCurrent(place(.week, containing: now, f)), "this week is not current", &problems)
            expect(f.store.noteIsCurrent(place(.month, containing: now, f)), "this month is not current", &problems)
            expect(!f.store.noteIsCurrent(place(.week, containing: lastWeek, f)), "last week is current", &problems)
            expect(!f.store.noteIsCurrent(f.store.notePlace(forDayContaining: moment(f, back: 1, 12))),
                   "yesterday is current", &problems)
        }
    }

    private static func finishedPeriodsCompare() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            f.store.setReviewVisible(true)
            let november = place(.month, containing: f.clock.value, f)
            let during = f.store.noteFacts(for: november)?.observations ?? []
            expect(!during.contains { $0.contains("than the month before") },
                   "November is compared with October while it runs: \(during)", &problems)

            // November: 2h 30m. October: 2h.
            f.clock.value = f.calendar.date(from: DateComponents(year: 2023, month: 12, day: 5, hour: 9, minute: 13))!
            let after = f.store.noteFacts(for: november)?.observations ?? []
            expect(after.contains("30m more focus than the month before"), "finished November says \(after)", &problems)
            let cut = HistoryPlace(level: .month, span: DateInterval(start: november.start, end: moment(f, back: 20, 0)))
            let part = f.store.noteFacts(for: cut)?.observations ?? []
            expect(!part.contains { $0.contains("than the month before") },
                   "part of November is compared with all of October: \(part)", &problems)
        }
    }

    private static func yesterdayOffer() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            let tuesday = f.store.notePlace(forDayContaining: moment(f, back: 1, 12))
            expect(f.store.yesterdayNotePlace() == tuesday, "yesterday's offer is \(String(describing: f.store.yesterdayNotePlace()))",
                   &problems)
            f.store.dismissYesterdayNote()
            expect(f.store.yesterdayNotePlace() == nil, "the offer came back after Done", &problems)

            // Wednesday gets a session; on Thursday it is the new yesterday.
            f.engine.start(workType: .deepWork, intent: "Review")
            f.clock.advance(30 * 60)
            expect(f.engine.stop(), "the session did not stop", &problems)
            let wednesday = f.store.notePlace(forDayContaining: f.clock.value)
            f.clock.value = f.calendar.date(byAdding: .day, value: 1, to: f.clock.value)!
            expect(f.store.yesterdayNotePlace() == wednesday, "the next day's offer is \(String(describing: f.store.yesterdayNotePlace()))",
                   &problems)

            // A day with only a recorded break has no note to offer.
            let lunch = f.calendar.date(bySettingHour: 8, minute: 0, second: 0, of: f.clock.value)!
            let rest = SessionRecord(name: "Lunch", workType: .breakTime, start: lunch,
                                     end: lunch.addingTimeInterval(30 * 60), workSeconds: 1_800)
            expect(f.engine.archive.append(rest) == nil, "the break was not saved", &problems)
            f.clock.value = f.calendar.date(byAdding: .day, value: 1, to: f.clock.value)!
            expect(f.store.yesterdayNotePlace() == nil, "a break-only day is offered", &problems)
        }
    }

    /// The Story is the only thing open, so History has not refreshed: the
    /// line must come from the day itself.
    private static func figuresLineWithoutHistory() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            let tuesday = f.store.notePlace(forDayContaining: moment(f, back: 1, 12))
            let line = f.store.noteFiguresLine(for: tuesday)
            expect(line.hasPrefix("1h 30m focus") && line.hasSuffix("1 session"), "the line says “\(line)”", &problems)
            f.store.setReviewVisible(true)
            let summary = f.store.historySummary(for: tuesday)
            expect(line.hasPrefix("\(DurationText.compact(summary.focused)) focus")
                    && line.hasSuffix(" · \(summary.sessions) session"),
                   "the line “\(line)” differs from History's \(summary.focused)s over \(summary.sessions)", &problems)
        }
    }

    private static func wrapUpOffer() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            expect(!f.store.wrapUpOffered, "Wrap up is offered with no session today", &problems)
            f.engine.start(workType: .deepWork, intent: "Review")
            f.clock.advance(10 * 60)
            expect(!f.store.wrapUpOffered, "Wrap up is offered while a session runs", &problems)
            expect(f.engine.stop(), "the session did not stop", &problems)
            expect(f.store.wrapUpOffered, "Wrap up is not offered after today's session", &problems)
            f.engine.start(workType: .deepWork, intent: "Review")
            f.clock.advance(10 * 60)
            expect(!f.store.wrapUpOffered, "Wrap up is offered while a second session runs", &problems)
            expect(f.engine.stop(), "the second session did not stop", &problems)
            expect(f.store.wrapUpOffered, "Wrap up is not offered after the second session", &problems)
            f.clock.value = f.calendar.date(byAdding: .day, value: 1, to: f.clock.value)!
            expect(!f.store.wrapUpOffered, "Wrap up is offered on a day with no session", &problems)
        }
    }
}
