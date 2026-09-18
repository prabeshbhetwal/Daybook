import Foundation
import SwiftUI
import AppKit

/// The pinned activity list: short, ordered, one per name, kept apart from
/// recents, and reachable from a floating panel.
enum SavedActivityChecks {
    static let tests: [(String, () -> [String])] = [
        ("Saved activities normalise, dedupe, cap and keep their order", normalisation),
        ("The store pins, edits, reorders and removes activities and hides them from recents", storeEdits),
        ("The activity panel opens from the menu and closes", panel)
    ]

    private static func normalisation() -> [String] {
        var failures: [String] = []
        let items = (1...10).map { SavedActivity(name: "Task \($0)", workType: .deepWork) }
            + [SavedActivity(name: "  task 1 ", workType: .admin),
               SavedActivity(name: "   ", workType: .deepWork),
               SavedActivity(name: "Lunch", workType: .breakTime)]
        let normalised = SavedActivities.normalised(items)
        if normalised.count != SavedActivities.limit {
            failures.append("The list was not capped at \(SavedActivities.limit): \(normalised.count)")
        }
        if normalised.map(\.name) != (1...8).map({ "Task \($0)" }) {
            failures.append("Order, blanks, rest or duplicates were mishandled: \(normalised.map(\.name))")
        }
        let recents = SavedActivities.recents(
            [QuickStart(id: "a", name: "Task 1", workType: .deepWork),
             QuickStart(id: "b", name: "Reading", workType: .learning),
             QuickStart(id: "c", name: "TASK 2", workType: .admin)] + (0..<10).map {
                QuickStart(id: "r\($0)", name: "Recent \($0)", workType: .deepWork) },
            excluding: normalised)
        if recents.map(\.name) != ["Reading", "Recent 0", "Recent 1", "Recent 2", "Recent 3", "Recent 4"] {
            failures.append("Recents did not exclude pinned names or cap at six: \(recents.map(\.name))")
        }
        let retired = SavedActivity(name: "Calls", workType: WorkType(rawValue: "custom.gone"))
        if retired.startableWorkType != .deepWork {
            failures.append("A retired category did not fall back to Deep work on pick")
        }
        return failures
    }

    private static func storeEdits() -> [String] {
        var failures: [String] = []
        let store = FixtureFactory.store(for: .firstRun)
        defer { FixtureFactory.cleanUp() }
        store.refresh()
        if !store.savedActivities.isEmpty { failures.append("A fresh store had pinned activities") }
        let research = SavedActivity(name: "Research", workType: .learning)
        guard store.saveActivity(research) else { return failures + ["Pinning failed"] }
        if store.saveActivity(SavedActivity(name: "research", workType: .deepWork)) {
            failures.append("A second pin with the same name was accepted")
        }
        _ = store.saveActivity(SavedActivity(name: "Coding", workType: .deepWork))
        if store.savedActivities.map(\.name) != ["Research", "Coding"] {
            failures.append("Pins were not kept in order: \(store.savedActivities.map(\.name))")
        }
        store.moveSavedActivity(id: research.id, up: false)
        if store.savedActivities.map(\.name) != ["Coding", "Research"] {
            failures.append("Moving a pin down did not reorder")
        }
        _ = store.saveActivity(SavedActivity(id: research.id, name: "Reading papers", workType: .learning))
        if store.savedActivities.last?.name != "Reading papers" || store.savedActivities.count != 2 {
            failures.append("Editing a pin did not replace it in place")
        }
        store.engine.store.rememberActivity(name: "Coding", workType: .deepWork)
        store.engine.store.rememberActivity(name: "Browsing", workType: .deepWork)
        store.refresh()
        if store.recentActivities.contains(where: { $0.name == "Coding" })
            || !store.recentActivities.contains(where: { $0.name == "Browsing" }) {
            failures.append("Recents did not hide a pinned name: \(store.recentActivities.map(\.name))")
        }
        store.chooseActivity(store.savedActivities[1])
        if store.intent != "Reading papers" || store.workType != .learning {
            failures.append("Choosing a pin did not fill both the name and the category")
        }
        store.removeSavedActivity(id: research.id)
        if store.savedActivities.map(\.name) != ["Coding"] {
            failures.append("Removing a pin failed")
        }
        // A second store on the same preferences sees the same list.
        if store.engine.store.savedActivities.map(\.name) != ["Coding"] {
            failures.append("Pins did not persist")
        }
        return failures
    }

    private static func panel() -> [String] {
        var failures: [String] = []
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .firstRun)
            defer { FixtureFactory.cleanUp() }
            let panel = ActivityEditorPanel.shared
            panel.show(.new, store: store)
            if !panel.isVisible || panel.title != "Pin activity" {
                failures.append("Pin activity… did not open the panel on a blank form")
            }
            panel.show(.edit, store: store)
            if panel.title != "Pinned activities" {
                failures.append("Edit pinned… did not retitle the open panel")
            }
            panel.close()
            if panel.isVisible { failures.append("The panel did not close") }
        }
        return failures
    }
}
