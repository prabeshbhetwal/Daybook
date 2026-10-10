import SwiftUI

/// The ways into Ask Daybook besides ⌘K, which only someone who already
/// knows it can find: the bar's button, the Settings row and its switch, and
/// the questions an empty sheet offers.
enum AskEntryChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The bar shows Ask beside Settings when Ask can run here and its switch is on", barShowsAsk),
        ("Ask's toolbar switch is on until turned off, and is saved", switchIsSaved),
        ("Settings finds Ask by its words and hands over to the Ask sheet", settingsReachAsk),
        ("An empty Ask sheet offers questions, and asking one asks exactly it", examplesAskThemselves),
    ]

    private static func barShowsAsk() -> [String] {
        var problems: [String] = []
        expect(AskChromeButton.isShown(switchOn: true, offered: true), "on and offered, Ask is hidden", &problems)
        expect(!AskChromeButton.isShown(switchOn: false, offered: true), "switched off, Ask still shows", &problems)
        expect(!AskChromeButton.isShown(switchOn: true, offered: false),
               "a Mac that cannot run Ask is shown a way into it", &problems)
        let store = FixtureFactory.insightsStore(withEvidence: true)
        defer { FixtureFactory.cleanUp() }
        MainActor.assumeIsolated {
            let navigation = MainWindowModel(store: store)
            let shown = StoryWorkspaceChecks.renderFrame(
                StoryChromeBar(store: store, navigation: navigation, showsAsk: true), width: 1_160, height: 60)
            expect(shown.evidence.contains(.askButtonWithWord),
                   "a wide bar draws Ask with its word: \(shown.evidence.map(\.rawValue).sorted())", &problems)
            expect(shown.evidence.contains(.storyChromeControls),
                   "Ask pushed the session controls out of the bar", &problems)
            let hidden = StoryWorkspaceChecks.renderFrame(
                StoryChromeBar(store: store, navigation: navigation, showsAsk: false), width: 1_160, height: 60)
            expect(!hidden.evidence.contains(.askButton) && !hidden.evidence.contains(.askButtonWithWord),
                   "a bar without Ask drew it: \(hidden.evidence.map(\.rawValue).sorted())", &problems)
            navigation.open(tab: .review)
            let history = StoryWorkspaceChecks.renderFrame(
                StoryChromeBar(store: store, navigation: navigation, showsAsk: true), width: 1_160, height: 60)
            expect(history.evidence.contains(.askButtonWithWord) || history.evidence.contains(.askButton),
                   "History's bar has no Ask: \(history.evidence.map(\.rawValue).sorted())", &problems)
        }
        return problems
    }

    private static func switchIsSaved() -> [String] {
        var problems: [String] = []
        let suite = "fc-selftest-askentry-\(UUID().uuidString)"
        guard let defaults = MemoryDefaults.suite(named: suite) else { return ["could not make a preferences suite"] }
        defer { MemoryDefaults.remove(named: suite) }
        let store = PersistenceStore(defaults: defaults)
        expect(store.showsAskButton, "a new install hides the Ask button", &problems)
        MainActor.assumeIsolated {
            let model = SettingsModel(store: store, isTrackingEnabled: true, onChange: {}, onTrackingChanged: { _ in })
            model.showsAskButton = false
            expect(!PersistenceStore(defaults: defaults).showsAskButton, "turning Ask off was not saved", &problems)
            model.showsAskButton = true
            expect(PersistenceStore(defaults: defaults).showsAskButton, "turning Ask back on was not saved", &problems)
            expect(SettingsControlKey.askButton.modelKeyPath == \SettingsModel.showsAskButton,
                   "the Settings control does not name the switch", &problems)
        }
        defaults.set("yes", forKey: "fc.showsAskButton")
        expect(PersistenceStore(defaults: defaults).showsAskButton, "a malformed value hid Ask", &problems)
        return problems
    }

    private static func settingsReachAsk() -> [String] {
        var problems: [String] = []
        for words in ["Apple Intelligence", "Command-K", "Show Ask in the toolbar", "Open Ask"] {
            let found = SettingsSection.matching(words).map(\.title)
            expect(found.contains("General"), "searching “\(words)” finds \(found), not General", &problems)
        }
        let store = FixtureFactory.insightsStore(withEvidence: false)
        defer { FixtureFactory.cleanUp() }
        MainActor.assumeIsolated {
            let navigation = MainWindowModel(store: store)
            var opened = 0
            let settings = SettingsModel(store: store.engine.store, isTrackingEnabled: true, onChange: {},
                                         onTrackingChanged: { _ in },
                                         openAsk: { opened += 1; navigation.openAsk() })
            expect(settings.canOpenAsk, "Settings offers no way into Ask", &problems)
            navigation.openSheet(.settings)
            settings.openAsk()
            expect(opened == 1, "Open Ask called its handler \(opened) times", &problems)
            expect(navigation.sheet == .ask && navigation.askModel != nil,
                   "Open Ask left the sheet at \(String(describing: navigation.sheet))", &problems)
            expect(!SettingsModel(store: store.engine.store, isTrackingEnabled: true, onChange: {},
                                 onTrackingChanged: { _ in }).canOpenAsk,
                   "a Settings with no app behind it offers Open Ask", &problems)
        }
        return problems
    }

    private static func examplesAskThemselves() -> [String] {
        var problems: [String] = []
        let examples = AskModel.examples
        expect(examples.count == 4 && Set(examples).count == 4 && examples.allSatisfy { $0.hasSuffix("?") },
               "the sheet offers \(examples)", &problems)
        guard #available(macOS 26, *) else { return problems }
        problems += AskThreadChecks.withModel { _, model, problems in
            var asked: [String] = []
            model.responder = { question, show in
                asked.append(question)
                show("The most focused day was Tue 17 Oct.")
            }
            model.ask(examples[0])
            InstalledAppCatalog.turnRunLoop(until: { !model.isAnswering }, timeout: 5)
            expect(asked == [examples[0]], "the example asked \(asked)", &problems)
            expect(model.question == examples[0], "the sheet shows the question “\(model.question)”", &problems)
        }
        return problems
    }
}
