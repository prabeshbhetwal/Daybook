import AppKit

/// An update's countdown waits while a pinned activity or a break's name is
/// being written: the relaunch would lose it. The pinned-activity form is
/// always on screen, so only a change from what it opened with counts.
enum StoreFormHoldChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("An update waits while a pinned activity is changed, not while its form is untouched",
         activityFormHolds),
        ("An update waits while a break's name is being written", breakNameHolds),
    ]

    private static func activityFormHolds() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let store = FixtureFactory.store(for: .firstRun)
            defer { FixtureFactory.cleanUp() }
            let panel = ActivityEditorPanel.shared
            panel.show(.new, store: store)
            // The panel's form takes its ticket when SwiftUI first draws it.
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            let editor = panel.editor
            expect(editor.editingID != nil && !store.holdsUnsavedWork,
                   "the blank pin form held the update (form set up \(editor.editingID != nil))", &problems)
            editor.name = "Reading pap"
            expect(store.holdsUnsavedWork, "a pin being named did not hold the update", &problems)
            editor.beginNew()
            expect(!store.holdsUnsavedWork, "a form set up afresh, as after Pin, still held the update", &problems)
            let pinned = SavedActivity(id: UUID(), name: "Reviews", workType: .admin)
            editor.edit(pinned)
            expect(!store.holdsUnsavedWork, "a pin opened for editing held the update unchanged", &problems)
            editor.workType = .meetings
            expect(store.holdsUnsavedWork, "a pin's changed category did not hold the update", &problems)
            panel.close()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            expect(!store.holdsUnsavedWork, "the closed panel still held the update", &problems)
            return problems
        }
    }

    private static func breakNameHolds() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let store = FixtureFactory.store(for: .firstRun)
            defer { FixtureFactory.cleanUp() }
            let draft = BreakNameDraft()
            expect(!store.holdsUnsavedWork, "nothing open held the update", &problems)
            draft.begin(with: "", in: store)
            expect(store.holdsUnsavedWork, "a break's name field did not hold the update", &problems)
            draft.text = "dinner"
            draft.isEditing = false
            expect(!store.holdsUnsavedWork, "a closed name field still held the update", &problems)
            return problems
        }
    }
}
