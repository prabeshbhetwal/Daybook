import SwiftUI
import AppKit

/// `--snapshot <dir>` renders every gallery fixture to PNG in both appearances.
/// The gallery window is for a human; this is how the design gets checked without
/// a screen-recording grant, and it doubles as a visual regression artefact.
@MainActor
enum Snapshotter {

    /// The screen the harness pretends to be on. Two-pane output needs a wide
    /// one; pass `--snapshot-narrow` for the single-column artefacts.
    static var screen: CGSize {
        // 13" MacBook Pro by default: the tightest machine the panel must fit,
        // so the regression artefacts show the layout under real pressure
        // rather than on a display with room to hide mistakes.
        if CommandLine.arguments.contains("--wide") {
            return CGSize(width: 2_560, height: 1_440)
        }
        return CGSize(width: 1_440, height: 845)
    }

    static func run(directory: URL) -> Bool {
        // ImageRenderer needs AppKit initialised for text and symbol rendering.
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)

        do {
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(Data("cannot create \(directory.path)\n".utf8))
            return false
        }

        var wrote = 0
        var supplementalFailed = false
        for fixture in Fixture.allCases {
            for scheme in [ColorScheme.light, .dark] {
                let store = FixtureFactory.store(for: fixture)
                let name = "\(fixture.rawValue)-\(scheme == .light ? "light" : "dark").png"
                // Unscrolled: `ScrollView` has no intrinsic content under
                // `ImageRenderer`, so the harness would render an empty panel.
                let metrics = PopoverMetrics.fitting(Snapshotter.screen)
                let view = PopoverView(store: store,
                                       metricsOverride: metrics,
                                       scrolls: false)
                    .environment(\.colorScheme, scheme)
                    // The canvas follows the panel. Hard-coding the single-column
                    // width cropped every two-pane render in half, which looked
                    // like a layout fault and was a harness fault.
                    .frame(width: metrics.width)
                    .background(scheme == .light ? Color.white : Color.black)

                let dashName = "dashboard-\(fixture.rawValue)-\(scheme == .light ? "light" : "dark").png"
                // Taller than the window's default: the harness cannot scroll,
                // and the day view with a session running is about 900pt.
                let dash = DashboardView(store: store, scrolls: false)
                    .environment(\.colorScheme, scheme)
                    .frame(width: 1020, height: 1240, alignment: .top)
                    .background(scheme == .light ? Color.white : Color.black)
                _ = render(dash, to: directory.appendingPathComponent(dashName))

                // The ordinary dashboard view returns to today on appearance.
                // Preserve yesterday only for this historical snapshot, so the
                // harness proves the past-day surface without changing app use.
                if fixture == .idleWithHistory {
                    store.stepDay(by: -1)
                    let pastDay = DashboardView(store: store, scrolls: false,
                                                returnsToTodayOnAppear: false)
                        .environment(\.colorScheme, scheme)
                        .frame(width: 1020, height: 1240, alignment: .top)
                        .background(scheme == .light ? Color.white : Color.black)
                    _ = render(pastDay, to: directory.appendingPathComponent(
                        "dashboard-past-idleWithHistory-\(scheme == .light ? "light" : "dark").png"))
                    store.goToToday()
                }

                // Week and Month share a code path, so one fixture with history
                // covers both; the empty state needs a fixture with none.
                let periods: [TrackingPeriod]
                switch fixture {
                case .idleWithHistory: periods = [.week, .month]
                case .firstRun: periods = [.week]
                default: periods = []
                }
                for period in periods {
                    store.period = period
                    let periodName = "period-\(period.rawValue)-\(fixture.rawValue)"
                        + "-\(scheme == .light ? "light" : "dark").png"
                    let periodView = DashboardView(store: store, scrolls: false)
                        .environment(\.colorScheme, scheme)
                        // Taller than the dashboard frame: a period's log is long,
                        // and the harness cannot scroll.
                        .frame(width: 1020, height: 1500, alignment: .top)
                        .background(scheme == .light ? Color.white : Color.black)
                    _ = render(periodView, to: directory.appendingPathComponent(periodName))
                }
                store.period = .day

                if render(view, to: directory.appendingPathComponent(name)) {
                    wrote += 1
                    print("  wrote \(name)")
                } else {
                    print("  FAILED \(name)")
                }
            }
        }
        for scheme in [ColorScheme.light, .dark] {
            let variants = [
                (name: "wide", size: CGSize(width: 1_160, height: 780),
                 screen: CGSize(width: 1_440, height: 845)),
                (name: "narrow", size: CGSize(width: 980, height: 680),
                 screen: CGSize(width: 1_000, height: 680))
            ]
            for variant in variants {
                let store = FixtureFactory.store(for: .running)
                let settings = snapshotSettings()
                let navigation = MainWindowModel(selectedTab: .focus)
                let shell = MainWindowView(store: store,
                                           settings: settings,
                                           navigation: navigation)
                    .environment(\.colorScheme, scheme)
                    .frame(width: variant.size.width, height: variant.size.height,
                           alignment: .topLeading)
                    .background(Tokens.Colour.ground)
                let shellName = "main-shell-\(variant.name)-"
                    + "\(scheme == .light ? "light" : "dark").png"
                if render(shell, to: directory.appendingPathComponent(shellName)) {
                    print("  wrote \(shellName)")
                } else {
                    supplementalFailed = true
                    print("  FAILED \(shellName)")
                }

                let focusStates: [(name: String, fixture: Fixture)] = [
                    ("first-run", .firstRun),
                    ("running", .running),
                    ("automatic-running", .automaticRunning),
                    ("paused", .paused),
                    ("watching", .watching),
                    ("automatic-paused", .automaticPaused),
                    ("automatic-watching", .automaticWatching),
                    ("automatic-away", .automaticAway),
                    ("awaiting-decision", .needsResolution)
                ]
                for state in focusStates {
                    let focusStore = FixtureFactory.store(for: state.fixture)
                    let focusShell = MainWindowView(
                        store: focusStore,
                        settings: snapshotSettings(),
                        navigation: MainWindowModel(selectedTab: .focus),
                        focusScrolls: false
                    )
                    .environment(\.colorScheme, scheme)
                    .frame(width: variant.size.width, height: variant.size.height,
                           alignment: .topLeading)
                    .background(Tokens.Colour.ground)
                    let focusName = "focus-\(state.name)-\(variant.name)-"
                        + "\(scheme == .light ? "light" : "dark").png"
                    if render(focusShell, to: directory.appendingPathComponent(focusName)) {
                        print("  wrote \(focusName)")
                    } else {
                        supplementalFailed = true
                        print("  FAILED \(focusName)")
                    }

                    let popoverStore = FixtureFactory.store(for: state.fixture)
                    let popoverMetrics = PopoverMetrics.fitting(variant.screen)
                    let popover = PopoverView(store: popoverStore,
                                              metricsOverride: popoverMetrics,
                                              scrolls: false)
                        .environment(\.colorScheme, scheme)
                        .frame(width: popoverMetrics.width)
                        .background(scheme == .light ? Color.white : Color.black)
                    let popoverName = "focus-popover-\(state.name)-\(variant.name)-"
                        + "\(scheme == .light ? "light" : "dark").png"
                    if render(popover, to: directory.appendingPathComponent(popoverName)) {
                        print("  wrote \(popoverName)")
                    } else {
                        supplementalFailed = true
                        print("  FAILED \(popoverName)")
                    }
                }
            }

            // Task 6: the purpose-built one-day canvas. These are rendered
            // unscrolled at a tall review measure so the ribbon, inspector,
            // supporting groups and recap are visible in one artefact.
            let emptyToday = FixtureFactory.store(for: .firstRun)
            emptyToday.setDashboardVisible(true)

            let liveToday = FixtureFactory.store(for: .running)
            liveToday.setDashboardVisible(true)

            let historyToday = FixtureFactory.store(for: .idleWithHistory)
            historyToday.setDashboardVisible(true)
            let todayStart = Calendar.current.startOfDay(for: Date())
            historyToday.engine.archive.append(SessionRecord(
                name: "Tea break", workType: .breakTime,
                start: todayStart.addingTimeInterval(185 * 60),
                end: todayStart.addingTimeInterval(215 * 60),
                workSeconds: 30 * 60))
            historyToday.refreshDashboard()

            let selectedToday = FixtureFactory.store(for: .running)
            selectedToday.setDashboardVisible(true)
            if let segment = selectedToday.timelineSegments.first,
               let layout = selectedToday.timelineLayout,
               let fraction = layout.fraction(for: segment.start.addingTimeInterval(1)) {
                selectedToday.selectTimeline(at: fraction)
            }

            let pastToday = FixtureFactory.store(for: .idleWithHistory)
            pastToday.setDashboardVisible(true)
            pastToday.stepDay(by: -1)

            let watchingToday = FixtureFactory.store(for: .watching)
            watchingToday.setDashboardVisible(true)

            let todayStates: [(name: String, store: SessionStore)] = [
                ("empty", emptyToday),
                ("live", liveToday),
                ("history-with-break", historyToday),
                ("selected-inspector", selectedToday),
                ("past-integrity", pastToday),
                ("watching", watchingToday)
            ]
            for state in todayStates {
                let todayView = TodayView(store: state.store, scrolls: false)
                    .environment(\.colorScheme, scheme)
                    .frame(width: 1_100, height: 1_050, alignment: .topLeading)
                    .background(Tokens.Colour.ground)
                let todayName = "today-\(state.name)-"
                    + "\(scheme == .light ? "light" : "dark").png"
                if render(todayView, to: directory.appendingPathComponent(todayName)) {
                    print("  wrote \(todayName)")
                } else {
                    supplementalFailed = true
                    print("  FAILED \(todayName)")
                }
            }

            // Task 7: Week/Month comparison and calendar-driven History. The
            // fixtures include exact tracked bars, the empty state, focus-only
            // evidence, a preserved legacy qualification, an intersected filter
            // and display-name search whose bundle ID contains neither word.
            let weekReview = FixtureFactory.store(for: .idleWithHistory,
                                                  accurateUsage: true)
            weekReview.refreshReview(period: .week)

            let monthReview = FixtureFactory.store(for: .idleWithHistory,
                                                   accurateUsage: true)
            monthReview.refreshReview(period: .month)

            let emptyReview = FixtureFactory.store(for: .firstRun)
            emptyReview.refreshReview(period: .week)

            let legacyReview = FixtureFactory.store(for: .idleWithHistory)
            legacyReview.refreshReview(period: .week)

            let focusOnlyReview = FixtureFactory.store(for: .firstRun)
            let focusBounds = Calendar.current.dateInterval(of: .weekOfYear, for: Date())
            let focusStart = (focusBounds?.start ?? Date()).addingTimeInterval(2 * 3_600)
            let focusThread = UUID()
            focusOnlyReview.engine.archive.append(SessionRecord(
                name: "Write proposal", workType: .deepWork,
                start: focusStart, end: focusStart.addingTimeInterval(45 * 60),
                workSeconds: 45 * 60, threadID: focusThread))
            focusOnlyReview.engine.archive.append(SessionRecord(
                name: "Write proposal", workType: .deepWork,
                start: focusStart.addingTimeInterval(4 * 3_600),
                end: focusStart.addingTimeInterval(4 * 3_600 + 15 * 60),
                workSeconds: 15 * 60, threadID: focusThread))
            focusOnlyReview.refreshReview(period: .week)

            let denseFocusReview = FixtureFactory.store(for: .firstRun)
            let denseBounds = Calendar.current.dateInterval(of: .weekOfYear, for: Date())
            let denseStart = (denseBounds?.start ?? Date()).addingTimeInterval(3_600)
            for index in 0..<510 {
                let start = denseStart.addingTimeInterval(Double(index * 60))
                let seconds: TimeInterval = index == 0 ? 120 : 60
                denseFocusReview.engine.archive.append(SessionRecord(
                    name: "Focus \(index)",
                    workType: index == 0 ? .learning : .deepWork,
                    start: start, end: start.addingTimeInterval(seconds),
                    workSeconds: seconds))
            }
            denseFocusReview.refreshReview(period: .week)

            let filteredHistory = FixtureFactory.store(for: .idleWithHistory)
            filteredHistory.refreshReview()
            filteredHistory.setHistoryQuery("xcode")
            filteredHistory.setHistoryApp("com.apple.dt.Xcode")
            filteredHistory.setHistoryWorkType(.deepWork)

            let nameSearchHistory = FixtureFactory.store(for: .firstRun)
            let searchDay = Calendar.current.startOfDay(for: Date())
            nameSearchHistory.usage?.record(AppUsageSession(
                bundleID: "org.example.product", appName: "Quill Writer",
                start: searchDay.addingTimeInterval(60 * 60),
                end: searchDay.addingTimeInterval(70 * 60)))
            nameSearchHistory.refreshReview()
            nameSearchHistory.setHistoryQuery("quill writer")

            let reviewStates: [(name: String, store: SessionStore, section: ReviewSection)] = [
                ("week", weekReview, .week),
                ("month", monthReview, .month),
                ("empty", emptyReview, .week),
                ("focus-only", focusOnlyReview, .week),
                ("focus-dense-bounded", denseFocusReview, .week),
                ("legacy-qualified", legacyReview, .week),
                ("history-filtered", filteredHistory, .history),
                ("history-name-search", nameSearchHistory, .history)
            ]
            for state in reviewStates {
                // The local section is owned by the navigation model; select it
                // before composition so the rendered surface is deterministic.
                let navigation = MainWindowModel(selectedTab: .review)
                navigation.reviewSection = state.section
                let selectedReview = ReviewView(store: state.store,
                                                navigation: navigation,
                                                scrolls: false)
                    .environment(\.colorScheme, scheme)
                    .frame(width: 1_100, height: 1_500, alignment: .topLeading)
                    .background(Tokens.Colour.ground)
                let reviewName = "review-\(state.name)-"
                    + "\(scheme == .light ? "light" : "dark").png"
                if render(selectedReview, to: directory.appendingPathComponent(reviewName)) {
                    print("  wrote \(reviewName)")
                } else {
                    supplementalFailed = true
                    print("  FAILED \(reviewName)")
                }
            }

            let strip = ComponentStrip()
                .environment(\.colorScheme, scheme)
                .frame(width: 2200)
            _ = render(strip, to: directory.appendingPathComponent(
                "components-\(scheme == .light ? "light" : "dark").png"))
            let quick = AwayAnswerGrid(away: 22 * 60,
                                       range: (Date().addingTimeInterval(-22 * 60), Date()),
                                       compact: true, onAnswer: { _ in }, onReason: { _ in })
                .padding(Tokens.Space.m).frame(width: 300)
                .background(Tokens.Surface.card)
                .environment(\.colorScheme, scheme)
            _ = render(quick, to: directory.appendingPathComponent(
                "awayPrompt-quick-\(scheme == .light ? "light" : "dark").png"))
            let full = AwayAnswerGrid(away: 72 * 60,
                                      range: (Date().addingTimeInterval(-72 * 60), Date()),
                                      showsCaptions: true, onAnswer: { _ in }, onReason: { _ in })
                .padding(Tokens.Space.xl).frame(width: 520)
                .background(Tokens.Surface.card)
                .environment(\.colorScheme, scheme)
            _ = render(full, to: directory.appendingPathComponent(
                "awayPrompt-full-\(scheme == .light ? "light" : "dark").png"))
        }
        print("\(wrote)/\(Fixture.allCases.count * 2) snapshots written to \(directory.path)")
        return wrote == Fixture.allCases.count * 2 && !supplementalFailed
    }

    private static func snapshotSettings() -> SettingsModel {
        let defaults = UserDefaults(
            suiteName: "com.prabesh.focuscontinuity.snapshot.shell"
        ) ?? .standard
        let persistence = PersistenceStore(defaults: defaults)
        persistence.removeAll()
        return SettingsModel(store: persistence,
                             isTrackingEnabled: true,
                             onChange: {},
                             onTrackingChanged: { _ in })
    }

    @MainActor
    private static func render<V: View>(_ view: V, to url: URL) -> Bool {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return false
        }
        do {
            try png.write(to: url)
            return true
        } catch {
            return false
        }
    }
}
