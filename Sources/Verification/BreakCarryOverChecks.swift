import Foundation

/// Four edges phase 1 left in the reminder and break-log path: a reminder
/// back after a Later is one log row, a reminder after a wake waits for the
/// person, Watching offers no break anywhere, and a countdown that is not a
/// number reads as a break that is over.
enum BreakCarryOverChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A reminder back after a Later stays one log row", laterKeepsOneRow),
        ("A break by hand after a returned reminder still answers it", handBreakAnswersReturnedReminder),
        ("A reminder after a wake waits for the person", reminderWaitsAfterWake),
        ("Watching offers no break anywhere", watchingOffersNoBreak),
        ("A countdown that is not a number reads Break over", countdownNaN),
    ]

    private static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        cal.firstWeekday = 2
        return cal
    }

    private static func at(_ minutes: Double) -> Date { SelfTest.base.addingTimeInterval(minutes * 60) }

    private static func entry(shown: Date, kind: BreakPromptKind = .main) -> BreakPromptEntry {
        BreakPromptEntry(id: UUID(), kind: kind, due: shown.addingTimeInterval(-60), shown: shown)
    }

    // MARK: - The log

    private static func laterKeepsOneRow() -> [String] {
        var problems: [String] = []
        let directory = SelfTest.scratchDirectory()
        let log = BreakLog(directory: directory, calendar: calendar)
        let first = entry(shown: at(0)), back = entry(shown: at(10))
        log.recordShown(first)
        log.noteLater(for: first.id, at: at(1))
        expect(log.recordShown(back) == nil, "the returned reminder is saved", &problems)
        expect(log.prompts.count == 1, "one row, got \(log.prompts.count)", &problems)
        let row = log.prompts.first
        expect(row?.id == back.id, "it takes the new showing's id", &problems)
        expect(row?.laterCount == 1, "the Later count stays, got \(String(describing: row?.laterCount))", &problems)
        expect(row?.outcome == nil && row?.outcomeAt == nil,
               "and it waits for its answer again, got \(String(describing: row?.outcome))", &problems)
        expect(row?.due == first.due && row?.shown == first.shown, "due and shown stay", &problems)
        expect(row?.latestShowing == back.shown, "the latest showing is kept apart", &problems)
        expect(BreakLog(directory: directory, calendar: calendar).prompts == log.prompts,
               "and one row is what a reload reads", &problems)

        log.noteLater(for: back.id, at: at(11))
        expect(log.prompts.first?.laterCount == 2, "a second Later counts on the same row", &problems)
        log.recordShown(entry(shown: at(21)))
        log.setOutcome(.started, for: log.prompts.last?.id ?? UUID(), at: at(22))
        expect(log.prompts.count == 1 && log.prompts.first?.outcome == .started
               && log.prompts.first?.laterCount == 2, "and the answer lands on it", &problems)

        log.recordShown(entry(shown: at(60)))
        expect(log.prompts.count == 2, "an answered reminder is never reused, got \(log.prompts.count)", &problems)
        let guardEntry = entry(shown: at(70), kind: .stretchGuard)
        log.noteLater(for: log.prompts.last?.id ?? UUID(), at: at(61))
        log.recordShown(guardEntry)
        expect(log.prompts.count == 3, "nor by another kind, got \(log.prompts.count)", &problems)

        var logged: [String] = []
        Diagnostics.observer = { logged.append($0) }
        defer { Diagnostics.observer = nil }
        let before = log.prompts
        expect(log.setOutcome(.skipped, for: UUID(), at: at(80)) == nil, "an unknown id is not an error", &problems)
        expect(log.noteLater(for: UUID(), at: at(80)) == nil, "for a Later either", &problems)
        expect(log.prompts == before, "and leaves the rows alone", &problems)
        expect(logged.count == 2, "each writes one line to the log, got \(logged.count)", &problems)
        return problems
    }

    /// The by-hand rule measures from the latest showing: a reminder shown
    /// at 0, put off, and back at 10 is "a moment ago" at 18, not 18 minutes ago.
    private static func handBreakAnswersReturnedReminder() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let f = BreakStoreChecks.make() else { return ["could not create isolated preferences"] }
            defer { f.close() }
            let first = BreakPrompt(tier: .cognitive, worked: 50 * 60, appName: nil)
            let back = BreakPrompt(tier: .cognitive, worked: 60 * 60, appName: nil)
            f.store.logShown(first, at: at(0))
            f.store.breakLog.noteLater(for: first.id, at: at(1))
            f.store.logShown(back, at: at(10))
            f.go(toMinute: 18)
            f.store.startBreak()
            expect(f.store.breakLog.prompts.count == 1, "one row, got \(f.store.breakLog.prompts.count)", &problems)
            expect(f.store.breakLog.prompts.first?.outcome == .started,
                   "the break by hand answers it, got \(String(describing: f.store.breakLog.prompts.first?.outcome))",
                   &problems)
            return problems
        }
    }

    // MARK: - After a wake

    private static func reminderWaitsAfterWake() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            expect(!AppCoordinator.breakReminderReachesScreen(
                screenLocked: false, displayAsleep: false, machineSleeping: false, away: false,
                awaitingPresence: true), "nobody has shown they are back, so it waits", &problems)
            expect(AppCoordinator.breakReminderReachesScreen(
                screenLocked: false, displayAsleep: false, machineSleeping: false, away: false,
                awaitingPresence: false), "and it shows once they have", &problems)
            guard let f = BreakStoreChecks.make() else { return problems + ["could not create isolated preferences"] }
            defer { f.close() }
            expect(!f.store.isAwaitingPresence, "a store nobody woke is not waiting", &problems)
            f.store.noteMachineWake()
            expect(f.store.isAwaitingPresence, "a wake leaves the store waiting for the person", &problems)
            return problems
        }
    }

    // MARK: - Watching

    private static func watchingOffersNoBreak() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let film = BreakStoreChecks.make(prepare: { engine, clock in
                BreakStoreChecks.running(engine, clock)
                engine.transition(on: .watchingObserved(seconds: 20 * 60))
            }), let running = BreakStoreChecks.make(prepare: BreakStoreChecks.running),
                  let idle = BreakStoreChecks.make() else { return ["could not create isolated preferences"] }
            defer { film.close(); running.close(); idle.close() }
            expect(film.store.state == .paused(reason: .watching), "the fixture is watching", &problems)
            expect(!film.store.canTakeBreak, "a film offers no break", &problems)
            expect(!film.store.focusSurfaceComposition.offersTakeBreak
                   && !SessionCommandState.Snapshot(film.store).takeBreakEnabled,
                   "not in the hero or the menu", &problems)
            film.store.startBreak(from: BreakPrompt(tier: .cognitive, worked: 50 * 60, appName: nil))
            expect(!film.store.isOnBreak, "and a Start pressed on a reminder does nothing", &problems)

            expect(idle.store.canTakeBreak && running.store.canTakeBreak, "idle and running still may", &problems)
            running.store.togglePause()
            expect(running.engine.state == .paused(reason: .manual) && running.store.canTakeBreak,
                   "so does a pause by hand", &problems)
            running.store.startBreak()
            expect(running.store.isOnBreak, "and the break begins", &problems)

            let reminder = BreakPrompt(tier: .cognitive, worked: 50 * 60, appName: nil)
            let withheld = BreakHUDCopy.reminder(reminder, canStart: false).buttons.map(\.title)
            expect(withheld == ["Later", "Skip"], "the reminder keeps Later and Skip, got \(withheld)", &problems)
            let guardOnly = BreakHUDCopy.reminder(BreakPrompt(tier: .ultradian, worked: 90 * 60, appName: nil),
                                                  canStart: false).buttons.map(\.title)
            expect(guardOnly == ["Remind me in 15 min"], "and the guard its Remind me, got \(guardOnly)", &problems)
            expect(BreakHUDCopy.reminder(reminder).buttons.map(\.title) == ["Start break", "Later", "Skip"],
                   "while the others still start one", &problems)
            return problems
        }
    }

    // MARK: - The countdown

    private static func countdownNaN() -> [String] {
        var problems: [String] = []
        expect(BreakCountdown.cardText(remaining: .nan) == "Break over",
               "got \(BreakCountdown.cardText(remaining: .nan))", &problems)
        expect(BreakCountdown.cardText(remaining: 300) == "5m left"
               && BreakCountdown.cardText(remaining: 30) == "30s left"
               && BreakCountdown.cardText(remaining: -30) == "Break over"
               && BreakCountdown.cardText(remaining: -180) == "+3m over",
               "and the numbers read as before", &problems)
        return problems
    }
}
