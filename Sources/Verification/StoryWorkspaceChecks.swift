import Foundation
import SwiftUI
import AppKit

private final class StoryRenderEvidenceBox {
    var values: Set<StoryRenderEvidence> = []
}

struct StoryRenderedFrame {
    let bitmap: NSBitmapImageRep?
    let evidence: Set<StoryRenderEvidence>
}

enum StoryWorkspaceChecks {
    static let tests: [(String, () -> [String])] = [
        ("Explicit day projections use only the requested day's seeded evidence", explicitDayProjection),
        ("History and Insights preserve Story and running-engine context", workspacesPreserveStory),
        ("Insights pages are bounded, newest first and expose every scope", insightPages),
        ("History never shows a period from before the record began", insightRecordFloor),
            ("A ticking clock does not rebuild an unchanged page of History", insightReadingIsCached),
        ("A projected current-day child owns all running presentation state", projectedCurrentDayLiveState),
        ("Receipt-only dates remain searchable without focus or app-use credit", receiptOnlyHistory),
        ("Story workspaces render sparse and dense reading contexts offscreen", offscreenWorkspaceRenders)
    ]

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
            let navigation = MainWindowModel(store: store)
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
            if navigation.workspace != .history {
                failures.append("Closing Settings did not restore Insights")
            }
            navigation.revealApplication()
            if navigation.workspace != .history {
                failures.append("Generic Open discarded the current reading workspace")
            }
            navigation.returnToStory()
            if navigation.workspace != .story {
                failures.append("Return to Story did not restore the day's story")
            }
            if !Calendar.current.isDate(store.selectedDay, inSameDayAs: storyDay)
                || store.engine.activeThreadID != thread || store.engine.state != state {
                failures.append("A reading workspace mutated Story's date or running engine")
            }
            return failures
        }
    }

    /// The column, its chrome label and its paging all stop at the first day
    /// the app ever saw. A page of blank months before the install is not
    /// history; it is a claim of a record that was never kept.
    /// History's reading and the usage snapshot beneath it are built once per
    /// change of evidence, not once per read. The view reads them from `body`,
    /// and `body` runs every second while a session ticks; a page that was
    /// rebuilt each time held a core at full load for as long as it was open.
    private static func insightReadingIsCached() -> [String] {
        MainActor.assumeIsolated {
            var failures: [String] = []
            let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            defer { FixtureFactory.cleanUp() }
            let anchor = Calendar.current.startOfDay(for: store.now())

            // The snapshot: many reads in one second, at most one build. The
            // fixture's own refresh has usually built it already, so warming
            // first makes the count about the reads, not the setup.
            guard store.usage != nil else {
                return ["The history fixture attaches no usage archive; the snapshot cannot be checked"]
            }
            _ = store.effectiveUsageSnapshot
            let snapshotsBefore = store.usageSnapshotComputeCount
            for _ in 0..<5 { _ = store.effectiveUsageSnapshot }
            let snapshotsBuilt = store.usageSnapshotComputeCount - snapshotsBefore
            if snapshotsBuilt > 1 {
                failures.append("Five reads of an unchanged usage archive built \(snapshotsBuilt) snapshots")
            }

            // The reading: many reads, one build — including today's period,
            // which the clock alone must not invalidate within a minute.
            let before = store.insightReadingComputeCount
            for _ in 0..<5 {
                _ = store.insightReading(scope: .month, anchoredAt: anchor, limit: 3)
            }
            let built = store.insightReadingComputeCount - before
            if built != 1 {
                failures.append("Five reads of an unchanged month built the reading \(built) times, not once")
            }
            // A different page is a different reading.
            _ = store.insightReading(scope: .week, anchoredAt: anchor, limit: 6)
            if store.insightReadingComputeCount - before != 2 {
                failures.append("Changing the span did not build a new reading")
            }
            // Evidence changing must invalidate it: a saved note bumps the
            // metadata revision the key carries.
            guard let record = store.engine.archive.records.first else {
                failures.append("The history fixture has no archived session to annotate")
                return failures
            }
            let compute = store.insightReadingComputeCount
            _ = store.insightReading(scope: .week, anchoredAt: anchor, limit: 6)
            if store.insightReadingComputeCount != compute {
                failures.append("Re-reading the same page rebuilt it before any evidence changed")
            }
            store.setNoteDraft("cache check", for: record.id)
            if !store.saveNote(for: record.id) {
                failures.append("The fixture could not save a note to change the evidence")
            }
            _ = store.insightReading(scope: .week, anchoredAt: anchor, limit: 6)
            if store.insightReadingComputeCount != compute + 1 {
                failures.append("Changed evidence did not rebuild the reading "
                                + "(\(store.insightReadingComputeCount - compute) builds)")
            }
            return failures
        }
    }

    private static func insightRecordFloor() -> [String] {
        MainActor.assumeIsolated {
            var failures: [String] = []
            let calendar = Calendar.current
            let store = FixtureFactory.insightsStore(withEvidence: true)
            defer { FixtureFactory.cleanUp() }
            let navigation = MainWindowModel(opening: .insights, store: store)
            navigation.open(tab: .insights)
            guard let earliest = store.earliestSelectableDay else {
                return ["The evidence fixture has no first recorded day to clamp to"]
            }
            for range in HistoryRange.allCases {
                navigation.selectHistoryRange(range)
                let scope = navigation.insightRange
                let shown = navigation.insightShownCount
                let fitting = navigation.insightRequestedCount
                if shown < 1 || shown > fitting {
                    failures.append("\(scope.rawValue) shows \(shown) periods against a capacity of \(fitting)")
                }
                let pages = store.insightPeriodProjections(scope: scope,
                                                           anchoredAt: navigation.insightAnchor,
                                                           limit: shown)
                guard let oldest = pages.last else {
                    failures.append("\(scope.rawValue) shows no period at all"); continue
                }
                if oldest.end <= earliest {
                    failures.append("\(scope.rawValue) drew \(oldest.start) – \(oldest.end), "
                                    + "which ends before the record began on \(earliest)")
                }
                if shown < fitting, oldest.start > earliest {
                    failures.append("\(scope.rawValue) stopped short: room for more, and "
                                    + "\(oldest.start) is after the first recorded day \(earliest)")
                }
                if let window = navigation.insightWindow {
                    if let floor = calendar.dateInterval(of: scope == .day ? .day
                                                          : scope == .week ? .weekOfYear : .month,
                                                          for: earliest)?.start, window.start < floor {
                        failures.append("\(scope.rawValue) chrome window starts \(window.start), before the record")
                    }
                    if shown < fitting, navigation.insightCanPageBack {
                        failures.append("\(scope.rawValue) offers to page back past the first recorded day")
                    }
                }
            }
            // Nothing recorded: one period, the current one, and no invented past.
            let bare = FixtureFactory.store(for: .firstRun)
            let fresh = MainWindowModel(opening: .insights, store: bare)
            fresh.open(tab: .insights)
            for range in HistoryRange.allCases {
                fresh.selectHistoryRange(range)
                if fresh.insightShownCount != 1 {
                    failures.append("With nothing recorded, \(range.title) shows "
                                    + "\(fresh.insightShownCount) periods instead of the current one")
                }
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
            // History's bars group by day, week or month, and nothing else.
            if Set(InsightRange.allCases) != Set([.day, .week, .month]) {
                failures.append("History did not group by exactly day, week and month")
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
            let navigation = MainWindowModel(store: dense)
            let denseDay = renderFrame(DayStoryColumn(store: dense), height: 900)
            requireContent("Day story", denseDay)
            requireEvidence("Day story", denseDay, includes: [.dayStory])

            navigation.open(tab: .review)
            navigation.selectHistoryRange(.months12)
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
            for range in HistoryRange.allCases {
                insightDenseNavigation.selectHistoryRange(range)
                sparseNavigation.selectHistoryRange(range)
                let scope = range
                let denseFrame = renderFrame(
                    InsightsView(store: insightDense,
                                 navigation: insightDenseNavigation, scrolls: false),
                    height: 1_100)
                let sparseFrame = renderFrame(
                    InsightsView(store: sparse,
                                 navigation: sparseNavigation, scrolls: false),
                    height: 1_100)
                requireContent("Dense Insights \(scope.title)", denseFrame)
                requireContent("Sparse Insights \(scope.title)", sparseFrame)
                requireEvidence("Dense Insights \(scope.title)", denseFrame,
                                includes: [.insightPeriod, .insightStrongestDay])
                // A range holding nothing anywhere states that once, instead of
                // repeating an identical zero card for every period in it.
                requireEvidence("Sparse Insights \(scope.title)", sparseFrame,
                                includes: [.insightEmptyPeriod],
                                excludes: [.insightPeriod, .insightStrongestDay])
            }
            FixtureFactory.cleanUp()
            return failures
        }
    }

    static func renderFrame<V: View>(_ view: V,
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
