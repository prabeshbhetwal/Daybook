import SwiftUI

/// The application window is the story: one chrome row that says what you are
/// looking at and what is running. Story, History and Insights are persistent
/// reading workspaces in the content region; Focus, Awards and Settings remain
/// attached panels and return to whichever workspace invoked them.
struct MainWindowView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var settings: SettingsModel
    @ObservedObject var navigation: MainWindowModel
    var focusScrolls = true
    var todayScrolls = true
    var reviewScrolls = true
    var insightsScrolls = true
    var settingsScrolls = true
    /// Offscreen bitmap captures cannot include a native child window. They
    /// retain the real scrollable content but compose its sheet in this viewport.
    var presentsNativeSheets = true

    var body: some View {
      GeometryReader { geometry in
        VStack(spacing: 0) {
            StoryChromeBar(store: store, navigation: navigation)
                .accessibilitySortPriority(3)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            Divider()
            readingWorkspace
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
                .accessibilitySortPriority(1)
        }
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        .overlay {
            // Anchor to the finite window, never a long day's document height.
            if !presentsNativeSheets, let presented = navigation.sheet {
                ZStack {
                    Color.black.opacity(0.14)
                    sheetContent(presented)
                }
            }
        }
        .clipped()
      }
        .frame(minWidth: 980, minHeight: 680)
        .background(StoryStyle.canvas)
        .environment(\.focusInterfaceDensity, settings.interfaceDensity)
        .environment(\.focusShowsTimelineLabels, settings.showsTimelineLabels)
        .environment(\.focusExpandsEntryDetails, settings.expandsEntryDetails)
        .tint(StoryStyle.action)
        .onAppear { navigation.connect(to: store) }
        .sheet(item: Binding(get: { presentsNativeSheets ? navigation.sheet : nil },
                             set: { if $0 == nil { navigation.closeSheet() } })) { presented in
            sheetContent(presented)
                .environment(\.focusInterfaceDensity, settings.interfaceDensity)
                .environment(\.focusShowsTimelineLabels, settings.showsTimelineLabels)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var readingWorkspace: some View {
        switch navigation.workspace {
        case .story:
            StoryCanvas(store: store, navigation: navigation, settings: settings,
                        scrolls: reviewScrolls)
        case .history:
            Group {
                if reviewScrolls {
                    ScrollView {
                        HistoryView(store: store, navigation: navigation)
                            .padding(Tokens.Space.xxl)
                    }
                } else {
                    HistoryView(store: store, navigation: navigation)
                        .padding(Tokens.Space.xxl)
                }
            }
            .background(Tokens.Colour.ground)
            .onAppear {
                store.setReviewVisible(true)
                store.refreshReview()
            }
            .onDisappear { store.setReviewVisible(false) }
        case .insights:
            InsightsView(store: store, navigation: navigation,
                         scrolls: insightsScrolls)
        }
    }

    /// Attached panels. History and Insights remain compatibility enum cases,
    /// but MainWindowModel routes them into the content workspace before this
    /// presentation boundary.
    private func sheetContent(_ presented: StorySheetKind) -> some View {
        StorySheet(title: presented.title, onClose: { navigation.closeSheet() }) {
                switch presented {
                case .focus:
                    FocusView(store: store, scrolls: focusScrolls)
                case .history:
                    Group {
                        if reviewScrolls {
                            ScrollView {
                                HistoryView(store: store, navigation: navigation)
                                    .padding(Tokens.Space.xl)
                            }
                        } else {
                            HistoryView(store: store, navigation: navigation)
                                .padding(Tokens.Space.xl)
                        }
                    }
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
        .frame(width: presented == .settings ? 560 : 880,
               height: presented == .settings
                ? SettingsLayout.sheetHeight(section: navigation.settingsSection,
                                              query: navigation.settingsQuery) : 570)
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
            switch navigation.storyScope {
            case .day: DayStoryColumn(store: store)
            case .week: WeekStoryColumn(store: store, navigation: navigation)
            case .month: MonthStoryColumn(store: store, navigation: navigation)
            }
        }
        .padding(StoryStyle.columnInsets(for: density))
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(Tokens.Motion.animation(Tokens.Motion.rise, reduceMotion: reduceMotion),
                   value: navigation.storyScope)
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
                    Button("Done", action: onClose)
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.cancelAction)
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
