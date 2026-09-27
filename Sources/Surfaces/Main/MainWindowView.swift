import SwiftUI

/// The application window is the story: one chrome row that says what you are
/// looking at and what is running. Story, History and Insights are persistent
/// reading workspaces in the content region; session controls expand below the
/// chrome, while Awards and Settings remain attached panels.
struct MainWindowView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var settings: SettingsModel
    @ObservedObject var navigation: MainWindowModel
    /// The welcome. Inert unless it has been begun, which is why every surface
    /// that builds this window can leave it at its default.
    @ObservedObject var firstRun = FirstRunCoach()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var focusScrolls = true
    var reviewScrolls = true
    var insightsScrolls = true
    var settingsScrolls = true
    /// Offscreen bitmap captures cannot include a native child window. They
    /// retain the real scrollable content but compose its sheet in this viewport.
    var presentsNativeSheets = true
    @StateObject private var windowSize = SizeBox()

    var body: some View {
      GeometryReader { geometry in
        VStack(spacing: 0) {
            StoryChromeBar(store: store, navigation: navigation,
                           sessionControlsVisible: sessionControlsVisible)
                .accessibilitySortPriority(3)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
                // Above the strip, so the strip slides out from beneath it.
                .zIndex(1)
            Divider()
                .zIndex(1)
            if sessionControlsVisible {
                SessionControlStrip(store: store, settings: settings, navigation: navigation)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                    .transition(Tokens.Motion.transition(Tokens.Motion.slideDown,
                                                         reduceMotion: reduceMotion))
            }
            readingWorkspace
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
                .accessibilitySortPriority(1)
        }
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        .overlayPreferenceValue(CoachAnchorKey.self) { anchors in
            GeometryReader { coachSpace in
                WelcomeCoachOverlay(coach: firstRun, anchors: anchors, proxy: coachSpace)
            }
        }
        .overlay {
            // Anchor to the finite window, never a long day's document height.
            if !presentsNativeSheets, let presented = navigation.sheet {
                ZStack {
                    Color.black.opacity(0.14)
                    sheetContent(presented, within: geometry.size)
                }
            }
        }
        .overlay {
            // The report is always drawn here, never as a native sheet: it
            // must close on Escape and on a click outside, which a sheet
            // does not do.
            if let session = navigation.reportSession {
                SessionReportOverlay(store: store, session: session, windowSize: geometry.size,
                                     onClose: { navigation.closeReport() })
                    .zIndex(2)
            }
        }
        .clipped()
        // The native sheet is presented outside this reader; it sizes itself
        // to the window it will cover from the size noted here.
        .onAppear { windowSize.value = geometry.size }
        .onChange(of: geometry.size) { windowSize.value = $0 }
      }
        .frame(minWidth: 980, minHeight: 680)
        .background(StoryStyle.canvas)
        .environment(\.focusInterfaceDensity, settings.interfaceDensity)
        .environment(\.focusShowsTimelineLabels, settings.showsTimelineLabels)
        .environment(\.focusExpandsEntryDetails, settings.expandsEntryDetails)
        .environment(\.openSessionReport) { session in navigation.openReport(for: session) }
        .environment(\.sessionControlsVisible, sessionControlsVisible)
        .environment(\.openActivityEditor, openActivityEditor)
        .environment(\.openCategoryEditor, openCategoryEditor)
        .tint(StoryStyle.action)
        .animation(Tokens.Motion.animation(Tokens.Motion.reveal,
                                           reduceMotion: reduceMotion),
                   value: sessionControlsVisible)
        .onAppear {
            navigation.connect(to: store)
            firstRun.observe(coachSignals)
        }
        .onChange(of: coachSignals) { firstRun.observe($0) }
        .sheet(item: Binding(get: { presentsNativeSheets ? navigation.sheet : nil },
                             set: { if $0 == nil { navigation.closeSheet() } })) { presented in
            sheetContent(presented, within: windowSize.value == .zero ? nil : windowSize.value)
                .environment(\.focusInterfaceDensity, settings.interfaceDensity)
                .environment(\.focusShowsTimelineLabels, settings.showsTimelineLabels)
                // A native sheet is its own view tree: the panels the window
                // opens must be reachable from it too, or a category menu in
                // Settings loses its Add and Edit items.
                .environment(\.openCategoryEditor, openCategoryEditor)
                .environment(\.openActivityEditor, openActivityEditor)
        }
        .accessibilityElement(children: .contain)
    }

    private var sessionControlsVisible: Bool {
        SessionControlsVisibility.isVisible(expanded: navigation.sessionControlsExpanded,
                                            pinned: settings.sessionControlsPinned)
    }

    private func openActivityEditor(_ request: ActivityEditorRequest) {
        ActivityEditorPanel.shared.show(request, store: store)
    }

    /// A category added from any menu becomes the one the next session uses.
    private func openCategoryEditor(_ request: CategoryEditorRequest) {
        CategoryEditorPanel.shared.show(request, model: settings) { definition, wasNew in
            if wasNew { store.workType = definition.workType }
        }
    }

    /// What the welcome's steps are waiting on, gathered from the same state
    /// every other surface reads. Nothing here is staged for the welcome.
    private var coachSignals: FirstRunSignals {
        FirstRunSignals(
            sessionControlsVisible: sessionControlsVisible,
            sessionRunning: store.state.isRunning,
            otherAppRecorded: !store.rankedApps.isEmpty)
    }

    private var readingWorkspace: some View {
        Group {
            switch navigation.workspace {
            case .story:
            StoryCanvas(store: store, navigation: navigation, settings: settings,
                        scrolls: reviewScrolls)
            case .history, .insights:
                InsightsView(store: store, navigation: navigation,
                             scrolls: insightsScrolls)
                    .onAppear {
                        store.setReviewVisible(true)
                        store.refreshReview()
                    }
                    .onDisappear { store.setReviewVisible(navigation.storyScope.period != nil) }
            }
        }
        .transition(Tokens.Motion.transition(Tokens.Motion.unfold, reduceMotion: reduceMotion))
    }

    /// Attached panels. Focus, History and Insights remain compatibility enum
    /// cases, but MainWindowModel routes them before this presentation boundary.
    private func sheetContent(_ presented: StorySheetKind, within window: CGSize?) -> some View {
        let size = SettingsLayout.sheetSize(for: presented, within: window)
        return sheetBody(presented)
            .frame(width: size.width, height: size.height)
    }

    private func sheetBody(_ presented: StorySheetKind) -> some View {
        StorySheet(title: presented.title, onClose: { navigation.closeSheet() }) {
                switch presented {
                case .focus:
                    FocusView(store: store, scrolls: focusScrolls)
                case .history:
                    InsightsView(store: store, navigation: navigation, scrolls: insightsScrolls)
                    .onAppear {
                        store.setReviewVisible(true)
                        store.refreshReview()
                    }
                    .onDisappear {
                        store.setReviewVisible(navigation.storyScope.period != nil)
                    }
                case .settings:
                    SettingsView(model: settings, navigation: navigation,
                                 scrolls: settingsScrolls)
                case .insights:
                    InsightsView(store: store, navigation: navigation,
                                 scrolls: insightsScrolls)
                case .awards:
                    AwardsView(store: store, scrolls: insightsScrolls)
                }
        }
    }
}

/// The story canvas: the column and its rail.
struct StoryCanvas: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    @ObservedObject var settings: SettingsModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.focusInterfaceDensity) private var density
    var scrolls = true

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Group {
                if scrolls {
                    ScrollView { column }
                } else {
                    column.frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(StoryStyle.canvas)
            Divider()
            Group {
                if scrolls {
                    ScrollView { StoryRail(store: store, navigation: navigation,
                                       settings: settings) }
                } else {
                    StoryRail(store: store, navigation: navigation, settings: settings)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(width: StoryLayout.railWidth)
            .background(StoryStyle.rail)
            .coachAnchor(.rail)
            .animation(Tokens.Motion.animation(Tokens.Motion.swap, reduceMotion: reduceMotion),
                       value: readingKey)
        }
        .onAppear {
            navigation.connect(to: store)
            refresh(for: navigation.storyScope)
        }
        .onDisappear {
            store.setDashboardVisible(false)
            store.setReviewVisible(false)
        }
        .onChange(of: navigation.storyScope) { refresh(for: $0) }
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xl) {
            Group {
                switch navigation.storyScope {
                case .day: DayStoryColumn(store: store)
                case .week: WeekStoryColumn(store: store, navigation: navigation)
                case .month: MonthStoryColumn(store: store, navigation: navigation)
                }
            }
            // A new period is a new reading, so it is a new view: stepping
            // forward nudges it in from the trailing edge, back from the
            // leading, and a change of scope settles in place.
            .id(readingKey)
            .transition(Tokens.Motion.transition(readingTransition, reduceMotion: reduceMotion))
        }
        .padding(StoryStyle.columnInsets(for: density))
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(Tokens.Motion.animation(Tokens.Motion.swap, reduceMotion: reduceMotion),
                   value: readingKey)
    }

    private var readingKey: String {
        let period = navigation.storyScope == .day ? store.dayLabel : store.reviewPeriodLabel
        return "\(navigation.storyScope)-\(period)"
    }

    private var readingTransition: AnyTransition {
        switch navigation.lastPeriodStep {
        case let step where step > 0: return Tokens.Motion.slide(from: .trailing)
        case let step where step < 0: return Tokens.Motion.slide(from: .leading)
        default: return Tokens.Motion.unfold
        }
    }

    private func refresh(for scope: StoryScope) {
        store.setDashboardVisible(true)
        if let period = scope.period {
            store.setReviewVisible(true)
            store.refreshReview(period: period)
        } else {
            store.setReviewVisible(false)
        }
    }
}

/// A sheet that arrives from under the chrome, over a scrim. Escape and the
/// close control both dismiss it; nothing behind it is unloaded.
struct StorySheet<Content: View>: View {
    let title: String
    let onClose: () -> Void
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) {
                HStack {
                    Text(title)
                        .font(Tokens.Typography.sectionTitle)
                    Spacer(minLength: Tokens.Space.m)
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .frame(width: AccessibilityMetrics.minimumTargetSize,
                                   height: AccessibilityMetrics.minimumTargetSize)
                    }
                        .buttonStyle(StoryPressStyle())
                        .keyboardShortcut(.cancelAction)
                        .help("Close \(title)")
                        .accessibilityLabel("Close \(title)")
                }
                .padding(.horizontal, Tokens.Space.xl)
                .padding(.vertical, Tokens.Space.m)
                .background(Tokens.Colour.surface)
                Divider()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Tokens.Colour.ground)
        .onExitCommand(perform: onClose)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isModal)
    }
}

/// The window's size, for a sheet presented outside its geometry reader.
final class SizeBox: ObservableObject {
    @Published var value: CGSize = .zero
}
