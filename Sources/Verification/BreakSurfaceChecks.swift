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
                    + "You can also take or end a break from Daybook in the menu bar.",
                   "got \(withDetail)", &problems)
            let noDetail = BreakHUD.spoken(BreakHUDContent(
                title: "Break's over", detail: "", symbolName: "",
                buttons: [BreakHUDButton(title: "Done", isPrimary: true) {}], duration: 12, onTimeout: nil))
            expect(noDetail == "Break's over. You can also take or end a break from Daybook in the menu bar.",
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

    private static func launchOnBreakSeedsNothing() -> [String] {
        var problems: [String] = []
        expect(!AppCoordinator.permitsInitialUsageSeed(screenLocked: false, displayAsleep: false, onBreak: true),
               "a break at launch must not seed the frontmost app", &problems)
        expect(AppCoordinator.permitsInitialUsageSeed(screenLocked: false, displayAsleep: false, onBreak: false),
               "an ordinary launch still seeds", &problems)
        return problems
    }
}
