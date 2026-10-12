import Foundation

/// Following a source: each place an Ask answer lists opens History where the
/// figure came from, and the Ask sheet gets out of the way while the side
/// panel stays beside it. The fixture is the one the lookups use: Wed 15 Nov
/// 2023, with Thesis on Mon 13 Nov, Parser on Tue 14 Nov and Thesis again on
/// Tue 17 Oct, so History's top is the year 2023.
enum AskFollowChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Following a day opens History with that day open", dayOpensHistoryDay),
        ("Following a session picks it on its day", sessionIsPicked),
        ("Following a session that no longer exists opens its day", missingSessionOpensItsDay),
        ("A renamed session is still found by its thread", renamedSessionStillOpensByThread),
        ("Following a week unfolds History to that week's row, focused", periodUnfoldsToItsRow),
        ("A current week listed with its whole calendar span opens History's own clipped row", currentWeekByStart),
        ("A period that starts before the record opens its clipped row, and one wholly before it opens the top",
         pastAndOutsidePeriods),
        ("Following History itself opens it at the top", historyOpensTop),
        ("The sheet closes when a source is followed, the side panel stays", sheetClosesPanelStays),
        ("The Awards source opens the Awards sheet in either placement", awardsOpensSheet),
    ]

    private typealias Fixture = AskLookupChecks.Fixture

    // MARK: - Fixture

    private static func date(_ f: Fixture, _ month: Int, _ day: Int) -> Date {
        f.calendar.date(from: DateComponents(year: 2023, month: month, day: day))!
    }

    private static func dayPlace(_ f: Fixture, _ month: Int, _ day: Int) -> HistoryPlace {
        let start = date(f, month, day)
        return HistoryPlace(level: .day, span: DateInterval(start: start, end: HistoryTreeBuilder.dayAfter(start, calendar: f.calendar)))
    }

    private static func place(_ f: Fixture, _ level: HistoryLevel, from start: (Int, Int), to end: (Int, Int)) -> HistoryPlace {
        HistoryPlace(level: level, span: DateInterval(start: date(f, start.0, start.1), end: date(f, end.0, end.1)))
    }

    private static func link(_ target: AskLink.Target) -> AskLink {
        AskLink(target: target, label: "source", role: .totals)
    }

    private static func parserThread(_ f: Fixture) -> UUID {
        f.engine.archive.records.first { $0.name == "Parser" }?.threadID ?? UUID()
    }

    /// A window model on the fixture's store, with the Ask sheet closed.
    private static func withWindow(_ body: @MainActor (Fixture, MainWindowModel, inout [String]) -> Void) -> [String] {
        AskLookupChecks.withFixture { f, problems in
            MainActor.assumeIsolated { body(f, MainWindowModel(store: f.store), &problems) }
        }
    }

    // MARK: - Checks

    private static func dayOpensHistoryDay() -> [String] {
        withWindow { f, navigation, problems in
            navigation.openSheet(.ask)
            navigation.follow(link(.day(date(f, 11, 13))))
            expect(navigation.workspace == .history && navigation.sheet == nil,
                   "the day opened \(navigation.workspace) with sheet \(String(describing: navigation.sheet))", &problems)
            expect(navigation.historyOpen.last == dayPlace(f, 11, 13),
                   "History opened \(navigation.historyOpen.map(\.id)), not 13 Nov", &problems)
            expect(navigation.historySession == nil, "a day picked a session", &problems)
        }
    }

    private static func sessionIsPicked() -> [String] {
        withWindow { f, navigation, problems in
            let thread = parserThread(f)
            navigation.follow(link(.session(thread: thread, day: date(f, 11, 14))))
            expect(navigation.workspace == .history, "the session opened \(navigation.workspace)", &problems)
            expect(navigation.historySession == HistorySessionPick(thread: thread, day: date(f, 11, 14)),
                   "History picked \(String(describing: navigation.historySession))", &problems)
            expect(navigation.historyOpen.last == dayPlace(f, 11, 14),
                   "its day is not the deepest open row: \(navigation.historyOpen.map(\.id))", &problems)
        }
    }

    private static func missingSessionOpensItsDay() -> [String] {
        withWindow { f, navigation, problems in
            navigation.follow(link(.session(thread: UUID(), day: date(f, 11, 14))))
            expect(navigation.historySession == nil,
                   "a session that is not there was picked: \(String(describing: navigation.historySession))", &problems)
            expect(navigation.historyOpen.last == dayPlace(f, 11, 14),
                   "its day did not open: \(navigation.historyOpen.map(\.id))", &problems)
        }
    }

    private static func renamedSessionStillOpensByThread() -> [String] {
        withWindow { f, navigation, problems in
            let thread = parserThread(f)
            expect(f.engine.archive.rename(thread: thread, to: "Lexer"), "the rename was refused", &problems)
            navigation.follow(link(.session(thread: thread, day: date(f, 11, 14))))
            expect(navigation.historySession == HistorySessionPick(thread: thread, day: date(f, 11, 14)),
                   "the renamed session was not picked: \(String(describing: navigation.historySession))", &problems)
        }
    }

    private static func periodUnfoldsToItsRow() -> [String] {
        withWindow { f, navigation, problems in
            // History's row for this week ends at today, the end of Wed 15 Nov.
            let row = place(f, .week, from: (11, 13), to: (11, 16))
            navigation.follow(link(.period(row)))
            expect(navigation.historyOpen.last == row, "the week row is not open: \(navigation.historyOpen.map(\.id))", &problems)
            expect(navigation.historyFocus == .row(row),
                   "the keyboard is on \(String(describing: navigation.historyFocus))", &problems)
            // The year is History's top, so the open rows start at the month.
            expect(navigation.historyOpen.map(\.level) == [.month, .week],
                   "the path is \(navigation.historyOpen.map(\.level))", &problems)
            expect(navigation.historyScrollTarget == row.id, "the scroll target is \(String(describing: navigation.historyScrollTarget))", &problems)
            expect(navigation.historySession == nil, "a period picked a session", &problems)
        }
    }

    /// A lookup lists this week with the whole week, 13 to 19 Nov, while
    /// History draws the row only to today. The two are the same row.
    private static func currentWeekByStart() -> [String] {
        withWindow { f, navigation, problems in
            let row = place(f, .week, from: (11, 13), to: (11, 16))
            let whole = place(f, .week, from: (11, 13), to: (11, 20))
            expect(whole.span != row.span, "the fixture's week is not clipped to today", &problems)
            navigation.follow(link(.period(whole)))
            expect(navigation.historyOpen.last == row,
                   "the whole week opened \(navigation.historyOpen.map(\.id)), not History's own row", &problems)
            expect(navigation.historyFocus == .row(row),
                   "the keyboard is on \(String(describing: navigation.historyFocus))", &problems)
            let month = place(f, .month, from: (11, 1), to: (12, 1))
            navigation.follow(link(.period(month)))
            expect(navigation.historyOpen.last?.level == .month && navigation.historyOpen.last?.start == month.start,
                   "the whole month opened \(navigation.historyOpen.map(\.id))", &problems)
        }
    }

    /// A lookup lists October 2023 as the whole month and the week of Mon 16 Oct
    /// as the whole week. The record starts on Tue 17 Oct, so History's rows for
    /// both begin there; the sources must open those rows, not the top.
    private static func pastAndOutsidePeriods() -> [String] {
        withWindow { f, navigation, problems in
            let october = place(f, .month, from: (10, 1), to: (11, 1))
            let octoberRow = place(f, .month, from: (10, 17), to: (11, 1))
            navigation.follow(link(.period(october)))
            expect(navigation.historyOpen.last == octoberRow && navigation.historyFocus == .row(octoberRow),
                   "October opened \(navigation.historyOpen.map(\.id))", &problems)

            let firstWeek = place(f, .week, from: (10, 16), to: (10, 23))
            let firstWeekRow = place(f, .week, from: (10, 17), to: (10, 23))
            navigation.follow(link(.period(firstWeek)))
            expect(navigation.historyOpen.last == firstWeekRow && navigation.historyFocus == .row(firstWeekRow),
                   "the first week opened \(navigation.historyOpen.map(\.id))", &problems)
            expect(navigation.historyOpen.map(\.level) == [.month, .week],
                   "the first week's path is \(navigation.historyOpen.map(\.level))", &problems)

            // Wholly before the record, or ending where it begins: no row, so the top.
            let before = HistoryPlace(level: .month, span: DateInterval(
                start: f.calendar.date(from: DateComponents(year: 2022, month: 3, day: 1))!,
                end: f.calendar.date(from: DateComponents(year: 2022, month: 4, day: 1))!))
            let endsAtFirstDay = place(f, .week, from: (10, 10), to: (10, 17))
            for (what, outside) in [("a month before the record", before), ("a week ending where it begins", endsAtFirstDay)] {
                navigation.follow(link(.period(firstWeek)))
                navigation.follow(link(.period(outside)))
                expect(navigation.workspace == .history && navigation.historyOpen.isEmpty,
                       "\(what) left \(navigation.historyOpen.map(\.id)) open", &problems)
                expect(navigation.historyFocus == nil,
                       "the top has focus \(String(describing: navigation.historyFocus))", &problems)
            }
        }
    }

    private static func historyOpensTop() -> [String] {
        withWindow { f, navigation, problems in
            navigation.follow(link(.day(date(f, 11, 14))))
            expect(!navigation.historyOpen.isEmpty, "the day did not open", &problems)
            navigation.openSheet(.ask)
            navigation.follow(link(.history))
            expect(navigation.workspace == .history && navigation.sheet == nil && navigation.historyOpen.isEmpty,
                   "History opened \(navigation.workspace), sheet \(String(describing: navigation.sheet)), "
                   + "\(navigation.historyOpen.count) rows open", &problems)
        }
    }

    private static func awardsOpensSheet() -> [String] {
        withWindow { f, navigation, problems in
            let awards = AskLink(target: .awards, label: "Awards", role: .streakAndAwards, names: ["streak"])
            let preferences = f.engine.store

            preferences.askPlacement = .sheet
            navigation.openAsk()
            let model = navigation.askModel
            let turns = model?.turns.count
            navigation.follow(awards)
            expect(navigation.sheet == .awards && !navigation.askPanelOpen && navigation.askModel === model
                       && model?.turns.count == turns,
                   "from the sheet, Awards opened sheet \(String(describing: navigation.sheet)), "
                   + "panel \(navigation.askPanelOpen)", &problems)
            navigation.closeSheet()

            preferences.askPlacement = .panel
            navigation.openAsk()
            expect(navigation.askPanelOpen, "the panel did not open", &problems)
            navigation.follow(awards)
            expect(navigation.sheet == .awards && navigation.askPanelOpen,
                   "from the panel, Awards opened sheet \(String(describing: navigation.sheet)), "
                   + "panel \(navigation.askPanelOpen)", &problems)

            let label = AskSourcesView.accessibilityLabel(for: AskSource(link: awards, mention: nil))
            expect(label == "Awards, streak and awards. Opens Awards.", "Awards reads \"\(label)\"", &problems)
            let day = AskSourcesView.accessibilityLabel(for: AskSource(link: link(.day(date(f, 11, 13))), mention: nil))
            expect(day.hasSuffix("Opens in History."), "a day reads \"\(day)\"", &problems)
        }
    }

    private static func sheetClosesPanelStays() -> [String] {
        withWindow { f, navigation, problems in
            let day = link(.day(date(f, 11, 13)))
            let preferences = f.engine.store

            preferences.askPlacement = .sheet
            navigation.openAsk()
            let model = navigation.askModel
            expect(navigation.sheet == .ask && model != nil && !navigation.askPanelOpen,
                   "the sheet placement opened \(String(describing: navigation.sheet))", &problems)
            navigation.follow(day)
            expect(navigation.sheet == nil && !navigation.askPanelOpen && navigation.askModel === model,
                   "following left sheet \(String(describing: navigation.sheet)) and replaced the chat", &problems)
            navigation.openAsk()
            expect(navigation.sheet == .ask && navigation.askModel === model, "⌘K did not bring the chat back", &problems)
            navigation.closeSheet()

            preferences.askPlacement = .panel
            navigation.openAsk()
            expect(navigation.askPanelOpen && navigation.sheet == nil && navigation.askModel === model,
                   "the panel placement opened panel \(navigation.askPanelOpen), sheet \(String(describing: navigation.sheet))",
                   &problems)
            navigation.follow(day)
            expect(navigation.askPanelOpen && navigation.workspace == .history,
                   "following closed the panel (open \(navigation.askPanelOpen))", &problems)
            navigation.openAsk()
            expect(!navigation.askPanelOpen, "⌘K did not close the open panel", &problems)

            // A sheet over the window is closed by ⌘K; the panel then opens, never closes.
            navigation.openSheet(.settings)
            navigation.openAsk()
            expect(navigation.sheet == nil && navigation.askPanelOpen,
                   "⌘K over Settings left sheet \(String(describing: navigation.sheet)), panel \(navigation.askPanelOpen)",
                   &problems)
            navigation.openSheet(.awards)
            navigation.openAsk()
            expect(navigation.sheet == nil && navigation.askPanelOpen,
                   "⌘K over Awards left sheet \(String(describing: navigation.sheet)), panel \(navigation.askPanelOpen)",
                   &problems)
            navigation.closeAskPanel()
            expect(!navigation.askPanelOpen, "the close button left the panel open", &problems)
        }
    }
}
