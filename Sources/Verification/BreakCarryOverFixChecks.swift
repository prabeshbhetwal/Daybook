import Foundation

/// Fix round 1 of the carry-overs: a reminder put off and then rested away no
/// longer swallows the next one, the coordinator's two decisions are checked
/// where they are made, a start the store refuses is logged as unanswered, and
/// a reminder that cannot start a break says nothing it cannot do.
enum BreakCarryOverFixChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A reminder that returns by the clock is one log row", returnsByTheClock),
        ("A reminder put off and then walked away from closes, and the next is a row of its own", walkedAwayCloses),
        ("A rest taken after a Later closes it as credited", restCreditsOpenLater),
        ("A closed Later is never reused, and neither is one in a phase-1 file", closedLaterNotReused),
        ("The coordinator holds a reminder after a wake and while away", coordinatorHoldsReminder),
        ("A reminder's buttons follow whether a break can begin", reminderContentFollowsStore),
        ("A Start the store refuses is logged as unanswered", refusedStartUnanswered),
    ]

    private static func at(_ minutes: Double) -> Date { SelfTest.base.addingTimeInterval(minutes * 60) }

    private static func entry(shown: Date, kind: BreakPromptKind = .main) -> BreakPromptEntry {
        BreakPromptEntry(id: UUID(), kind: kind, due: shown.addingTimeInterval(-60), shown: shown)
    }

    private static func film() -> BreakStoreChecks.Fixture? {
        MainActor.assumeIsolated {
            BreakStoreChecks.make(prepare: { engine, clock in
                BreakStoreChecks.running(engine, clock)
                engine.transition(on: .watchingObserved(seconds: 20 * 60))
            })
        }
    }

    // MARK: - Through the store's own evaluation

    /// The first reminder shown and put off, as the store raises it.
    @MainActor
    private static func putOff(_ f: BreakStoreChecks.Fixture, _ shown: BreakStoreChecks.Box<[BreakPrompt]>) -> Bool {
        f.work(0, 55); f.go(toMinute: 55); f.store.refresh()
        guard let first = shown.value.last else { return false }
        f.store.laterBreak(first)
        return true
    }

    private static func returnsByTheClock() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let f = BreakStoreChecks.make() else { return ["could not create isolated preferences"] }
            defer { f.close() }
            let shown = BreakStoreChecks.Box<[BreakPrompt]>([])
            f.store.onBreakDue = { shown.value.append($0); return true }
            guard putOff(f, shown) else { return ["no first reminder"] }
            f.work(55, 65); f.go(toMinute: 65); f.store.refresh()
            let rows = f.store.breakLog.prompts
            expect(shown.value.count == 2 && rows.count == 1 && rows.first?.id == shown.value.last?.id,
                   "put off and back by the clock is one row, got \(rows.count)", &problems)
            expect(rows.first?.laterCount == 1 && rows.first?.shown == at(55), "keeping its Later and first showing", &problems)
            return problems
        }
    }

    private static func walkedAwayCloses() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let f = BreakStoreChecks.make() else { return ["could not create isolated preferences"] }
            defer { f.close() }
            let shown = BreakStoreChecks.Box<[BreakPrompt]>([])
            f.store.onBreakDue = { shown.value.append($0); return true }
            guard putOff(f, shown) else { return ["no first reminder"] }
            // Away well past a rest, then a new run comes due.
            f.go(toMinute: 70); f.store.refresh()
            expect(f.store.breakLog.prompts.first?.outcome == .credited,
                   "the Later is closed once its break is over, got \(String(describing: f.store.breakLog.prompts.first?.outcome))",
                   &problems)
            f.work(150, 205); f.go(toMinute: 205); f.store.refresh()
            let rows = f.store.breakLog.prompts
            expect(shown.value.count == 2 && rows.count == 2, "the next reminder is a second row, got \(rows.count)", &problems)
            expect(rows.last?.id == shown.value.last?.id && rows.last?.laterCount == 0 && rows.last?.shown == at(205),
                   "with its own id, no Laters and its own showing", &problems)
            expect(rows.first?.laterCount == 1 && rows.first?.shown == at(55) && rows.first?.outcome == .credited,
                   "and the old row is as it was, credited", &problems)
            return problems
        }
    }

    private static func restCreditsOpenLater() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let f = BreakStoreChecks.make() else { return ["could not create isolated preferences"] }
            defer { f.close() }
            let shown = BreakStoreChecks.Box<[BreakPrompt]>([])
            f.store.onBreakDue = { shown.value.append($0); return true }
            guard putOff(f, shown) else { return ["no first reminder"] }
            // Too long after the reminder for the break by hand to answer it.
            f.go(toMinute: 70)
            f.store.startBreak(length: 300)
            f.clock.advance(300)
            f.store.endBreak()
            let row = f.store.breakLog.prompts.first
            expect(f.store.breakLog.prompts.count == 1 && row?.outcome == .credited && row?.outcomeAt != nil,
                   "the rest closes the Later as credited, got \(String(describing: row?.outcome))", &problems)
            return problems
        }
    }

    // MARK: - In the log

    private static func closedLaterNotReused() -> [String] {
        var problems: [String] = []
        let directory = SelfTest.scratchDirectory()
        let log = BreakLog(directory: directory)
        let first = entry(shown: at(0))
        log.recordShown(first)
        log.noteLater(for: first.id, at: at(1))
        log.closeLater(of: [.stretchGuard], at: at(2))
        expect(log.prompts.first?.outcome == .later, "another kind's close leaves it", &problems)
        log.closeLater(of: [.main], at: at(3))
        expect(log.prompts.first?.outcome == .credited && log.prompts.first?.outcomeAt == at(3),
               "its own kind's close credits it, got \(String(describing: log.prompts.first?.outcome))", &problems)
        log.closeLater(of: [.main], at: at(4))
        expect(log.prompts.first?.outcomeAt == at(3), "and a closed row is closed once", &problems)
        log.recordShown(entry(shown: at(10)), returning: true)
        expect(log.prompts.count == 2 && log.prompts.last?.laterCount == 0 && log.prompts.last?.shown == at(10),
               "the next is a row of its own, got \(log.prompts.count)", &problems)

        // A phase-1 file whose last row is a Later; the first reminder after
        // an upgrade is not signalled as returning.
        let old = SelfTest.scratchDirectory()
        let phase1 = BreakLog(directory: old)
        let stale = entry(shown: at(0))
        phase1.recordShown(stale)
        phase1.noteLater(for: stale.id, at: at(1))
        let reloaded = BreakLog(directory: old)
        reloaded.recordShown(entry(shown: at(200)))
        expect(reloaded.prompts.count == 2 && reloaded.prompts.last?.laterCount == 0
               && reloaded.prompts.last?.due == at(200).addingTimeInterval(-60),
               "a reminder not known to be returning is its own row, got \(reloaded.prompts.count)", &problems)
        return problems
    }

    // MARK: - The coordinator

    private static func coordinatorHoldsReminder() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let f = BreakStoreChecks.make(prepare: BreakStoreChecks.running) else {
                return ["could not create isolated preferences"]
            }
            defer { f.close() }
            func reaches() -> Bool {
                AppCoordinator.breakReminderReachesScreen(store: f.store, screenLocked: false,
                                                          displayAsleep: false, machineSleeping: false)
            }
            expect(reaches(), "a present person gets it", &problems)
            f.store.noteMachineWake()
            expect(!reaches(), "after a wake it waits for them", &problems)
            f.store.confirmPresence(at: f.clock.value)
            expect(reaches(), "and shows once they are back", &problems)
            f.store.markAway()
            expect(!reaches(), "and not while they are away", &problems)
            expect(!AppCoordinator.breakReminderReachesScreen(store: f.store, screenLocked: true,
                                                              displayAsleep: false, machineSleeping: false),
                   "nor behind a locked screen", &problems)
            return problems
        }
    }

    private static func reminderContentFollowsStore() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let running = BreakStoreChecks.make(prepare: BreakStoreChecks.running),
                  let watching = film() else { return ["could not create isolated preferences"] }
            defer { running.close(); watching.close() }
            var main = BreakPrompt(tier: .cognitive, worked: 50 * 60, appName: nil)
            main.canLater = true
            var answers: [BreakHUDAction] = []
            let offered = AppCoordinator.breakReminderContent(main, store: running.store) { answers.append($0) }
            expect(offered.buttons.map(\.title) == ["Start break", "Later", "Skip"] && offered.mentionsMenuBar,
                   "a store that can begin a break offers Start, got \(offered.buttons.map(\.title))", &problems)
            expect(BreakHUD.spoken(offered).hasSuffix("in the menu bar."), "and says where to take one", &problems)
            let held = AppCoordinator.breakReminderContent(main, store: watching.store) { answers.append($0) }
            expect(held.buttons.map(\.title) == ["Later", "Skip"] && !held.mentionsMenuBar,
                   "a watching store offers Later and Skip only, got \(held.buttons.map(\.title))", &problems)
            expect(!BreakHUD.spoken(held).contains("menu bar"), "and names no menu bar item that is off", &problems)
            held.buttons.first?.action()
            expect(answers == [.later], "its first button is the Later, got \(answers)", &problems)

            // A guard with no Later left has nothing to press: it goes away unanswered.
            var guardPrompt = BreakPrompt(tier: .ultradian, worked: 90 * 60, appName: nil)
            guardPrompt.canLater = false
            watching.store.logShown(guardPrompt, at: at(0))
            let bare = AppCoordinator.breakReminderContent(guardPrompt, store: watching.store) { answers.append($0) }
            expect(bare.buttons.isEmpty && bare.onTimeout != nil, "no buttons, but a timeout that answers", &problems)
            expect(!BreakHUD.spoken(bare).contains("menu bar"), "and no menu bar sentence", &problems)
            bare.onTimeout?()
            expect(watching.store.breakLog.prompts.last?.outcome == .unanswered,
                   "going away is logged as unanswered, got \(String(describing: watching.store.breakLog.prompts.last?.outcome))",
                   &problems)
            return problems
        }
    }

    // MARK: - A start the store refuses

    private static func refusedStartUnanswered() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let watching = film(), let running = BreakStoreChecks.make(prepare: BreakStoreChecks.running) else {
                return ["could not create isolated preferences"]
            }
            defer { watching.close(); running.close() }
            let prompt = BreakPrompt(tier: .cognitive, worked: 50 * 60, appName: nil)
            watching.store.logShown(prompt, at: at(0))
            watching.store.startBreak(from: prompt)
            expect(!watching.store.isOnBreak, "nothing began", &problems)
            expect(watching.store.breakLog.prompts.last?.outcome == .unanswered,
                   "and the reminder is unanswered, got \(String(describing: watching.store.breakLog.prompts.last?.outcome))",
                   &problems)
            let ok = BreakPrompt(tier: .cognitive, worked: 50 * 60, appName: nil)
            running.store.logShown(ok, at: at(0))
            running.store.startBreak(from: ok)
            expect(running.store.breakLog.prompts.last?.outcome == .started, "a start that began is started", &problems)
            return problems
        }
    }
}
