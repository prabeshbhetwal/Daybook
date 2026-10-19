import Foundation

/// What the break HUD says and offers. The copy is pure, so it is checked
/// here without a panel or a screen.
enum BreakSurfaceChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A reminder offers Later only while it may", reminderButtons),
        ("Break's over names the thread, or offers Done without one", breakOverCopy),
        ("Break's over waits until a hand is on the keys", breakOverWaitsForThePerson),
        ("A second click on a break button does nothing", doubleClickAnswersOnce),
        ("A break prompt tells VoiceOver where to answer it", spokenLine),
        ("Break-over sound is on until turned off, and erasing data restores it", breakOverSoundSetting),
        ("A break restored at launch seeds no app use", launchOnBreakSeedsNothing),
        ("The menu bar counts a break down by the minute, then the second", menuBarBreakText),
        ("The menu bar shows a break even with no session", menuBarIdleBreak),
        ("A break is spoken by the minute and reads the same in words and on screen", breakCountdownSpoken),
        ("A break is a Focus mode of its own, with or without a session", breakIsAFocusMode),
        ("Take a break is offered only where a break can begin", takeABreakOnlyWhereItCanBegin),
        ("The menu bar countdown is on until turned off, and erasing data restores it", menuBarCountdownSetting),
    ]

    private static func cognitive(canLater: Bool) -> BreakPrompt {
        var prompt = BreakPrompt(tier: .cognitive, worked: 50 * 60, appName: nil)
        prompt.canLater = canLater
        return prompt
    }

    private static func ultradian(canLater: Bool) -> BreakPrompt {
        var prompt = BreakPrompt(tier: .ultradian, worked: 90 * 60, appName: nil)
        prompt.canLater = canLater
        return prompt
    }

    private static func reminderButtons() -> [String] {
        var problems: [String] = []
        expect(BreakHUDCopy.reminder(cognitive(canLater: true)).buttons.map(\.title) == ["Start break", "Later", "Skip"],
               "full set", &problems)
        expect(BreakHUDCopy.reminder(cognitive(canLater: false)).buttons.map(\.title) == ["Start break", "Skip"],
               "no third Later", &problems)
        expect(BreakHUDCopy.reminder(ultradian(canLater: true)).buttons.map(\.title) == ["Start break", "Remind me in 15 min"],
               "guard has no Skip", &problems)
        expect(BreakHUDCopy.reminder(cognitive(canLater: true)).buttons.map(\.action) == [.start, .later, .skip],
               "each button does what it says", &problems)
        expect(BreakHUDCopy.reminder(ultradian(canLater: true)).buttons.map(\.action) == [.start, .later],
               "the 15-minute button puts the reminder off", &problems)
        return problems
    }

    private static func breakOverCopy() -> [String] {
        var problems: [String] = []
        let named = BreakHUDCopy.breakOver(threadName: "Parser")
        expect(named.title == "Break's over" && named.detail == "Back to Parser?"
                && named.buttons.map(\.title) == ["Resume", "+5 min"],
               "with thread", &problems)
        expect(named.buttons.map(\.action) == [.resume, .extend], "with thread, actions", &problems)
        let bare = BreakHUDCopy.breakOver(threadName: nil)
        expect(bare.buttons.map(\.title) == ["Done", "+5 min"] && bare.detail.isEmpty,
               "without thread", &problems)
        expect(bare.buttons.map(\.action) == [.done, .extend], "without thread, actions", &problems)
        return problems
    }

    private static func breakOverWaitsForThePerson() -> [String] {
        var problems: [String] = []
        expect(!AppCoordinator.breakOverReachesPerson(reachesScreen: true, idleSeconds: 11),
               "11 s without input is not someone at the Mac", &problems)
        expect(AppCoordinator.breakOverReachesPerson(reachesScreen: true, idleSeconds: 2),
               "2 s without input is", &problems)
        expect(AppCoordinator.breakOverReachesPerson(reachesScreen: true, idleSeconds: 10),
               "10 s still counts", &problems)
        expect(!AppCoordinator.breakOverReachesPerson(reachesScreen: false, idleSeconds: 0),
               "a screen nobody can see never gets it", &problems)
        return problems
    }

    private static func doubleClickAnswersOnce() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            var answers = 0
            let hud = BreakHUD()
            let button = BreakHUDButton(title: "+5 min", isPrimary: false) { answers += 1 }
            let content = BreakHUDContent(title: "Break's over", detail: "", symbolName: "cup.and.saucer.fill",
                                          buttons: [button], duration: 12, onTimeout: nil)
            hud.show(content)
            hud.pressed(button)
            hud.pressed(button)
            expect(answers == 1, "two clicks answered \(answers) times", &problems)
            hud.show(content)
            hud.pressed(button)
            expect(answers == 2, "a fresh showing could not be answered", &problems)
            hud.dismiss()
            return problems
        }
    }

    private static func spokenLine() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let withDetail = BreakHUD.spoken(BreakHUDContent(
                title: "Take 5 minutes", detail: "You have been in Xcode for 50m.", symbolName: "",
                buttons: [BreakHUDButton(title: "Skip", isPrimary: false) {}], duration: 12, onTimeout: nil))
            expect(withDetail == "Take 5 minutes. You have been in Xcode for 50m. "
                    + "To answer, open Daybook from the menu bar.",
                   "got \(withDetail)", &problems)
            let noDetail = BreakHUD.spoken(BreakHUDContent(
                title: "Break's over", detail: "", symbolName: "",
                buttons: [BreakHUDButton(title: "Done", isPrimary: true) {}], duration: 12, onTimeout: nil))
            expect(noDetail == "Break's over. To answer, open Daybook from the menu bar.",
                   "an empty detail left a stray stop, got \(noDetail)", &problems)
            return problems
        }
    }

    private static func breakOverSoundSetting() -> [String] {
        var problems: [String] = []
        guard let defaults = MemoryDefaults.suite(named: "fc-selftest-break-over-sound") else {
            return ["could not create isolated defaults"]
        }
        defer { MemoryDefaults.remove(named: "fc-selftest-break-over-sound") }
        let store = PersistenceStore(defaults: defaults)
        expect(store.breakOverSound, "a fresh store plays the sound", &problems)
        let settings = SettingsModel(store: store, isTrackingEnabled: true,
                                     onChange: {}, onTrackingChanged: { _ in })
        settings.breakOverSound = false
        expect(!PersistenceStore(defaults: defaults).breakOverSound,
               "turning it off is saved", &problems)
        expect(!SettingsModel(store: store, isTrackingEnabled: true, onChange: {},
                              onTrackingChanged: { _ in }).breakOverSound,
               "turning it off survives a reload of Settings", &problems)
        settings.breakOverSound = true
        expect(store.breakOverSound, "turning it back on is saved", &problems)
        settings.breakOverSound = false
        store.removeAll()
        expect(store.breakOverSound, "erasing all data restores the default", &problems)
        return problems
    }

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
            f.store.endBreak()
            expect(f.store.focusSurfaceComposition.mode == .running, "and the session is back when it ends", &problems)
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

    private static func launchOnBreakSeedsNothing() -> [String] {
        var problems: [String] = []
        expect(!AppCoordinator.permitsInitialUsageSeed(screenLocked: false, displayAsleep: false, onBreak: true),
               "a break at launch must not seed the frontmost app", &problems)
        expect(AppCoordinator.permitsInitialUsageSeed(screenLocked: false, displayAsleep: false, onBreak: false),
               "an ordinary launch still seeds", &problems)
        return problems
    }
}
