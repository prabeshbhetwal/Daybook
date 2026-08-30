import SwiftUI
import AppKit

enum SnapshotScenario: String, CaseIterable, Identifiable, Hashable {
    case focusFirstRun, focusRunning, focusPaused, focusAwaitingDecision
    case todayHistory, todayHistoryExpanded, todayPast
    case reviewWeek, reviewMonth
    case reviewSelectedFirstDay, reviewSelectedLastDay, reviewHistorySelection
    case insightsEnough, insightsEmpty
    case awardsEarned, awardsEmpty
    case settingsGeneral, settingsFocus, settingsAway, settingsAutomatic
    case settingsTracking, settingsAppearance, settingsData, settingsAdvanced
    case awayQuick, awayFull, rewardEarned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focusFirstRun: return "Focus — first run"
        case .focusRunning: return "Focus — running"
        case .focusPaused: return "Focus — paused"
        case .focusAwaitingDecision: return "Focus — awaiting decision"
        case .todayHistory: return "Today — history"
        case .todayHistoryExpanded: return "Today — history expanded recap"
        case .todayPast: return "Today — past day and integrity"
        case .reviewWeek: return "Review — week"
        case .reviewMonth: return "Review — month"
        case .reviewSelectedFirstDay: return "Review — first day selected"
        case .reviewSelectedLastDay: return "Review — last day selected"
        case .reviewHistorySelection: return "Review — History row selected"
        case .insightsEnough: return "Insights — enough evidence"
        case .insightsEmpty: return "Insights — insufficient evidence"
        case .awardsEarned: return "Awards — earned and in progress"
        case .awardsEmpty: return "Awards — nothing earned yet"
        case .settingsGeneral: return "Settings — General"
        case .settingsFocus: return "Settings — Focus sessions"
        case .settingsAway: return "Settings — Away and breaks"
        case .settingsAutomatic: return "Settings — Automatic and rewards"
        case .settingsTracking: return "Settings — Tracking and apps"
        case .settingsAppearance: return "Settings — Appearance"
        case .settingsData: return "Settings — Data and privacy"
        case .settingsAdvanced: return "Settings — Advanced"
        case .awayQuick: return "Away — quick prompt"
        case .awayFull: return "Away — full prompt"
        case .rewardEarned: return "Reward — earned"
        }
    }

    var settingsSection: SettingsSection? {
        switch self {
        case .settingsGeneral: return .general
        case .settingsFocus: return .focus
        case .settingsAway: return .away
        case .settingsAutomatic: return .automatic
        case .settingsTracking: return .tracking
        case .settingsAppearance: return .appearance
        case .settingsData: return .data
        case .settingsAdvanced: return .advanced
        default: return nil
        }
    }

    var presentations: [SnapshotPresentation] {
        switch self {
        case .focusFirstRun, .focusRunning, .focusPaused, .focusAwaitingDecision:
            return [.minimum, .comfortable, .popover]
        case .awayQuick, .awayFull, .rewardEarned:
            return [.compact]
        default:
            return [.minimum, .comfortable]
        }
    }

    /// Internal rather than fileprivate: the visual-matrix test asserts that
    /// every global tab owns a rendered surface.
    var tab: AppTab? {
        switch self {
        case .focusFirstRun, .focusRunning, .focusPaused, .focusAwaitingDecision:
            return .focus
        case .todayHistory, .todayHistoryExpanded, .todayPast:
            return .today
        case .reviewWeek, .reviewMonth, .reviewSelectedFirstDay,
             .reviewSelectedLastDay, .reviewHistorySelection:
            return .review
        case .insightsEnough, .insightsEmpty:
            return .insights
        case .awardsEarned, .awardsEmpty:
            return .awards
        case .settingsGeneral, .settingsFocus, .settingsAway, .settingsAutomatic,
             .settingsTracking, .settingsAppearance, .settingsData, .settingsAdvanced:
            return .settings
        case .awayQuick, .awayFull, .rewardEarned:
            return nil
        }
    }
}

enum SnapshotAppearance: String, CaseIterable, Hashable {
    case light, dark

    fileprivate var scheme: ColorScheme { self == .light ? .light : .dark }
    fileprivate var preference: AppearancePreference { self == .light ? .light : .dark }
}

enum SnapshotPresentation: String, CaseIterable, Hashable {
    case minimum, comfortable, popover, compact

    var title: String {
        switch self {
        case .minimum: return "Minimum-width shell — 980 pt"
        case .comfortable: return "Comfortable shell — 1,160 pt"
        case .popover: return "Compact menu-bar popover"
        case .compact: return "Compact production surface"
        }
    }
}

struct SnapshotRender: Hashable, Identifiable {
    let scenario: SnapshotScenario
    let appearance: SnapshotAppearance
    let presentation: SnapshotPresentation

    var id: String {
        "\(scenario.rawValue)-\(presentation.rawValue)-\(appearance.rawValue)"
    }

    var filename: String { "\(id).png" }
}

/// A configured product root. Keeping the exact SettingsModel beside the view
/// makes its independently persisted appearance and density lifetime explicit:
/// Gallery cards coexist instead of consulting one mutable shared domain.
struct SnapshotSurface: View {
    let settings: SettingsModel?
    private let root: AnyView

    init(settings: SettingsModel?, root: AnyView) {
        self.settings = settings
        self.root = root
    }

    var body: some View { root }
}

/// One product-surface matrix drives both the live Gallery and PNG output. No
/// legacy Dashboard root or fixture catalogue has a separate rendering path.
@MainActor
enum Snapshotter {

    static let matrix: [SnapshotRender] = SnapshotScenario.allCases.flatMap { scenario in
        scenario.presentations.flatMap { presentation in
            SnapshotAppearance.allCases.map { appearance in
                SnapshotRender(scenario: scenario,
                               appearance: appearance,
                               presentation: presentation)
            }
        }
    }

    /// The screen the compact popover harness pretends to be on. The minimum
    /// desktop screen keeps the rendered panel honest without depending on the
    /// display attached to the build host.
    static let popoverScreen = CGSize(width: 1_000, height: 680)

    /// One canonical root for the density comparison and its structural test.
    /// Task 9's regression continues to use the complete main shell.
    static func densityFocusSnapshot(
        density: InterfaceDensity,
        scheme: ColorScheme
    ) -> some View {
        let appearance: SnapshotAppearance = scheme == .light ? .light : .dark
        let item = SnapshotRender(scenario: .focusRunning,
                                  appearance: appearance,
                                  presentation: .comfortable)
        let settings = snapshotSettings(for: item, density: density)
        return mainShell(for: item, settings: settings)
    }

    /// The production minimum-width Focus shell, used by structural checks for
    /// the compact app mark and tab row together.
    static func narrowFocusSnapshot(scheme: ColorScheme) -> some View {
        let appearance: SnapshotAppearance = scheme == .light ? .light : .dark
        let item = SnapshotRender(scenario: .focusRunning,
                                  appearance: appearance,
                                  presentation: .minimum)
        let settings = snapshotSettings(for: item, density: .compact)
        return mainShell(for: item, settings: settings)
    }

    static func run(directory: URL) -> Bool {
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
        for item in matrix {
            let output = directory.appendingPathComponent(item.filename)
            if render(view(for: item), to: output) {
                wrote += 1
                print("  wrote \(item.filename)")
            } else {
                print("  FAILED \(item.filename)")
            }
        }
        print("\(wrote)/\(matrix.count) product snapshots written to \(directory.path)")
        return wrote == matrix.count
    }

    static func view(for item: SnapshotRender) -> SnapshotSurface {
        switch item.presentation {
        case .minimum, .comfortable:
            let density: InterfaceDensity = item.presentation == .minimum
                ? .compact : .comfortable
            let settings = snapshotSettings(for: item, density: density)
            return SnapshotSurface(settings: settings,
                                   root: AnyView(mainShell(for: item, settings: settings)))
        case .popover:
            let settings = snapshotSettings(for: item, density: .compact)
            return SnapshotSurface(settings: settings,
                                   root: focusPopover(for: item, settings: settings))
        case .compact:
            return SnapshotSurface(settings: nil, root: compactSurface(for: item))
        }
    }

    private static func mainShell(
        for item: SnapshotRender,
        settings: SettingsModel
    ) -> some View {
        let store = store(for: item.scenario)
        let navigation = navigation(for: item.scenario, store: store)
        let size = shellSize(for: item)
        return MainWindowView(store: store,
                              settings: settings,
                              navigation: navigation,
                              focusScrolls: false,
                              todayScrolls: false,
                              reviewScrolls: false,
                              insightsScrolls: false,
                              settingsScrolls: false)
            .environment(\.colorScheme, item.appearance.scheme)
            .environment(\.todayRecapInitiallyExpanded,
                         item.scenario == .todayHistoryExpanded)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
            .background(Tokens.Colour.ground)
    }

    private static func focusPopover(
        for item: SnapshotRender,
        settings: SettingsModel
    ) -> AnyView {
        let metrics = PopoverMetrics.fitting(popoverScreen)
        let store = store(for: item.scenario)
        let view = PopoverView(store: store,
                               settings: settings,
                               metricsOverride: metrics,
                               scrolls: false)
            .environment(\.colorScheme, item.appearance.scheme)
            .frame(width: metrics.width)
            .fixedSize(horizontal: false, vertical: true)
            .background(Tokens.Colour.ground)
        return AnyView(view)
    }

    private static func compactSurface(for item: SnapshotRender) -> AnyView {
        let reference = Date(timeIntervalSince1970: 1_700_000_000)
        switch item.scenario {
        case .awayQuick:
            let view = AwayQuickPanel.snapshotView(
                away: 22 * 60,
                range: (reference.addingTimeInterval(-22 * 60), reference),
                note: nil)
                .environment(\.colorScheme, item.appearance.scheme)
                .fixedSize(horizontal: false, vertical: true)
            return AnyView(view)
        case .awayFull:
            let view = AwayFullPrompt.snapshotView(
                away: 72 * 60,
                range: (reference.addingTimeInterval(-72 * 60), reference),
                note: nil)
                .environment(\.colorScheme, item.appearance.scheme)
            return AnyView(view)
        case .rewardEarned:
            let reward = Reward(kind: .goalReached,
                                title: "4h goal reached",
                                detail: "You've focused 4h 12m today.",
                                symbolName: "checkmark.seal.fill")
            return AnyView(RewardHUD.snapshotView(for: reward)
                .environment(\.colorScheme, item.appearance.scheme)
                .fixedSize(horizontal: false, vertical: true))
        default:
            return AnyView(Text("Unsupported compact snapshot"))
        }
    }

    private static func store(for scenario: SnapshotScenario) -> SessionStore {
        switch scenario {
        case .focusFirstRun:
            return FixtureFactory.store(for: .firstRun)
        case .focusRunning:
            return FixtureFactory.store(for: .running)
        case .focusPaused:
            return FixtureFactory.store(for: .paused)
        case .focusAwaitingDecision:
            return FixtureFactory.store(for: .needsResolution)
        case .todayHistory, .todayHistoryExpanded:
            let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            store.setDashboardVisible(true)
            return store
        case .todayPast:
            let store = FixtureFactory.store(for: .idleWithHistory)
            store.setDashboardVisible(true)
            store.stepDay(by: -1)
            return store
        case .reviewWeek:
            let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            store.refreshReview(period: .week)
            return store
        case .reviewMonth:
            let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            store.refreshReview(period: .month)
            return store
        case .reviewSelectedFirstDay, .reviewSelectedLastDay, .reviewHistorySelection:
            let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            store.refreshReview(period: .week)
            return store
        case .insightsEnough:
            return FixtureFactory.insightsStore(withEvidence: true)
        case .insightsEmpty:
            return FixtureFactory.insightsStore(withEvidence: false)
        case .awardsEarned:
            let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            store.refreshReview(period: .month)
            return store
        case .awardsEmpty:
            return FixtureFactory.store(for: .firstRun)
        case .settingsGeneral, .settingsFocus, .settingsAway, .settingsAutomatic,
             .settingsTracking, .settingsAppearance, .settingsData, .settingsAdvanced:
            return FixtureFactory.store(for: .running)
        case .awayQuick, .awayFull, .rewardEarned:
            return FixtureFactory.store(for: .firstRun)
        }
    }

    /// Days the Review period and the History index both hold. Selecting any
    /// other date would open no detail, which would make the fixture useless.
    private static func selectableReviewDays(_ store: SessionStore) -> [Date] {
        let calendar = Calendar.current
        return store.reviewDays.map(\.date).filter { day in
            store.historyDays.contains { calendar.isDate($0.date, inSameDayAs: day) }
        }
    }

    private static func navigation(for scenario: SnapshotScenario,
                                   store: SessionStore) -> MainWindowModel {
        let navigation = MainWindowModel(selectedTab: scenario.tab ?? .focus)
        switch scenario {
        case .reviewWeek:
            navigation.reviewSection = .week
        case .reviewMonth:
            navigation.reviewSection = .month
        // The first and last selectable bars: the plot edges are exactly where
        // a clipped mark or a colliding annotation would hide.
        case .reviewSelectedFirstDay:
            navigation.reviewSection = .week
            if let day = selectableReviewDays(store).first { navigation.selectReviewDay(day) }
        case .reviewSelectedLastDay:
            navigation.reviewSection = .week
            if let day = selectableReviewDays(store).last { navigation.selectReviewDay(day) }
        case .reviewHistorySelection:
            navigation.reviewSection = .history
            if let day = store.filteredHistoryDays.first?.date {
                navigation.selectReviewDay(day)
            }
        case .insightsEnough, .insightsEmpty:
            navigation.insightRange = .week
        default:
            if let section = scenario.settingsSection {
                navigation.settingsSection = section
            }
        }
        return navigation
    }

    private static func shellSize(for item: SnapshotRender) -> CGSize {
        let width: CGFloat = item.presentation == .minimum ? 980 : 1_160
        let height: CGFloat
        switch item.scenario.tab {
        case .focus: height = item.presentation == .minimum ? 680 : 780
        case .today: height = 1_100
        // Review's unscrolled period evidence is intentionally tall. A generous
        // canvas keeps the fixed shell bands and full log in one artefact;
        // ImageRenderer cannot rasterise the real ScrollView viewport.
        case .review:
            switch item.scenario {
            case .reviewSelectedFirstDay, .reviewSelectedLastDay, .reviewHistorySelection:
                height = 2_800
            default:
                height = 2_400
            }
        case .insights: height = 780
        case .awards: height = 900
        case .settings: height = item.presentation == .minimum ? 1_450 : 1_300
        case nil: height = 780
        }
        return CGSize(width: width, height: height)
    }

    private static func snapshotSettings(
        for item: SnapshotRender,
        density: InterfaceDensity,
        showsTimelineLabels: Bool = true
    ) -> SettingsModel {
        // Every simultaneously alive product card has a stable persistence
        // domain. Reconstructing the same render is harmless because it writes
        // the same complete configuration; a different card cannot see it.
        let suiteName = "com.prabesh.focuscontinuity.snapshot.\(item.id).\(density.rawValue)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Could not create snapshot defaults domain \(suiteName)")
        }
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
        model.appearancePreference = item.appearance.preference
        model.showsTimelineLabels = showsTimelineLabels
        return model
    }

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
