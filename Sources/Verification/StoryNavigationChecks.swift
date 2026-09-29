import Foundation
import SwiftUI

enum StoryNavigationChecks {
    static let tests: [(String, () -> [String])] = [
        ("Story commands present the requested surface, including repeat routes", routes),
        ("A day opened from History shows that day's own evidence", historicalEvidence),
        ("Find in History opens History with the cursor asked for its search", findInHistory),
        ("Picking in History changes what the rail reads, never the story's day", historyPicks),
        ("Jump to date and the arrow keys move History's selection and its scroll", historyJumpAndSteps)
    ]

    private static func historyPicks() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.insightsStore(withEvidence: true)
            defer { FixtureFactory.cleanUp() }
            let calendar = SessionStore.historyCalendar
            let navigation = MainWindowModel(store: store)
            navigation.open(tab: .review)
            store.refreshReview()
            let storyDay = store.selectedDay
            var failures: [String] = []
            let top = store.historyTop()
            if navigation.historyOpen != HistoryTreeBuilder.pathToToday(top: top, calendar: calendar) {
                failures.append("History did not open to this week")
            }
            let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: store.now()))!
            navigation.openHistory(day: yesterday)
            if navigation.reviewSelectedDate != yesterday {
                failures.append("Jump to date did not open the day: \(String(describing: navigation.reviewSelectedDate))")
            }
            if let thread = store.journalThreads(on: yesterday, only: nil).first {
                navigation.selectHistory(session: thread, on: yesterday)
                if navigation.historySession?.thread != thread { failures.append("picking a session did not select it") }
                if navigation.reviewSelectedDate != yesterday { failures.append("a picked session did not belong to its day") }
                navigation.stepHistoryFocus(by: -1)
                if navigation.historyFocus != .row(navigation.historyOpen.last!) {
                    failures.append("↑ from the first session did not land on its day")
                }
            } else {
                failures.append("the fixture's yesterday has no session to pick")
            }
            if store.selectedDay != storyDay { failures.append("picking in History moved the story's day") }
            navigation.foldDeepestHistory()
            if navigation.reviewSelectedDate != nil { failures.append("Escape left a day open") }
            return failures
        }
    }

    private static func historyJumpAndSteps() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.insightsStore(withEvidence: true)
            defer { FixtureFactory.cleanUp() }
            let calendar = SessionStore.historyCalendar
            let navigation = MainWindowModel(store: store)
            navigation.open(tab: .review)
            store.refreshReview()
            var failures: [String] = []
            let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: store.now()))!
            let scroll = navigation.historyScrollRequest
            navigation.openHistory(day: twoDaysAgo)
            if navigation.historyOpen.last?.level != .day || navigation.historyOpen.last?.start != twoDaysAgo {
                failures.append("Jump to date did not open the day: \(navigation.historyOpen.map(\.level))")
            }
            if navigation.historyScrollRequest == scroll || navigation.historyScrollTarget != navigation.historyOpen.last?.id {
                failures.append("Jump to date did not ask the tree to scroll to the day")
            }
            navigation.stepHistoryFocus(by: 1)
            guard case .session(_, let day) = navigation.historyFocus ?? .row(navigation.historyOpen[0]),
                  day == twoDaysAgo else {
                return failures + ["↓ from a day with a session did not reach that session"]
            }
            navigation.stepHistoryFocus(by: -1)
            if navigation.historyFocus != .row(navigation.historyOpen.last!) {
                failures.append("↑ from the day's first session did not return to its row")
            }
            return failures
        }
    }

    private static func findInHistory() -> [String] {
        MainActor.assumeIsolated {
            let navigation = MainWindowModel()
            let before = navigation.historySearchFocusRequest
            navigation.findInHistory()
            var failures: [String] = []
            if navigation.workspace != .history || navigation.sheet != nil {
                failures.append("Find in History did not show History")
            }
            if navigation.historySearchFocusRequest == before {
                failures.append("Find in History did not ask the search field for the cursor")
            }
            navigation.openSettings()
            navigation.findInHistory()
            if navigation.sheet != nil {
                failures.append("Find in History left Settings covering the search")
            }
            return failures
        }
    }

    private static func routes() -> [String] {
        MainActor.assumeIsolated {
            var failures: [String] = []
            let navigation = MainWindowModel()
            navigation.open(tab: .insights)
            if navigation.workspace != .history || navigation.sheet != nil {
                failures.append("Insights command did not present its same-window workspace")
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
            if navigation.sheet != nil || navigation.workspace != .story {
                failures.append("A named day route did not dismiss its sheet and show the day")
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
            let navigation = MainWindowModel(opening: .review)
            navigation.connect(to: store)
            navigation.openDay(chosen)
            var failures: [String] = []
            @MainActor func checkDay() {
                if navigation.workspace != .story || !calendar.isDate(store.selectedDay, inSameDayAs: chosen) {
                    failures.append("Opening 21 August did not show that day's story")
                }
                let names = store.storyDayProjection(on: chosen).sessions.compactMap { entry -> String? in
                    if case .session(let session) = entry { return session.name }; return nil
                }
                if names != ["Historical parser work"] {
                    failures.append("Historical route did not load its own session evidence: \(names)")
                }
            }
            checkDay()
            navigation.open(tab: .today)
            if store.dayOffset != 0 { failures.append("Today route did not return to the current local day") }
            navigation.jumpToDay(chosen)
            checkDay()
            // 21 August is the first recorded day, so the only step is forward.
            navigation.stepStoryPeriod(by: 1)
            if !calendar.isDate(store.selectedDay, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: chosen)!) {
                failures.append("Stepping on from 21 August did not show 22 August")
            }
            navigation.open(tab: .review)
            if navigation.workspace != .history || store.historyDays.isEmpty {
                failures.append("History route did not present searchable evidence")
            }
            let emptyDay = calendar.date(byAdding: .day, value: -1, to: chosen)!
            let emptyProjection = store.storyDayProjection(on: emptyDay)
            if !emptyProjection.sessions.isEmpty {
                failures.append("An explicit empty-day projection borrowed another date's evidence")
            }
            store.setDashboardVisible(false)
            store.setReviewVisible(false)
            return failures
        }
    }
}
