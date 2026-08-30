import SwiftUI

/// The application window is the story: one chrome row that says what you are
/// looking at and what is running, a story column, and the rail of tiles beside
/// it. Settings and the two secondary surfaces arrive as a sheet from under the
/// chrome rather than as separate destinations, so the story is never replaced.
struct MainWindowView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var settings: SettingsModel
    @ObservedObject var navigation: MainWindowModel
    var focusScrolls = true
    var todayScrolls = true
    var reviewScrolls = true
    var insightsScrolls = true
    var settingsScrolls = true

    var body: some View {
        VStack(spacing: 0) {
            StoryChromeBar(store: store, navigation: navigation)
                .accessibilitySortPriority(3)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            Divider()
            StoryCanvas(store: store, navigation: navigation, scrolls: reviewScrolls)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
                .accessibilitySortPriority(1)
                // The chrome stays visible and usable: a sheet is a layer over
                // the story, not a replacement for the window.
                .overlay { sheet }
        }
        .frame(minWidth: 980, minHeight: 680)
        .background(Tokens.Colour.ground)
        .environment(\.focusInterfaceDensity, settings.interfaceDensity)
        .environment(\.focusShowsTimelineLabels, settings.showsTimelineLabels)
        .preferredColorScheme(settings.preferredColorScheme)
        .accessibilityElement(children: .contain)
    }

    /// The one overlay. It carries Settings, and the two surfaces the story
    /// links to rather than contains, so nothing the app can say is lost.
    @ViewBuilder private var sheet: some View {
        if let presented = navigation.sheet {
            StorySheet(title: presented.title, onClose: { navigation.closeSheet() }) {
                switch presented {
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
}

/// The story canvas: the column and its rail.
struct StoryCanvas: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            .background(Tokens.Colour.surface)
            Divider()
            Group {
                if scrolls {
                    ScrollView { StoryRail(store: store, navigation: navigation) }
                } else {
                    StoryRail(store: store, navigation: navigation)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(width: StoryLayout.railWidth)
            .background(Tokens.Colour.ground)
        }
        .onAppear { refresh(for: navigation.storyScope) }
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
        .padding(Tokens.Space.xxl)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.16))
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
                .accessibilityHidden(true)
            VStack(spacing: 0) {
                HStack {
                    Text(title)
                        .font(Tokens.Typography.sectionTitle)
                    Spacer(minLength: Tokens.Space.m)
                    Button("Done", action: onClose)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, Tokens.Space.xl)
                .padding(.vertical, Tokens.Space.m)
                .background(Tokens.Colour.surface)
                Divider()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: 900, maxHeight: .infinity)
            .background(Tokens.Colour.ground)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.panel, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.panel, style: .continuous)
                .strokeBorder(Tokens.Colour.line))
            .shadow(color: .black.opacity(0.24), radius: 30, y: 12)
            .padding(Tokens.Space.l)
            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
        }
        .onExitCommand(perform: onClose)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isModal)
    }
}
