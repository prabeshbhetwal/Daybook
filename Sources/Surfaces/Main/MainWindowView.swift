import SwiftUI

/// The persistent three-band desktop shell. Global chrome never scrolls; each
/// selected canvas decides whether its own content needs scrolling.
struct MainWindowView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var settings: SettingsModel
    @ObservedObject var navigation: MainWindowModel
    var focusScrolls = true
    var todayScrolls = true
    var settingsScrolls = true

    var body: some View {
        VStack(spacing: 0) {
            MainWindowHeader(store: store, navigation: navigation)
            Divider()
            tabBand
            Divider()
            selectedCanvas
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 980, minHeight: 680)
        .background(Tokens.Colour.ground)
        .environment(\.focusInterfaceDensity, settings.interfaceDensity)
        .environment(\.focusShowsTimelineLabels, settings.showsTimelineLabels)
        .preferredColorScheme(settings.preferredColorScheme)
    }

    private var tabBand: some View {
        HStack {
            Spacer(minLength: 0)
            TabRail(selectedTab: $navigation.selectedTab) { tab in
                navigation.select(tab)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Tokens.Space.xl)
        .padding(.vertical, settings.interfaceDensity == .compact
                 ? Tokens.Space.xs : Tokens.Space.s)
    }

    @ViewBuilder private var selectedCanvas: some View {
        switch navigation.selectedTab {
        case .focus:
            FocusView(store: store, scrolls: focusScrolls)
        case .today:
            TodayView(store: store, scrolls: todayScrolls)
        case .review:
            ReviewView(store: store, navigation: navigation)
        case .insights:
            InsightsView(store: store, navigation: navigation)
        case .settings:
            SettingsView(model: settings, navigation: navigation,
                         scrolls: settingsScrolls)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

}
