import SwiftUI
import AppKit

enum SnapshotScenario: String, CaseIterable, Identifiable, Hashable {
    case focusFirstRun, focusRunning, focusPaused, focusAwaitingDecision
    case todayHistory, todayPast
    case reviewWeek, reviewMonth
    case insightsEnough, insightsEmpty
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
        case .todayPast: return "Today — past day and integrity"
        case .reviewWeek: return "Review — week"
        case .reviewMonth: return "Review — month"
        case .insightsEnough: return "Insights — enough evidence"
        case .insightsEmpty: return "Insights — insufficient evidence"
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

    fileprivate var tab: AppTab? {
        switch self {
        case .focusFirstRun, .focusRunning, .focusPaused, .focusAwaitingDecision:
            return .focus
        case .todayHistory, .todayPast:
            return .today
        case .reviewWeek, .reviewMonth:
            return .review
        case .insightsEnough, .insightsEmpty:
            return .insights
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
        return mainShell(for: SnapshotRender(scenario: .focusRunning,
                                             appearance: appearance,
                                             presentation: .comfortable),
                         densityOverride: density)
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

    static func view(for item: SnapshotRender) -> AnyView {
        switch item.presentation {
        case .minimum, .comfortable:
            return AnyView(mainShell(for: item))
        case .popover:
            return focusPopover(for: item)
        case .compact:
            return compactSurface(for: item)
        }
    }

    private static func mainShell(
        for item: SnapshotRender,
        densityOverride: InterfaceDensity? = nil
    ) -> some View {
        let store = store(for: item.scenario)
        let navigation = navigation(for: item.scenario)
        let density = densityOverride ?? (item.presentation == .minimum ? .compact : .comfortable)
        let settings = snapshotSettings(density: density,
                                        appearance: item.appearance.preference)
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
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
            .background(Tokens.Colour.ground)
    }

    private static func focusPopover(for item: SnapshotRender) -> AnyView {
        let metrics = PopoverMetrics.fitting(popoverScreen)
        let store = store(for: item.scenario)
        let settings = snapshotSettings(density: .compact,
                                        appearance: item.appearance.preference)
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
            let view = AwayAnswerGrid(
                away: 22 * 60,
                range: (reference.addingTimeInterval(-22 * 60), reference),
                compact: true,
                onAnswer: { _ in },
                onReason: { _ in })
                .padding(Tokens.Space.m)
                .frame(width: 300)
                .background(Tokens.Colour.surface,
                            in: RoundedRectangle(cornerRadius: Tokens.Radius.panel,
                                                 style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.panel,
                                          style: .continuous)
                    .strokeBorder(Tokens.Colour.attention.opacity(0.42), lineWidth: 1))
                .environment(\.colorScheme, item.appearance.scheme)
                .fixedSize(horizontal: false, vertical: true)
            return AnyView(view)
        case .awayFull:
            let view = AwayAnswerGrid(
                away: 72 * 60,
                range: (reference.addingTimeInterval(-72 * 60), reference),
                showsCaptions: true,
                onAnswer: { _ in },
                onReason: { _ in })
                .padding(Tokens.Space.xl)
                .frame(width: 520)
                .background(Tokens.Colour.surface,
                            in: RoundedRectangle(cornerRadius: Tokens.Radius.panel + 4,
                                                 style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.panel + 4,
                                          style: .continuous)
                    .strokeBorder(Tokens.Colour.attention.opacity(0.42), lineWidth: 1))
                .environment(\.colorScheme, item.appearance.scheme)
                .fixedSize(horizontal: false, vertical: true)
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
        case .todayHistory:
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
        case .insightsEnough:
            return FixtureFactory.insightsStore(withEvidence: true)
        case .insightsEmpty:
            return FixtureFactory.insightsStore(withEvidence: false)
        case .settingsGeneral, .settingsFocus, .settingsAway, .settingsAutomatic,
             .settingsTracking, .settingsAppearance, .settingsData, .settingsAdvanced:
            return FixtureFactory.store(for: .running)
        case .awayQuick, .awayFull, .rewardEarned:
            return FixtureFactory.store(for: .firstRun)
        }
    }

    private static func navigation(for scenario: SnapshotScenario) -> MainWindowModel {
        let navigation = MainWindowModel(selectedTab: scenario.tab ?? .focus)
        switch scenario {
        case .reviewWeek:
            navigation.reviewSection = .week
        case .reviewMonth:
            navigation.reviewSection = .month
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
        case .review: height = 2_400
        case .insights: height = 780
        case .settings: height = item.presentation == .minimum ? 1_450 : 1_300
        case nil: height = 780
        }
        return CGSize(width: width, height: height)
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
