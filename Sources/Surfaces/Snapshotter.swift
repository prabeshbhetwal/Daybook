import SwiftUI
import AppKit

enum SnapshotScenario: String, CaseIterable, Identifiable, Hashable {
    case focusFirstRun, focusRunning, focusPaused, focusAwaitingDecision, focusSaveFailure
    case todayHistory, todayHistoryExpanded
    case reviewHistorySelection, historySession, historySearch, historySparse
    case insightsEnough, insightsEmpty
    case awardsEarned, awardsEmpty
    case storyDay, storyDayEntry
    case storyShape, storyMeeting, storyLive, storyDecision, storyReport
    case welcomeOpening, welcomeStep
    case settingsGeneral, settingsFocus, settingsCategories, settingsAway, settingsAutomatic
    case settingsActivityRules, settingsTracking, settingsAppearance, settingsData, settingsAdvanced
    case activityRuleAmbiguity, activityRuleAutomatic
    case awayQuick, awayFull, awayQuickFailure, awayFullFailure, rewardEarned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focusFirstRun: return "Focus — first run"
        case .focusRunning: return "Focus — running"
        case .focusPaused: return "Focus — paused"
        case .focusAwaitingDecision: return "Focus — awaiting decision"
        case .focusSaveFailure: return "Focus — answer not saved"
        case .todayHistory: return "Today — history"
        case .todayHistoryExpanded: return "Today — history expanded recap"
        case .reviewHistorySelection: return "History — a day open"
        case .historySession: return "History — a day open and a session picked"
        case .historySearch: return "History — searching"
        case .historySparse: return "History — three recorded days"
        case .insightsEnough: return "Insights — enough evidence"
        case .insightsEmpty: return "Insights — insufficient evidence"
        case .awardsEarned: return "Awards — earned and in progress"
        case .awardsEmpty: return "Awards — nothing earned yet"
        case .storyDay: return "Story — the day"
        case .storyDayEntry: return "Story — an entry opened"
        case .storyShape: return "Story — recorded shape and session actions"
        case .storyMeeting: return "Story — meeting evidence"
        case .storyLive: return "Story — current work first"
        case .storyDecision: return "Story — contextual decision and Undo"
        case .storyReport: return "Story — full session report"
        case .welcomeOpening: return "Welcome — what this is"
        case .welcomeStep: return "Welcome — a step waiting on the reader"
        case .settingsGeneral: return "Settings — General"
        case .settingsFocus: return "Settings — Focus sessions"
        case .settingsCategories: return "Settings — Categories"
        case .settingsAway: return "Settings — Away and breaks"
        case .settingsAutomatic: return "Settings — Automatic and rewards"
        case .settingsTracking: return "Settings — Tracking and apps"
        case .settingsAppearance: return "Settings — Appearance"
        case .settingsData: return "Settings — Data and privacy"
        case .settingsAdvanced: return "Settings — Advanced"
        case .settingsActivityRules: return "Settings — Activity rules"
        case .activityRuleAmbiguity: return "Activity rules — quiet shared-app choice"
        case .activityRuleAutomatic: return "Activity rules — automatic start"
        case .awayQuick: return "Away — quick prompt"
        case .awayFull: return "Away — full prompt"
        case .awayQuickFailure: return "Away — quick prompt save failure"
        case .awayFullFailure: return "Away — full prompt save failure"
        case .rewardEarned: return "Reward — earned"
        }
    }

    var settingsSection: SettingsSection? {
        switch self {
        case .settingsGeneral: return .general
        case .settingsFocus: return .focus
        case .settingsCategories: return .categories
        case .settingsAway: return .away
        case .settingsAutomatic: return .automatic
        case .settingsTracking: return .tracking
        case .settingsAppearance: return .appearance
        case .settingsData: return .data
        case .settingsAdvanced: return .advanced
        case .settingsActivityRules: return .activities
        default: return nil
        }
    }

    var opensStoryEntry: Bool {
        switch self {
        case .storyDayEntry, .storyShape, .storyMeeting: return true
        default: return false
        }
    }

    var presentations: [SnapshotPresentation] {
        switch self {
        case .focusFirstRun, .focusRunning, .focusPaused, .focusAwaitingDecision, .focusSaveFailure,
             .activityRuleAmbiguity, .activityRuleAutomatic:
            return [.minimum, .comfortable, .popover]
        case .awayQuick, .awayFull, .awayQuickFailure, .awayFullFailure, .rewardEarned:
            return [.compact]
        default:
            return [.minimum, .comfortable]
        }
    }

    /// Internal rather than fileprivate: the visual-matrix test asserts that
    /// every global tab owns a rendered surface.
    var tab: AppTab? {
        switch self {
        case .focusFirstRun, .focusRunning, .focusPaused, .focusAwaitingDecision, .focusSaveFailure,
             .activityRuleAmbiguity, .activityRuleAutomatic:
            return .focus
        case .todayHistory, .todayHistoryExpanded:
            return .today
        case .reviewHistorySelection, .historySession, .historySearch, .historySparse:
            return .review
        case .insightsEnough, .insightsEmpty:
            return .insights
        case .awardsEarned, .awardsEmpty:
            return .awards
        case .storyDay, .storyDayEntry,
             .storyShape, .storyMeeting, .storyLive, .storyDecision, .storyReport,
             .welcomeOpening, .welcomeStep:
            return .story
        case .settingsGeneral, .settingsFocus, .settingsCategories, .settingsAway, .settingsAutomatic,
             .settingsTracking, .settingsAppearance, .settingsData, .settingsAdvanced,
             .settingsActivityRules:
            return .settings
        case .awayQuick, .awayFull, .awayQuickFailure, .awayFullFailure, .rewardEarned:
            return nil
        }
    }
}

/// The three acceptance appearances: the two forced schemes and the system
/// default, where no scheme is forced so the host's own appearance is
/// exercised. Reduce Motion is not an appearance a still capture can show and
/// the system flag cannot be forced through the environment; its contract is
/// verified on `Tokens.Motion` directly.
enum SnapshotAppearance: String, CaseIterable, Hashable {
    case light, dark, system

    /// Nil for `.system`: the scheme is then whatever the host applies.
    fileprivate var scheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
    fileprivate var preference: AppearancePreference {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return .system
        }
    }
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
    /// The one made category the Settings — Categories card shows.
    static let fixtureCategoryID = "custom.snapshot.calls"

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
        defer { FixtureFactory.cleanUp() }
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
        // FC_SNAPSHOT_ONLY=welcomeStep renders one scenario; the matrix is
        // six minutes, and a change to one surface needs one look.
        let only = ProcessInfo.processInfo.environment["FC_SNAPSHOT_ONLY"]
        for item in matrix where only == nil || item.scenario.rawValue == only {
            let output = directory.appendingPathComponent(item.filename)
            if render(view(for: item), appearance: item.appearance, to: output) {
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
                              firstRun: coach(for: item.scenario),
                              presentsNativeSheets: false)
            .snapshotAppearance(item.appearance)
            .environment(\.storyEntryInitiallyOpen, item.scenario.opensStoryEntry)
            // The static renderer cannot draw an AppKit drag source.
            .environment(\.storyTilesAreDraggable, false)
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
            .snapshotAppearance(item.appearance)
            .frame(width: metrics.width)
            .fixedSize(horizontal: false, vertical: true)
            .background(Tokens.Colour.ground)
        return AnyView(view)
    }

    private static func compactSurface(for item: SnapshotRender) -> AnyView {
        let reference = Date(timeIntervalSince1970: 1_700_000_000)
        switch item.scenario {
        case .awayQuick, .awayQuickFailure:
            let view = AwayQuickPanel.snapshotView(
                away: 22 * 60,
                range: (reference.addingTimeInterval(-22 * 60), reference),
                note: nil,
                error: item.scenario == .awayQuickFailure ? FixtureFactory.decisionSaveError : nil)
                .snapshotAppearance(item.appearance)
                .fixedSize(horizontal: false, vertical: true)
            return AnyView(view)
        case .awayFull, .awayFullFailure:
            let view = AwayFullPrompt.snapshotView(
                away: 72 * 60,
                range: (reference.addingTimeInterval(-72 * 60), reference),
                note: nil,
                error: item.scenario == .awayFullFailure ? FixtureFactory.decisionSaveError : nil)
                .snapshotAppearance(item.appearance)
            return AnyView(view)
        case .rewardEarned:
            let reward = Reward(kind: .goalReached,
                                title: "4h goal reached",
                                detail: "You've focused 4h 12m today.",
                                symbolName: "checkmark.seal.fill")
            return AnyView(RewardHUD.snapshotView(for: reward)
                .snapshotAppearance(item.appearance)
                .fixedSize(horizontal: false, vertical: true))
        default:
            return AnyView(Text("Unsupported compact snapshot"))
        }
    }

    static func store(for scenario: SnapshotScenario) -> SessionStore {
        switch scenario {
        case .focusFirstRun:
            return FixtureFactory.store(for: .firstRun)
        case .focusRunning:
            return FixtureFactory.store(for: .running)
        case .focusPaused:
            return FixtureFactory.store(for: .paused)
        case .focusAwaitingDecision:
            return FixtureFactory.store(for: .needsResolution)
        case .focusSaveFailure:
            return FixtureFactory.failingDecisionStore()
        case .activityRuleAmbiguity:
            return FixtureFactory.activityRuleStore(ambiguous: true)
        case .activityRuleAutomatic:
            return FixtureFactory.activityRuleStore(ambiguous: false)
        case .todayHistory, .todayHistoryExpanded:
            let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            store.setDashboardVisible(true)
            return store
        case .reviewHistorySelection:
            let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            store.refreshReview(period: .week)
            return store
        case .historySession:
            let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            store.refreshReview()
            return store
        case .historySearch:
            let store = FixtureFactory.insightsStore(withEvidence: true)
            store.refreshReview()
            store.setHistoryQuery("Build")
            return store
        case .historySparse:
            let store = FixtureFactory.store(for: .firstRun, accurateUsage: true)
            store.refreshReview()
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
        case .storyDay, .storyDayEntry:
            let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            store.setDashboardVisible(true)
            return store
        case .storyShape, .storyMeeting, .storyLive, .storyDecision, .storyReport:
            return FixtureFactory.storyInteractionStore(for: scenario)
        case .settingsGeneral, .settingsFocus, .settingsCategories, .settingsAway, .settingsAutomatic,
             .settingsTracking, .settingsAppearance, .settingsData, .settingsAdvanced,
             .settingsActivityRules:
            return FixtureFactory.store(for: .running)
        case .awayQuick, .awayFull, .awayQuickFailure, .awayFullFailure, .rewardEarned:
            return FixtureFactory.store(for: .firstRun)
        case .welcomeOpening, .welcomeStep:
            // The welcome is read on a day with nothing in it, which is the
            // only day it is ever shown on.
            let store = FixtureFactory.store(for: .firstRun)
            store.setDashboardVisible(true)
            return store
        }
    }

    /// A welcome positioned at one of its cards, reached the way a reader
    /// reaches it — begun, then stepped. Nothing here can produce a state the
    /// flow itself cannot.
    static func coach(for scenario: SnapshotScenario) -> FirstRunCoach {
        let coach = FirstRunCoach()
        switch scenario {
        case .welcomeOpening:
            coach.begin()
        case .welcomeStep:
            coach.begin()
            coach.advance()
        default:
            break
        }
        return coach
    }

    static func navigation(for scenario: SnapshotScenario,
                                   store: SessionStore) -> MainWindowModel {
        let navigation = MainWindowModel(opening: scenario.tab ?? .story, store: store)
        switch scenario {
        case .reviewHistorySelection:
            navigation.open(tab: .review)
            if let day = store.historyDays.first(where: { $0.sessions > 0 })?.date {
                navigation.openHistory(day: day)
            }
        case .historySession:
            navigation.open(tab: .review)
            if let day = store.historyDays.first(where: { $0.sessions > 0 })?.date,
               let thread = store.journalThreads(on: day, only: nil).first {
                navigation.selectHistory(session: thread, on: day)
            }
        case .insightsEnough, .insightsEmpty, .historySearch, .historySparse:
            navigation.open(tab: .review)
        case .activityRuleAmbiguity, .activityRuleAutomatic:
            navigation.focusSessionControls()
        case .settingsActivityRules:
            navigation.settingsSection = .activities
        case .storyReport:
            let sessions = store.daySessions.compactMap { entry -> DaySession? in
                if case .session(let session) = entry { return session }
                return nil
            }
            if let session = sessions.max(by: { $0.recordIDs.count < $1.recordIDs.count }) {
                navigation.openReport(for: session)
            }
        case .settingsCategories:
            // The editor open on the made category, the way "Edit categories…"
            // in a picker lands here.
            navigation.openCategoryEditor(.edit(WorkType(rawValue: Snapshotter.fixtureCategoryID)))
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
        // A taller evidence viewport shows the complete Month grid. The real
        // ScrollViews remain in use: sheets keep their production height and
        // cannot grow with the document behind them.
        case .review: height = 1_100
        case .insights: height = 780
        case .awards: height = 900
        case .story: height = 1_200
        case .settings: height = 780
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
        if item.scenario == .settingsActivityRules {
            persistence.activityRules = [
                ActivityRule(name: "Coding", workType: .deepWork,
                    bundleIDs: ["com.example.code", "com.example.shared"], startAfter: 180),
                ActivityRule(name: "Research", workType: .learning,
                    bundleIDs: ["com.example.shared"], startAfter: 300)
            ]
            persistence.activityRuleAutomationEnabled = true
        }
        if item.scenario == .settingsCategories {
            persistence.workTypeDefinitions = [
                WorkTypeDefinition(id: Snapshotter.fixtureCategoryID, name: "Client calls",
                                   symbolName: "phone.fill", hue: .green, countsWhileWatching: true)
            ]
        }
        let dataDirectory = FixtureFactory.scratchDirectory()
        let diagnostics = SettingsDiagnostics(
            usageAccuracyEpoch: Date(timeIntervalSince1970: 1_700_000_000),
            legacyBackupURL: dataDirectory
                .appendingPathComponent("app-usage-v1-backup-1700000000.json"),
            recoverySummary: "Legacy app usage was migrated only after its original bytes were preserved.",
            version: "1.0.0",
            build: "1")
        let model = SettingsModel(store: persistence,
                                  isTrackingEnabled: true,
                                  onChange: {},
                                  onTrackingChanged: { _ in },
                                  // The welcome's replay row hides itself where
                                  // it could do nothing, which hid it from every
                                  // capture too. A no-op route is enough to make
                                  // the row real to a still image.
                                  replayWelcome: {},
                                  diagnostics: diagnostics,
                                  dataDirectory: dataDirectory,
                                  installedAppCatalog: FixtureFactory.installedAppCatalog())
        model.interfaceDensity = density
        model.appearancePreference = item.appearance.preference
        model.showsTimelineLabels = showsTimelineLabels
        return model
    }

    private static func render<V: View>(_ view: V, appearance: SnapshotAppearance,
                                        to url: URL) -> Bool {
        // ImageRenderer substitutes yellow prohibition placeholders for native
        // controls. Host the real AppKit-backed view offscreen instead. This
        // captures our own view, not the user's screen, and needs no permission.
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        guard size.width > 0, size.height > 0 else { return false }
        let frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.contentView = host
        host.frame = frame
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.015))
        host.displayIfNeeded()
        defer { window.orderOut(nil); window.close() }
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return false }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return false }
        do {
            try png.write(to: url)
            return true
        } catch {
            return false
        }
    }
}

private extension View {
    /// Forces a scheme only when the appearance names one; `.system` leaves
    /// the host's own.
    @ViewBuilder func snapshotAppearance(_ appearance: SnapshotAppearance) -> some View {
        if let scheme = appearance.scheme {
            self.environment(\.colorScheme, scheme)
        } else {
            self
        }
    }
}
