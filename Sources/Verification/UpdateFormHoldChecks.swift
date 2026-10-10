import AppKit

/// An update's countdown waits while a rule or category form is open, in
/// Settings or in the floating category panel: the relaunch would lose its
/// draft. It used to ask only the window's notes, answer and naming.
enum UpdateFormHoldChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("An update waits while a rule or category form in Settings is open", settingsFormsHold),
        ("An update waits while the category panel is open, and not once it closes", panelFormHolds),
    ]

    private static func settingsFormsHold() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let (settings, cleanUp) = settingsModel()
            defer { cleanUp() }
            let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            defer { FixtureFactory.cleanUp() }
            func busy() -> Bool { AppUpdater.wouldLoseWork(store: store, settings: settings) }
            let drafts = SettingsDrafts.of(settings)
            expect(!busy(), "nothing open held the update", &problems)
            drafts.rule.beginNew()
            drafts.rule.name = "Half-written rule"
            expect(busy(), "a new rule being written did not hold the update", &problems)
            drafts.rule.close()
            expect(!busy(), "a cancelled rule form still held the update", &problems)
            drafts.category.edit(WorkTypeCatalog.shared.definition(for: .meetings))
            expect(busy(), "a category being changed did not hold the update", &problems)
            drafts.category.close()
            expect(!busy(), "a closed category form still held the update", &problems)
            return problems
        }
    }

    private static func panelFormHolds() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let (settings, cleanUp) = settingsModel()
            defer { cleanUp() }
            let panel = CategoryEditorPanel.shared
            panel.show(.new, model: settings)
            // The panel's form takes its ticket when SwiftUI first draws it.
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            expect(panel.isVisible && settings.holdsOpenForm,
                   "the open category panel did not hold the update (visible \(panel.isVisible))", &problems)
            panel.close()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            expect(!settings.holdsOpenForm, "the closed category panel still held the update", &problems)
            return problems
        }
    }

    /// A settings model over throwaway preferences, and the closure that
    /// removes them.
    @MainActor private static func settingsModel() -> (SettingsModel, () -> Void) {
        let suite = "fc-selftest-update-forms-\(UUID().uuidString)"
        let store = PersistenceStore(defaults: MemoryDefaults.suite(named: suite)!)
        let settings = SettingsModel(store: store, isTrackingEnabled: true,
                                     onChange: {}, onTrackingChanged: { _ in })
        return (settings, { MemoryDefaults.remove(named: suite) })
    }
}
