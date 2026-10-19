import Foundation

/// How a break shows: the menu bar's cup and countdown, the Focus mode that
/// replaces the hero while one runs, and where Take a break is offered. The
/// copy of the HUD and the settings that tune it are `BreakSurfaceChecks`'.
enum BreakDisplayChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The menu bar counts a break down by the minute, then the second", menuBarBreakText),
        ("The menu bar shows a break even with no session", menuBarIdleBreak),
        ("A break is spoken by the minute and reads the same in words and on screen", breakCountdownSpoken),
        ("A break is a Focus mode of its own, with or without a session", breakIsAFocusMode),
        ("Take a break is offered only where a break can begin", takeABreakOnlyWhereItCanBegin),
        ("The menu bar countdown is on until turned off, and erasing data restores it", menuBarCountdownSetting),
        ("A paused or running session on a break shows no session time beside the cup", menuBarBreakDropsSessionTime),
        ("The Take a break menu offers 5, 10, 15 and 30 minutes, each spoken as such", takeBreakMenuChoices),
        ("The hero's Take a break and the Session menu's item agree in every mode", takeBreakHeroAndMenuAgree),
    ]

    private static func menuBarBreakText() -> [String] {
        var problems: [String] = []
        expect(MenuBarDisplay.breakText(remaining: 299) == "5m", "rounds up minutes", &problems)
        expect(MenuBarDisplay.breakText(remaining: 61) == "2m" && MenuBarDisplay.breakText(remaining: 60) == "60s",
               "seconds in the last minute", &problems)
        expect(MenuBarDisplay.breakText(remaining: -30) == "Over" && MenuBarDisplay.breakText(remaining: -200) == "+3m",
               "overtime", &problems)
        expect(MenuBarDisplay.breakText(remaining: 300) == "5m" && MenuBarDisplay.breakText(remaining: 0) == "Over"
               && MenuBarDisplay.breakText(remaining: -60) == "+1m", "the edges of each rule", &problems)
        return problems
    }

    private static func menuBarIdleBreak() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let f = BreakStoreChecks.make() else { return ["could not create isolated preferences"] }
            defer { f.close() }
            expect(!MenuBarDisplay(f.store).isOnBreak, "no break, no cup", &problems)
            f.store.startBreak()
            var display = MenuBarDisplay(f.store)
            expect(display.isOnBreak && display.breakText == "5m",
                   "an idle store on a break shows 5m, got \(display.breakText ?? "nil")", &problems)
            expect(display.time == nil, "the frozen session time is not shown beside the cup", &problems)
            f.persistence.menuBarShowsBreakCountdown = false
            f.store.refresh()
            display = MenuBarDisplay(f.store)
            expect(display.isOnBreak && display.breakText == nil,
                   "with the countdown off the cup stays and the time goes", &problems)
            return problems
        }
    }

    private static func breakCountdownSpoken() -> [String] {
        var problems: [String] = []
        func label(_ remaining: TimeInterval) -> String {
            MenuBarDisplay(state: .idle, elapsed: 0, needsAttention: false,
                           goal: GoalProgress(goal: 14_400, achieved: 0, typical: nil),
                           showsTime: true, breakRemaining: remaining).accessibilityLabel
        }
        expect(label(299).contains("On a break, 5 minutes left"), "minutes left, got \(label(299))", &problems)
        expect(label(299) == label(241) && label(45) == label(5),
               "the label holds still inside a minute", &problems)
        expect(label(45).contains("On a break, under a minute left"), "the last minute", &problems)
        expect(label(100).contains("2 minutes left") && label(60.5).contains("2 minutes left"),
               "rounds up like the text", &problems)
        expect(label(-30).contains("Break over") && !label(-30).contains("On a break"), "just over", &problems)
        expect(label(-200).contains("Break over by 3 minutes"), "overtime, got \(label(-200))", &problems)
        expect(label(-70).contains("Break over by 1 minute") && !label(-70).contains("1 minutes"),
               "one minute is singular", &problems)
        expect(BreakCountdown.cardText(remaining: 299) == "5m left" && BreakCountdown.cardText(remaining: 45) == "45s left",
               "the card counts down like the menu bar", &problems)
        expect(BreakCountdown.cardText(remaining: -10) == "Break over"
               && BreakCountdown.cardText(remaining: -200) == "+3m over", "and counts overtime", &problems)
        return problems
    }

    private static func breakIsAFocusMode() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            func mode(_ state: SessionState, auto: Bool = false, onBreak: Bool = true) -> FocusSurfaceComposition {
                FocusSurfaceComposition(state: state, hasPendingDecision: false, isAutomatic: auto, isOnBreak: onBreak)
            }
            expect(mode(.idle).mode == .onBreak && mode(.paused(reason: .onBreak)).mode == .onBreak
                   && mode(.running).mode == .onBreak, "idle, paused and running all show the break", &problems)
            expect(mode(.running, onBreak: false).mode == .running, "no break, no break mode", &problems)
            expect(FocusSurfaceMode(state: .paused(reason: .onBreak)) == .onBreak, "the pause reason maps to it", &problems)
            expect(FocusSurfaceMode.onBreak.primaryPrompt == "On a break" && FocusSurfaceMode.onBreak.primaryAction == nil,
                   "named, and with no Pause or Resume of its own", &problems)
            expect(!mode(.paused(reason: .onBreak), auto: true).showsAutomaticSessionControls,
                   "no automatic-session form on a break card", &problems)
            guard let f = BreakStoreChecks.make(prepare: BreakStoreChecks.running) else {
                return problems + ["could not create isolated preferences"]
            }
            defer { f.close() }
            f.store.startBreak()
            expect(f.store.focusSurfaceComposition.mode == .onBreak, "the store composes a break", &problems)
            expect(FocusHero.detail(for: .onBreak, store: f.store) == nil
                   && FocusHero.detail(for: .onBreak, store: f.store, isStrip: true) == nil,
                   "nothing is said under the bar for a break; the row says it", &problems)
            expect(!FocusHero.underlineHasContent(f.store), "so the line under the bar is folded away", &problems)
            f.store.endBreak()
            expect(f.store.focusSurfaceComposition.mode == .running, "and the session is back when it ends", &problems)
            guard let idle = BreakStoreChecks.make() else { return problems + ["could not create isolated preferences"] }
            defer { idle.close() }
            idle.store.startBreak()
            expect(!FocusHero.underlineHasContent(idle.store), "and with no session too", &problems)
            return problems
        }
    }

    private static func takeABreakOnlyWhereItCanBegin() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let idle = BreakStoreChecks.make(),
                  let running = BreakStoreChecks.make(prepare: BreakStoreChecks.running) else {
                return ["could not create isolated preferences"]
            }
            defer { idle.close(); running.close() }
            expect(idle.store.canTakeBreak && running.store.canTakeBreak, "idle and running may", &problems)
            running.store.startBreak()
            expect(!running.store.canTakeBreak, "not while one is under way", &problems)
            running.store.endBreak()
            running.store.markAway()
            expect(running.store.isAway && !running.store.canTakeBreak,
                   "not while away, as the engine refuses", &problems)
            return problems
        }
    }

    /// The display must not carry the paused session's frozen minutes beside
    /// the cup. An idle store has no time to show either way, so only a
    /// session makes this check mean anything.
    private static func menuBarBreakDropsSessionTime() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let goal = GoalProgress(goal: 14_400, achieved: 0, typical: nil)
            let paused = MenuBarDisplay(state: .paused(reason: .onBreak), elapsed: 750, needsAttention: false,
                                        goal: goal, showsTime: true, breakRemaining: 120)
            expect(paused.isOnBreak && paused.time == nil && paused.breakText == "2m",
                   "a paused session on a break shows the countdown, not 12m", &problems)
            let hidden = MenuBarDisplay(state: .paused(reason: .onBreak), elapsed: 750, needsAttention: false,
                                        goal: goal, showsTime: true, breakRemaining: 120,
                                        showsBreakCountdown: false)
            expect(hidden.isOnBreak && hidden.time == nil && hidden.breakText == nil,
                   "with the countdown off, still no session time", &problems)
            let beforeBreak = MenuBarDisplay(state: .running, elapsed: 750, needsAttention: false,
                                             goal: goal, showsTime: true)
            expect(beforeBreak.time != nil && !beforeBreak.isOnBreak,
                   "without a break the session time is shown", &problems)
            guard let f = BreakStoreChecks.make(prepare: BreakStoreChecks.running) else {
                return problems + ["could not create isolated preferences"]
            }
            defer { f.close() }
            expect(MenuBarDisplay(f.store).time != nil, "a running store shows its time", &problems)
            f.store.startBreak()
            let display = MenuBarDisplay(f.store)
            expect(display.isOnBreak && display.time == nil && display.breakText == "5m",
                   "a running session that starts a break shows the cup's time only, got \(display.time ?? "nil")",
                   &problems)
            return problems
        }
    }

    private static func takeBreakMenuChoices() -> [String] {
        var problems: [String] = []
        let options = BreakChoice.options
        expect(options.map(\.length) == BreakLength.choices && options.map(\.length) == [300, 600, 900, 1_800],
               "the menu offers BreakLength.choices", &problems)
        expect(options.map(\.title) == ["5 minutes", "10 minutes", "15 minutes", "30 minutes"],
               "titled in minutes, got \(options.map(\.title))", &problems)
        expect(options.map(\.spoken) == ["Take a 5-minute break", "Take a 10-minute break",
                                         "Take a 15-minute break", "Take a 30-minute break"],
               "and spoken, got \(options.map(\.spoken))", &problems)
        expect(options.first?.length == BreakLength.standard, "the first is the default a click takes", &problems)
        return problems
    }

    /// One question, asked by both: the hero's button is drawn when
    /// `offersTakeBreak`, and the Session menu's item is enabled by it.
    private static func takeBreakHeroAndMenuAgree() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            func offers(_ state: SessionState, decision: Bool = false, onBreak: Bool = false) -> Bool {
                FocusSurfaceComposition(state: state, hasPendingDecision: decision, isAutomatic: false,
                                        isOnBreak: onBreak, canTakeBreak: true).offersTakeBreak
            }
            expect(offers(.idle) && offers(.running), "idle and running offer it", &problems)
            expect(offers(.paused(reason: .manual)) && offers(.paused(reason: .distractionApp(bundleID: "com.test"))),
                   "so do a pause by hand and a pause by a break app", &problems)
            expect(!offers(.paused(reason: .watching)), "watching does not, in the hero or the menu", &problems)
            expect(!offers(.running, decision: true) && !offers(.awaitingUserDecision(away: 1_200, lastApp: "Xcode")),
                   "an away question waiting does not", &problems)
            expect(!offers(.paused(reason: .onBreak), onBreak: true) && !offers(.idle, onBreak: true),
                   "a break under way offers End Break, not another", &problems)
            expect(!FocusSurfaceComposition(state: .idle, hasPendingDecision: false, isAutomatic: false,
                                            canTakeBreak: false).offersTakeBreak,
                   "and nowhere the engine would refuse", &problems)

            guard let running = BreakStoreChecks.make(prepare: BreakStoreChecks.running) else {
                return problems + ["could not create isolated preferences"]
            }
            defer { running.close() }
            func agree(_ label: String, expecting offered: Bool, enabled: Bool, in store: SessionStore? = nil) {
                let store = store ?? running.store
                let snapshot = SessionCommandState.Snapshot(store)
                let hero = store.focusSurfaceComposition.offersTakeBreak
                expect(hero == offered, "\(label): the hero offers \(offered), got \(hero)", &problems)
                expect(snapshot.takeBreakEnabled == enabled,
                       "\(label): the menu item is enabled=\(enabled), got \(snapshot.takeBreakEnabled)", &problems)
            }
            agree("running", expecting: true, enabled: true)
            running.store.togglePause()
            agree("paused by hand", expecting: true, enabled: true)
            running.store.togglePause()
            running.store.startBreak()
            agree("on a break", expecting: false, enabled: true)
            running.store.endBreak()
            running.store.markAway()
            agree("away", expecting: false, enabled: false)
            // The engine would take a break from a film, but the hero shows no
            // button there, so the menu must not offer one either.
            guard let film = BreakStoreChecks.make(prepare: { engine, clock in
                BreakStoreChecks.running(engine, clock)
                engine.transition(on: .watchingObserved(seconds: 20 * 60))
            }) else { return problems + ["could not create isolated preferences"] }
            defer { film.close() }
            expect(film.store.state == .paused(reason: .watching), "the fixture is watching", &problems)
            expect(film.store.canTakeBreak, "the engine would accept a break from a film", &problems)
            agree("watching", expecting: false, enabled: false, in: film.store)
            guard let idle = BreakStoreChecks.make() else { return problems + ["could not create isolated preferences"] }
            defer { idle.close() }
            expect(SessionCommandState.Snapshot(idle.store).takeBreakEnabled
                   == idle.store.focusSurfaceComposition.offersTakeBreak
                   && idle.store.focusSurfaceComposition.offersTakeBreak, "idle: both offer it", &problems)
            return problems
        }
    }

    private static func menuBarCountdownSetting() -> [String] {
        var problems: [String] = []
        guard let defaults = MemoryDefaults.suite(named: "fc-selftest-menu-bar-countdown") else {
            return ["could not create isolated defaults"]
        }
        defer { MemoryDefaults.remove(named: "fc-selftest-menu-bar-countdown") }
        let store = PersistenceStore(defaults: defaults)
        expect(store.menuBarShowsBreakCountdown, "a fresh store shows the countdown", &problems)
        let settings = SettingsModel(store: store, isTrackingEnabled: true,
                                     onChange: {}, onTrackingChanged: { _ in })
        settings.menuBarShowsBreakCountdown = false
        expect(!PersistenceStore(defaults: defaults).menuBarShowsBreakCountdown,
               "turning it off is saved", &problems)
        expect(!SettingsModel(store: store, isTrackingEnabled: true, onChange: {},
                              onTrackingChanged: { _ in }).menuBarShowsBreakCountdown,
               "turning it off survives a reload of Settings", &problems)
        store.removeAll()
        expect(store.menuBarShowsBreakCountdown, "erasing all data restores the default", &problems)
        return problems
    }
}
