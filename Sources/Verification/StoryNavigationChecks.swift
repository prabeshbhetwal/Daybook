import Foundation
import SwiftUI

enum StoryNavigationChecks {
    static let tests: [(String, () -> [String])] = [
        ("Story commands present the requested surface, including repeat routes", routes),
        ("Historical Story routes select canonical evidence and clear stale period detail", historicalEvidence)
    ]

    private static func routes() -> [String] {
        MainActor.assumeIsolated {
            var failures: [String] = []
            let navigation = MainWindowModel(storyScope: .month)
            navigation.open(tab: .insights)
            if navigation.sheet != .insights {
                failures.append("Insights command changed a legacy tab but did not present Insights")
            }
            navigation.open(tab: .settings)
            if navigation.sheet != .settings {
                failures.append("Popover Settings did not replace the current sheet with Settings")
            }
            navigation.closeSheet()
            navigation.open(tab: .settings)
            if navigation.sheet != .settings {
                failures.append("Opening the same Settings route a second time did not present it")
            }
            navigation.openToday(date: Date(timeIntervalSince1970: 1_782_000_000))
            if navigation.sheet != nil || navigation.storyScope != .day {
                failures.append("A named day route did not dismiss its sheet and show Day")
            }
            return failures
        }
    }

    private static func historicalEvidence() -> [String] {
        MainActor.assumeIsolated {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("fc-story-route-\(UUID().uuidString)", isDirectory: true)
            let suite = "fc.story.route.\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: suite) else {
                return ["Could not create isolated route preferences"]
            }
            defer {
                defaults.removePersistentDomain(forName: suite)
                try? FileManager.default.removeItem(at: directory)
            }
            let calendar = Calendar.current
            let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 12))!
            let chosen = calendar.date(from: DateComponents(year: 2026, month: 8, day: 21, hour: 15))!
            let archive = SessionArchive(directory: directory, now: { now })
            archive.append(SessionRecord(name: "Historical parser work", workType: .deepWork,
                                         start: chosen, end: chosen.addingTimeInterval(1_800),
                                         workSeconds: 1_800))
            let usage = AppUsageArchive(directory: directory, now: { now })
            let engine = SessionEngine(store: PersistenceStore(defaults: defaults), archive: archive,
                                       ownBundleID: "fc.route.test", schedulesDwell: false, now: { now })
            let store = SessionStore(engine: engine, now: { now })
            let tracker = AppUsageTracker(archive: usage, ownBundleID: "fc.route.test",
                                          idle: .disabled, now: { now })
            store.attach(tracker: tracker, usage: usage)
            let navigation = MainWindowModel(storyScope: .month)
            // A request can arrive before the window is constructed.
            navigation.openStoryDay(chosen)
            navigation.connect(to: store)
            var failures: [String] = []
            func checkDay() {
                if !calendar.isDate(store.selectedDay, inSameDayAs: chosen) {
                    failures.append("Opening 21 August displayed \(store.selectedDay), not the selected day")
                }
                let names = store.daySessions.compactMap { entry -> String? in
                    if case .session(let session) = entry { return session.name }; return nil
                }
                if names != ["Historical parser work"] {
                    failures.append("Historical route did not load its own session evidence: \(names)")
                }
            }
            checkDay()
            navigation.open(tab: .today)
            if store.dayOffset != 0 { failures.append("Today route did not return to the current local day") }
            navigation.openStoryDay(chosen)
            checkDay()
            navigation.selectScope(.week)
            if !store.reviewDays.contains(where: { calendar.isDate($0.date, inSameDayAs: chosen) }) {
                failures.append("Changing historical Day to Week lost the selected date's context")
            }
            navigation.selectScope(.month)
            navigation.selectStoryDay(chosen)
            navigation.stepStoryPeriod(by: -1)
            if navigation.storySelectedDay != nil {
                failures.append("July retained an August selection")
            }
            navigation.open(tab: .review)
            if navigation.sheet != .history || store.historyDays.isEmpty {
                failures.append("History route did not present searchable evidence")
            }
            let emptyDay = calendar.date(byAdding: .day, value: -1, to: chosen)!
            navigation.openStoryDay(emptyDay)
            if !calendar.isDate(store.selectedDay, inSameDayAs: emptyDay) || !store.daySessions.isEmpty {
                failures.append("An explicitly requested empty day was silently replaced with a recorded date")
            }
            store.setDashboardVisible(false)
            store.setReviewVisible(false)
            return failures
        }
    }
}
