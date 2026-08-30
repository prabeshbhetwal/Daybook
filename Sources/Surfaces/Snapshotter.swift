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

    /// One canonical root for the density comparison and its structural test.
    /// Keeping the full MainWindowView here prevents either appearance from
    /// accidentally substituting a Focus-only canvas that lacks fixed chrome.
    static func densityFocusSnapshot(
        density: InterfaceDensity,
        scheme: ColorScheme
    ) -> some View {
        let appearance: AppearancePreference = scheme == .light ? .light : .dark
        return MainWindowView(
            store: FixtureFactory.store(for: .running),
            settings: snapshotSettings(density: density, appearance: appearance),
            navigation: MainWindowModel(selectedTab: .focus),
            focusScrolls: false)
            .environment(\.colorScheme, scheme)
            .frame(width: 1_160, height: 780, alignment: .topLeading)
            .background(Tokens.Colour.ground)
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
                                       settings: snapshotSettings(),
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
                let shellDensity: InterfaceDensity = variant.name == "wide"
                    ? .comfortable : .compact
                let shellAppearance: AppearancePreference = scheme == .light
                    ? .light : .dark
                let settings = snapshotSettings(density: shellDensity,
                                                appearance: shellAppearance)
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
                        settings: snapshotSettings(density: shellDensity,
                                                   appearance: shellAppearance),
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
                                              settings: snapshotSettings(
                                                density: shellDensity,
                                                appearance: shellAppearance),
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

            // Task 8: evidence-rich and genuinely insufficient Insights. The
            // stores are rebuilt through the production read-model path before
            // composition; no view-only fixture values bypass evidence gates.
            let richInsights = FixtureFactory.insightsStore(withEvidence: true)
            let emptyInsights = FixtureFactory.insightsStore(withEvidence: false)
            let tinyQualityInsights = FixtureFactory.insightsStore(withEvidence: false)
            tinyQualityInsights.insightWeekSurface = InsightSurface.make(
                range: .week,
                goal: GoalProgress(goal: 4 * 3_600, achieved: 0, typical: nil),
                rhythm: [],
                rhythmPeak: nil,
                quality: FocusQuality(
                    byWorkType: [WorkTypeShare(workType: .deepWork,
                                               seconds: 30, share: 0.004)],
                    insideSessionShare: 0.004,
                    switchesPerSession: 0.04,
                    sessionCount: 1),
                streak: 0,
                activeDays: 0,
                totalDays: 7,
                tracked: 0,
                comparableTracked: nil)
            let insightStates: [(name: String, store: SessionStore)] = [
                ("evidence-rich", richInsights),
                ("insufficient-data", emptyInsights),
                ("tiny-quality", tinyQualityInsights)
            ]
            for state in insightStates {
                let navigation = MainWindowModel(selectedTab: .insights)
                navigation.insightRange = .week
                let selectedInsights = InsightsView(store: state.store,
                                                     navigation: navigation,
                                                     scrolls: false)
                    .environment(\.colorScheme, scheme)
                    .frame(width: 1_100, height: 780, alignment: .topLeading)
                    .background(Tokens.Colour.ground)
                let insightName = "insights-\(state.name)-"
                    + "\(scheme == .light ? "light" : "dark").png"
                if render(selectedInsights,
                          to: directory.appendingPathComponent(insightName)) {
                    print("  wrote \(insightName)")
                } else {
                    supplementalFailed = true
                    print("  FAILED \(insightName)")
                }
            }

            // Task 9: every group is rendered through the production metadata
            // at both breakpoints and densities. Light/dark is the enclosing
            // loop; filtered goal/privacy searches prove the detail follows the
            // filtered group rather than leaving a stale selection visible.
            let settingsAppearance: AppearancePreference = scheme == .light
                ? .light : .dark
            let settingsVariants: [(name: String, size: CGSize)] = [
                ("wide", CGSize(width: 1_160, height: 1_300)),
                ("narrow", CGSize(width: 980, height: 1_450))
            ]
            for density in InterfaceDensity.allCases {
                for variant in settingsVariants {
                    for section in SettingsSection.allCases {
                        let settings = snapshotSettings(density: density,
                                                        appearance: settingsAppearance)
                        let navigation = MainWindowModel(selectedTab: .settings)
                        navigation.settingsSection = section
                        let selectedSettings = MainWindowView(
                            store: FixtureFactory.store(for: .running),
                            settings: settings,
                            navigation: navigation,
                            settingsScrolls: false)
                            .environment(\.colorScheme, scheme)
                            .frame(width: variant.size.width, height: variant.size.height,
                                   alignment: .topLeading)
                            .background(Tokens.Colour.ground)
                        let settingsName = "settings-\(section.rawValue)-\(density.rawValue)-"
                            + "\(variant.name)-\(scheme == .light ? "light" : "dark").png"
                        if render(selectedSettings,
                                  to: directory.appendingPathComponent(settingsName)) {
                            print("  wrote \(settingsName)")
                        } else {
                            supplementalFailed = true
                            print("  FAILED \(settingsName)")
                        }
                    }

                    for filter in ["goal", "privacy"] {
                        let settings = snapshotSettings(density: density,
                                                        appearance: settingsAppearance)
                        let navigation = MainWindowModel(selectedTab: .settings)
                        navigation.settingsQuery = filter
                        let filtered = MainWindowView(
                            store: FixtureFactory.store(for: .running),
                            settings: settings,
                            navigation: navigation,
                            settingsScrolls: false)
                            .environment(\.colorScheme, scheme)
                            .frame(width: variant.size.width, height: variant.size.height,
                                   alignment: .topLeading)
                            .background(Tokens.Colour.ground)
                        let filteredName = "settings-filter-\(filter)-\(density.rawValue)-"
                            + "\(variant.name)-\(scheme == .light ? "light" : "dark").png"
                        if render(filtered,
                                  to: directory.appendingPathComponent(filteredName)) {
                            print("  wrote \(filteredName)")
                        } else {
                            supplementalFailed = true
                            print("  FAILED \(filteredName)")
                        }
                    }
                }
            }

            // Same-width comparison through the real desktop shell. Unlike
            // the general wide/narrow fixtures, only density changes here, so
            // the shared Focus panel's inset/height difference is observable.
            for density in InterfaceDensity.allCases {
                let densityFocus = densityFocusSnapshot(density: density,
                                                        scheme: scheme)
                let densityName = "main-density-focus-\(density.rawValue)-"
                    + "\(scheme == .light ? "light" : "dark").png"
                if render(densityFocus,
                          to: directory.appendingPathComponent(densityName)) {
                    print("  wrote \(densityName)")
                } else {
                    supplementalFailed = true
                    print("  FAILED \(densityName)")
                }
            }

            // The preference must reach the real ribbon, not merely survive in
            // UserDefaults. This shell snapshot selects Today with labels off.
            let hiddenLabelSettings = snapshotSettings(density: .compact,
                                                       appearance: settingsAppearance,
                                                       showsTimelineLabels: false)
            let hiddenLabelStore = FixtureFactory.store(for: .running)
            hiddenLabelStore.setDashboardVisible(true)
            let hiddenLabelShell = MainWindowView(
                store: hiddenLabelStore,
                settings: hiddenLabelSettings,
                navigation: MainWindowModel(selectedTab: .today),
                todayScrolls: false)
                .environment(\.colorScheme, scheme)
                .frame(width: 1_160, height: 780, alignment: .topLeading)
                .background(Tokens.Colour.ground)
            let hiddenLabelName = "today-timeline-labels-hidden-"
                + "\(scheme == .light ? "light" : "dark").png"
            if render(hiddenLabelShell,
                      to: directory.appendingPathComponent(hiddenLabelName)) {
                print("  wrote \(hiddenLabelName)")
            } else {
                supplementalFailed = true
                print("  FAILED \(hiddenLabelName)")
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

    private static func snapshotSettings(
        density: InterfaceDensity = .comfortable,
        appearance: AppearancePreference = .system,
        showsTimelineLabels: Bool = true
    ) -> SettingsModel {
        let defaults = UserDefaults(
            suiteName: "com.prabesh.focuscontinuity.snapshot.shell"
        ) ?? .standard
        let persistence = PersistenceStore(defaults: defaults)
        persistence.removeAll()
        let diagnostics = SettingsDiagnostics(
            usageAccuracyEpoch: Date(timeIntervalSince1970: 1_700_000_000),
            legacyBackupURL: SessionArchive.defaultDirectory
                .appendingPathComponent("app-usage-v1-backup-1700000000.json"),
            recoverySummary: "Legacy app usage was migrated only after its original bytes were preserved.",
            version: "1.0.0",
            build: "1")
        let model = SettingsModel(store: persistence,
                                  isTrackingEnabled: true,
                                  onChange: {},
                                  onTrackingChanged: { _ in },
                                  diagnostics: diagnostics)
        model.interfaceDensity = density
        model.appearancePreference = appearance
        model.showsTimelineLabels = showsTimelineLabels
        return model
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
