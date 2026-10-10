import Foundation

/// Where Ask opens, sheet or side panel: the saved choice, its place in
/// Settings, and what changing it does to a panel that is open.
enum AskPanelChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Ask opens as a sheet until the side panel is chosen, and the choice is saved", placementSavedDefaultSheet),
        ("A panel left open when the choice becomes the sheet closes as Settings closes", placementChangeClosesPanelWhenSettingsClose),
    ]

    private static func placementSavedDefaultSheet() -> [String] {
        var problems: [String] = []
        let suite = "fc-selftest-askpanel-\(UUID().uuidString)"
        guard let defaults = MemoryDefaults.suite(named: suite) else { return ["could not make a preferences suite"] }
        defer { MemoryDefaults.remove(named: suite) }
        let store = PersistenceStore(defaults: defaults)
        expect(store.askPlacement == .sheet, "a new install opens Ask as \(store.askPlacement)", &problems)
        MainActor.assumeIsolated {
            let model = SettingsModel(store: store, isTrackingEnabled: true, onChange: {}, onTrackingChanged: { _ in })
            model.askPlacement = .panel
            expect(PersistenceStore(defaults: defaults).askPlacement == .panel,
                   "choosing the side panel was not saved", &problems)
            model.askPlacement = .sheet
            expect(PersistenceStore(defaults: defaults).askPlacement == .sheet,
                   "choosing the sheet again was not saved", &problems)
            expect(SettingsControlKey.askPlacement.modelKeyPath == \SettingsModel.askPlacement,
                   "the Settings control does not name the placement", &problems)
        }
        for unreadable: Any in ["sideways", "", 7, true] {
            defaults.set(unreadable, forKey: "fc.askPlacement")
            expect(PersistenceStore(defaults: defaults).askPlacement == .sheet,
                   "the stored value \(unreadable) opened Ask as \(PersistenceStore(defaults: defaults).askPlacement)",
                   &problems)
        }
        store.askPlacement = .panel
        store.removeAll()
        expect(store.askPlacement == .sheet, "resetting every setting kept the side panel", &problems)
        let found = SettingsSection.matching("Side panel").map(\.title)
        expect(found.contains("General"), "searching “Side panel” finds \(found), not General", &problems)
        for words in ["Open Ask in", "Inspector", "Sidebar"] {
            let found = SettingsSection.matching(words).map(\.title)
            expect(found.contains("General"), "searching “\(words)” finds \(found), not General", &problems)
        }
        return problems
    }

    private static func placementChangeClosesPanelWhenSettingsClose() -> [String] {
        AskLookupChecks.withFixture { f, problems in
            MainActor.assumeIsolated { panelFollowsPlacement(f, &problems) }
        }
    }

    @MainActor private static func panelFollowsPlacement(_ f: AskLookupChecks.Fixture, _ problems: inout [String]) {
        let navigation = MainWindowModel(store: f.store)
        let settings = SettingsModel(store: f.engine.store, isTrackingEnabled: true, onChange: {},
                                     onTrackingChanged: { _ in })
        settings.askPlacement = .panel
        navigation.openAsk()
        expect(navigation.askPanelOpen, "the panel did not open", &problems)

        navigation.openSheet(.settings)
        expect(navigation.askPanelOpen, "Settings opening closed the panel", &problems)
        settings.askPlacement = .sheet
        expect(navigation.askPanelOpen, "the panel closed before Settings did", &problems)
        navigation.closeSheet()
        expect(!navigation.askPanelOpen && navigation.sheet == nil,
               "the panel is \(navigation.askPanelOpen ? "still open" : "closed") after Settings closed", &problems)
        navigation.openAsk()
        expect(navigation.sheet == .ask && !navigation.askPanelOpen,
               "the next ⌘K gave sheet \(String(describing: navigation.sheet)), panel \(navigation.askPanelOpen)", &problems)
        navigation.closeSheet()

        // Keeping the side panel keeps it open.
        settings.askPlacement = .panel
        navigation.openAsk()
        navigation.openSheet(.settings)
        navigation.closeSheet()
        expect(navigation.askPanelOpen, "closing Settings closed a panel that is still the choice", &problems)

        // Closing a sheet that has nothing to do with Ask never touches a closed panel.
        navigation.closeAskPanel()
        navigation.openSheet(.awards)
        navigation.closeSheet()
        expect(!navigation.askPanelOpen, "closing Awards opened the panel", &problems)
    }
}
