import Foundation
import SwiftUI
import AppKit

enum StoryWorkspaceChecks {
    static let tests: [(String, () -> [String])] = [
        ("Opening a period child preserves its parent reading context", periodChildPreservesContext),
        ("Explicit day projections use only the requested day's seeded evidence", explicitDayProjection),
        ("History and Insights preserve Story and running-engine context", workspacesPreserveStory),
        ("Insights pages are bounded, newest first and expose every scope", insightPages),
        ("Receipt-only dates remain searchable without focus or app-use credit", receiptOnlyHistory),
        ("Story workspaces render sparse and dense reading contexts offscreen", offscreenWorkspaceRenders)
    ]

    private static func periodChildPreservesContext() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            defer { FixtureFactory.cleanUp() }
            let calendar = Calendar.current
            let navigation = MainWindowModel(storyScope: .week, store: store)
            guard let child = store.reviewDays.dropFirst().first?.date else {
                return ["Week fixture did not publish a child day"]
            }
            let selectedBefore = store.selectedDay
            let anchorBefore = store.reviewAnchor
            let totalBefore = store.reviewSummary.tracked

            navigation.openStoryDay(child)

            var failures: [String] = []
            if navigation.storyScope != .week {
                failures.append("Opening a week child changed Story scope")
            }
            if !calendar.isDate(store.selectedDay, inSameDayAs: selectedBefore) {
                failures.append("Opening a week child changed the global Day selection")
            }
            if store.reviewAnchor != anchorBefore {
                failures.append("Opening a week child changed the parent period anchor")
            }
            if store.reviewSummary.tracked != totalBefore {
                failures.append("Opening a week child changed the parent tracked total")
            }
            if navigation.expandedStoryDay != child || navigation.storySelectedDay != child {
                failures.append("Opening a week child did not bind the inline story to that date")
            }
            navigation.openStoryDay(child)
            if navigation.expandedStoryDay != nil {
                failures.append("The expanded child action did not toggle to Hide story")
            }
            navigation.openStoryDay(child)
            if let other = store.reviewDays.first(where: {
                !calendar.isDate($0.date, inSameDayAs: child)
            })?.date {
                navigation.selectStoryDay(other)
                if navigation.expandedStoryDay != other {
                    failures.append("Selecting another period day did not update the open child")
                }
            }
            navigation.stepStoryPeriod(by: -1)
            if navigation.storySelectedDay != nil || navigation.expandedStoryDay != nil {
                failures.append("Stepping the parent period retained an incompatible child")
            }
            return failures
        }
    }

    private static func explicitDayProjection() -> [String] {
        MainActor.assumeIsolated {
            let fixture = makeSeededStore()
            defer { fixture.cleanUp() }
            let calendar = Calendar.current
            let selectedBefore = fixture.store.selectedDay
            let projection = fixture.store.storyDayProjection(on: fixture.day)
            var failures: [String] = []
            if projection.focused != 3_000 {
                failures.append("Seeded projection focused \(projection.focused)s instead of 3000s")
            }
            if projection.tracked != 3_000 {
                failures.append("Seeded projection tracked \(projection.tracked)s instead of 3000s")
            }
            let names = projection.sessions.compactMap { entry -> String? in
                if case .session(let session) = entry { return session.name }
                return nil
            }
            if names != ["Seeded parser"] {
                failures.append("Projection borrowed or lost session evidence: \(names)")
            }
            guard let session = projection.sessions.compactMap({ entry -> DaySession? in
                if case .session(let session) = entry { return session }
                return nil
            }).first, let detail = projection.sessionDetails[session.id] else {
                return failures + ["Seeded projection did not publish session detail"]
            }
            if detail.activity.coverage != 3_000 || detail.apps.map(\.appName) != ["Xcode", "Terminal"] {
                failures.append("Seeded explicit-day app detail was not canonical")
            }
            if !projection.summaryFacts.contains(where: { $0.contains("Recorded break") }) {
                failures.append("Named break summary did not use recorded-break language")
            }
            if !calendar.isDate(fixture.store.selectedDay, inSameDayAs: selectedBefore) {
                failures.append("Building a historical projection mutated selectedDay")
            }
            return failures
        }
    }

    private static func workspacesPreserveStory() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .running, accurateUsage: true)
            defer { FixtureFactory.cleanUp() }
            let navigation = MainWindowModel(storyScope: .day, store: store)
            let storyDay = store.selectedDay
            let thread = store.engine.activeThreadID
            let state = store.engine.state
            navigation.open(tab: .review)
            navigation.openSettings()
            navigation.closeSheet()
            var failures: [String] = []
            if navigation.workspace != .history {
                failures.append("Closing Settings did not restore History")
            }
            navigation.open(tab: .insights)
            navigation.openSettings()
            navigation.closeSheet()
            if navigation.workspace != .insights {
                failures.append("Closing Settings did not restore Insights")
            }
            navigation.revealApplication()
            if navigation.workspace != .insights {
                failures.append("Generic Open discarded the current reading workspace")
            }
            navigation.returnToStory()
            if navigation.workspace != .story || navigation.storyScope != .day {
                failures.append("Return to Story did not restore Story's scope")
            }
            if !Calendar.current.isDate(store.selectedDay, inSameDayAs: storyDay)
                || store.engine.activeThreadID != thread || store.engine.state != state {
                failures.append("A reading workspace mutated Story's date or running engine")
            }
            return failures
        }
    }

    private static func insightPages() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.insightsStore(withEvidence: true)
            defer { FixtureFactory.cleanUp() }
            let anchor = Calendar.current.startOfDay(for: store.now())
            var failures: [String] = []
            for (scope, limit) in [(InsightRange.day, 14), (.week, 6), (.month, 3)] {
                let pages = store.insightPeriodProjections(scope: scope,
                                                           anchoredAt: anchor,
                                                           limit: limit)
                if pages.count != limit || pages.first?.isCurrent != true {
                    failures.append("\(scope.rawValue) pages were not bounded from the current period")
                }
                if pages.map(\.start) != pages.map(\.start).sorted(by: >) {
                    failures.append("\(scope.rawValue) pages were not newest first")
                }
            }
            if Set(InsightRange.allCases) != Set([.day, .week, .month]) {
                failures.append("Insights did not expose Day, Week and Month")
            }
            return failures
        }
    }

    private static func receiptOnlyHistory() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.storyInteractionStore(for: .storyDecision)
            defer { FixtureFactory.cleanUp() }
            guard let receipt = store.engine.awayDecisions.first else {
                return ["Decision fixture did not retain its receipt"]
            }
            let rows = store.storyHistoryDaysIncludingDecisionReceipts([])
            guard let row = rows.first(where: {
                Calendar.current.isDate($0.date, inSameDayAs: receipt.range.start)
            }) else { return ["Receipt-only day was absent from History"] }
            return row.focused == 0 && row.tracked == 0 && row.sessions == 0 ? []
                : ["Receipt-only History day fabricated focus, app use or a session"]
        }
    }

    private static func offscreenWorkspaceRenders() -> [String] {
        MainActor.assumeIsolated {
            var failures: [String] = []
            func render<V: View>(_ label: String, _ view: V) {
                let host = NSHostingView(rootView: view)
                host.frame = NSRect(x: 0, y: 0, width: 980, height: 760)
                host.layoutSubtreeIfNeeded()
                if host.fittingSize.width <= 0 || host.fittingSize.height <= 0 {
                    failures.append("\(label) produced an empty offscreen layout")
                }
            }
            let dense = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            let navigation = MainWindowModel(storyScope: .day, store: dense)
            render("Day", DayStoryColumn(store: dense))
            navigation.selectScope(.week)
            if let day = dense.reviewDays.first?.date { navigation.openStoryDay(day) }
            render("Week child", WeekStoryColumn(store: dense, navigation: navigation))
            navigation.selectScope(.month)
            if let day = dense.reviewDays.first?.date { navigation.openStoryDay(day) }
            render("Month child", MonthStoryColumn(store: dense, navigation: navigation))
            navigation.open(tab: .review)
            if let day = dense.filteredHistoryDays.first?.date { navigation.selectReviewDay(day) }
            render("History detail", HistoryView(store: dense, navigation: navigation))
            for scope in InsightRange.allCases {
                navigation.selectInsightRange(scope)
                render("Dense Insights \(scope.rawValue)",
                       InsightsView(store: dense, navigation: navigation, scrolls: false))
            }
            FixtureFactory.cleanUp()
            let sparse = FixtureFactory.store(for: .firstRun, accurateUsage: true)
            let sparseNavigation = MainWindowModel(store: sparse)
            for scope in InsightRange.allCases {
                sparseNavigation.selectInsightRange(scope)
                render("Sparse Insights \(scope.rawValue)",
                       InsightsView(store: sparse, navigation: sparseNavigation, scrolls: false))
            }
            FixtureFactory.cleanUp()
            return failures
        }
    }

    private struct SeededFixture {
        let store: SessionStore
        let day: Date
        let directory: URL
        let suite: String
        func cleanUp() {
            try? FileManager.default.removeItem(at: directory)
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
    }

    private static func makeSeededStore() -> SeededFixture {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 12))!
        let day = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20))!
        let start = day.addingTimeInterval(9 * 3_600)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fc-story-projection-\(UUID().uuidString)", isDirectory: true)
        let suite = "fc.story.projection.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let archive = SessionArchive(directory: directory, now: { now })
        let thread = UUID()
        archive.append(SessionRecord(name: "Seeded parser", workType: .deepWork,
                                     start: start, end: start.addingTimeInterval(3_600),
                                     workSeconds: 3_000, threadID: thread))
        archive.append(SessionRecord(name: "Driving", workType: .breakTime,
                                     start: start.addingTimeInterval(4_500),
                                     end: start.addingTimeInterval(5_400),
                                     workSeconds: 900))
        let usage = AppUsageArchive(directory: directory, calendar: calendar, now: { now })
        usage.record(AppUsageSession(bundleID: "com.apple.dt.Xcode", appName: "Xcode",
                                     start: start, end: start.addingTimeInterval(1_800)))
        usage.record(AppUsageSession(bundleID: "com.apple.Terminal", appName: "Terminal",
                                     start: start.addingTimeInterval(1_800),
                                     end: start.addingTimeInterval(3_000)))
        let engine = SessionEngine(store: PersistenceStore(defaults: defaults), archive: archive,
                                   ownBundleID: "fc.story.projection", schedulesDwell: false,
                                   now: { now })
        let store = SessionStore(engine: engine, schedulesTicker: false, now: { now })
        let tracker = AppUsageTracker(archive: usage, ownBundleID: "fc.story.projection",
                                      idle: .disabled, now: { now })
        store.attach(tracker: tracker, usage: usage)
        store.refresh()
        return SeededFixture(store: store, day: day, directory: directory, suite: suite)
    }
}
