import Foundation
import SwiftUI
import AppKit

private final class StoryRenderEvidenceBox {
    var values: Set<StoryRenderEvidence> = []
}

private struct StoryRenderedFrame {
    let bitmap: NSBitmapImageRep?
    let evidence: Set<StoryRenderEvidence>
}

enum StoryWorkspaceChecks {
    static let tests: [(String, () -> [String])] = [
        ("Opening a period child preserves its parent reading context", periodChildPreservesContext),
        ("Explicit day projections use only the requested day's seeded evidence", explicitDayProjection),
        ("History and Insights preserve Story and running-engine context", workspacesPreserveStory),
        ("Insights pages are bounded, newest first and expose every scope", insightPages),
        ("Insights restores each scope's anchor and page depth", insightScopeRestoration),
        ("A projected current-day child owns all running presentation state", projectedCurrentDayLiveState),
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
            if navigation.workspace != .insights {
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
            if Set(InsightRange.allCases) != Set([.day, .week, .month, .year]) {
                failures.append("History did not expose Day, Week, Month and Year")
            }
            return failures
        }
    }

    private static func insightScopeRestoration() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.insightsStore(withEvidence: true)
            defer { FixtureFactory.cleanUp() }
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: store.now())
            let navigation = MainWindowModel(store: store)
            var failures: [String] = []

            navigation.selectInsightRange(.day)
            navigation.stepInsightPeriod(by: -2)
            navigation.showEarlierInsights()
            let dayAnchor = navigation.insightAnchor
            let dayPages = navigation.insightPageCount

            navigation.selectInsightRange(.week)
            if !calendar.isDate(navigation.insightAnchor, inSameDayAs: today)
                || navigation.insightPageCount != 6 {
                failures.append("Week inherited Day's historical anchor or page depth")
            }
            navigation.stepInsightPeriod(by: -1)
            navigation.showEarlierInsights()
            let weekAnchor = navigation.insightAnchor
            let weekPages = navigation.insightPageCount

            navigation.selectInsightRange(.month)
            if !calendar.isDate(navigation.insightAnchor, inSameDayAs: today)
                || navigation.insightPageCount != 3 {
                failures.append("Month inherited Week's historical anchor or page depth")
            }
            navigation.stepInsightPeriod(by: -1)
            navigation.showEarlierInsights()
            let monthAnchor = navigation.insightAnchor
            let monthPages = navigation.insightPageCount

            navigation.selectInsightRange(.day)
            if navigation.insightAnchor != dayAnchor || navigation.insightPageCount != dayPages {
                failures.append("Day did not restore its anchor and page depth")
            }
            navigation.selectInsightRange(.week)
            if navigation.insightAnchor != weekAnchor || navigation.insightPageCount != weekPages {
                failures.append("Week did not restore its anchor and page depth")
            }
            navigation.selectInsightRange(.month)
            if navigation.insightAnchor != monthAnchor || navigation.insightPageCount != monthPages {
                failures.append("Month did not restore its anchor and page depth")
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

    private static func projectedCurrentDayLiveState() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .running, accurateUsage: true)
            defer { FixtureFactory.cleanUp() }
            store.selectDay(offset: 1)
            guard !store.isToday else {
                return ["Fixture did not move the global Day selection into history"]
            }
            let projection = store.storyDayProjection(on: store.now())
            guard projection.isCurrentDay,
                  let running = projection.sessions.compactMap({ entry -> DaySession? in
                      if case .session(let session) = entry, session.isRunning { return session }
                      return nil
                  }).first else {
                return ["Current projected child did not contain the running session"]
            }
            let presentation = DayStorySessionPresentation.make(
                session: running, isCurrentStoryDay: projection.isCurrentDay, store: store)
            var failures: [String] = []
            if presentation.clock != Tokens.clock(running.worked) {
                failures.append("Current projected child lost its live clock")
            }
            if presentation.liveStatus != "running now" {
                failures.append("Current projected child lost running-now status")
            }
            if presentation.pauseTitle != "Pause" || !presentation.canControl {
                failures.append("Current projected child lost pause/end control state")
            }

            let pausedStore = FixtureFactory.store(for: .paused, accurateUsage: true)
            pausedStore.selectDay(offset: 1)
            let pausedProjection = pausedStore.storyDayProjection(on: pausedStore.now())
            if let pausedSession = pausedProjection.sessions.compactMap({ entry -> DaySession? in
                if case .session(let session) = entry, session.isRunning { return session }
                return nil
            }).first {
                let paused = DayStorySessionPresentation.make(
                    session: pausedSession,
                    isCurrentStoryDay: pausedProjection.isCurrentDay,
                    store: pausedStore)
                if paused.clock != Tokens.clock(pausedSession.worked)
                    || paused.liveStatus != "paused"
                    || paused.pauseTitle != "Resume"
                    || !paused.canControl {
                    failures.append("Current projected child lost paused/Resume presentation")
                }
            } else {
                failures.append("Paused current projected child lost its running-session row")
            }
            return failures
        }
    }

    private static func offscreenWorkspaceRenders() -> [String] {
        MainActor.assumeIsolated {
            var failures: [String] = []
            func requireContent(_ label: String, _ frame: StoryRenderedFrame) {
                guard let bitmap = frame.bitmap else {
                    failures.append("\(label) did not produce an offscreen bitmap")
                    return
                }
                let contrast = bitmapContrast(bitmap)
                if contrast < 0.08 {
                    failures.append("\(label) content region was effectively blank (contrast \(contrast))")
                }
            }
            func requireEvidence(_ label: String, _ frame: StoryRenderedFrame,
                                 includes: Set<StoryRenderEvidence>,
                                 excludes: Set<StoryRenderEvidence> = []) {
                let missing = includes.subtracting(frame.evidence)
                if !missing.isEmpty {
                    failures.append("\(label) missed production content evidence \(missing.map(\.rawValue).sorted())")
                }
                let unexpected = excludes.intersection(frame.evidence)
                if !unexpected.isEmpty {
                    failures.append("\(label) unexpectedly rendered \(unexpected.map(\.rawValue).sorted())")
                }
            }
            let dense = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            let navigation = MainWindowModel(storyScope: .day, store: dense)
            let denseDay = renderFrame(DayStoryColumn(store: dense), height: 900)
            requireContent("Day story", denseDay)
            requireEvidence("Day story", denseDay, includes: [.dayStory])

            navigation.selectScope(.week)
            if let day = dense.reviewDays.first?.date { navigation.selectStoryDay(day) }
            let weekClosed = renderFrame(
                WeekStoryColumn(store: dense, navigation: navigation), height: 1_200)
            requireEvidence("Closed Week child", weekClosed, includes: [],
                            excludes: [.periodChild])
            if let day = navigation.storySelectedDay { navigation.openStoryDay(day) }
            let weekOpen = renderFrame(
                WeekStoryColumn(store: dense, navigation: navigation), height: 1_200)
            requireContent("Week inline child", weekOpen)
            requireEvidence("Week inline child", weekOpen, includes: [.periodChild, .dayStory])

            navigation.selectScope(.month)
            if let day = dense.reviewDays.first?.date { navigation.selectStoryDay(day) }
            let monthClosed = renderFrame(
                MonthStoryColumn(store: dense, navigation: navigation), height: 1_600)
            requireEvidence("Closed Month child", monthClosed, includes: [],
                            excludes: [.periodChild])
            if let day = navigation.storySelectedDay { navigation.openStoryDay(day) }
            let monthOpen = renderFrame(
                MonthStoryColumn(store: dense, navigation: navigation), height: 1_600)
            requireContent("Month inline child", monthOpen)
            requireEvidence("Month inline child", monthOpen, includes: [.periodChild, .dayStory])

            navigation.open(tab: .review)
            navigation.selectInsightRange(.year)
            navigation.clearReviewDay()
            let historyClosed = renderFrame(
                InsightsView(store: dense, navigation: navigation, scrolls: false), height: 1_400)
            requireEvidence("Closed History detail", historyClosed, includes: [],
                            excludes: [.historyDetail])
            if let day = dense.filteredHistoryDays.first?.date { navigation.selectReviewDay(day) }
            let historyOpen = renderFrame(
                InsightsView(store: dense, navigation: navigation, scrolls: false), height: 1_400)
            requireContent("History day preview", historyOpen)
            // The picked day previews in the rail; its full story is one
            // action away, not unfolded inside the list.
            requireEvidence("History day preview", historyOpen,
                            includes: [.historyDetail], excludes: [.dayStory])
            FixtureFactory.cleanUp()

            let insightDense = FixtureFactory.insightsStore(withEvidence: true)
            let insightDenseNavigation = MainWindowModel(store: insightDense)
            let sparse = FixtureFactory.store(for: .firstRun, accurateUsage: true)
            let sparseNavigation = MainWindowModel(store: sparse)
            for scope in InsightRange.allCases {
                insightDenseNavigation.selectInsightRange(scope)
                sparseNavigation.selectInsightRange(scope)
                let denseFrame = renderFrame(
                    InsightsView(store: insightDense,
                                 navigation: insightDenseNavigation, scrolls: false),
                    height: 1_100)
                let sparseFrame = renderFrame(
                    InsightsView(store: sparse,
                                 navigation: sparseNavigation, scrolls: false),
                    height: 1_100)
                requireContent("Dense Insights \(scope.rawValue)", denseFrame)
                requireContent("Sparse Insights \(scope.rawValue)", sparseFrame)
                requireEvidence("Dense Insights \(scope.rawValue)", denseFrame,
                                includes: [.insightPeriod, .insightStrongestDay])
                // A range holding nothing anywhere states that once, instead of
                // repeating an identical zero card for every period in it.
                requireEvidence("Sparse Insights \(scope.rawValue)", sparseFrame,
                                includes: [.insightEmptyPeriod],
                                excludes: [.insightPeriod, .insightStrongestDay])
            }
            FixtureFactory.cleanUp()
            return failures
        }
    }

    private static func renderFrame<V: View>(_ view: V,
                                             width: CGFloat = 980,
                                             height: CGFloat) -> StoryRenderedFrame {
        let evidence = StoryRenderEvidenceBox()
        let framed = view.frame(width: width, height: height, alignment: .topLeading)
            .background(Tokens.Colour.ground)
            .onPreferenceChange(StoryRenderEvidenceKey.self) {
                evidence.values = $0
            }
        let host = NSHostingView(rootView: framed)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        host.displayIfNeeded()
        defer { window.orderOut(nil); window.close() }
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            return StoryRenderedFrame(bitmap: nil, evidence: evidence.values)
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return StoryRenderedFrame(bitmap: bitmap, evidence: evidence.values)
    }

    private static func bitmapContrast(_ bitmap: NSBitmapImageRep) -> Double {
        var low = 1.0
        var high = 0.0
        let startY = min(bitmap.pixelsHigh - 1, max(0, bitmap.pixelsHigh / 8))
        for y in stride(from: startY, to: bitmap.pixelsHigh, by: 5) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 5) {
                guard let colour = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    continue
                }
                let luminance = 0.2126 * Double(colour.redComponent)
                    + 0.7152 * Double(colour.greenComponent)
                    + 0.0722 * Double(colour.blueComponent)
                low = min(low, luminance)
                high = max(high, luminance)
            }
        }
        return high - low
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
