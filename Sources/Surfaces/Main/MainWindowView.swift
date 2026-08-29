import SwiftUI

/// The persistent three-band desktop shell. Global chrome never scrolls; each
/// selected canvas decides whether its own content needs scrolling.
struct MainWindowView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var settings: SettingsModel
    @ObservedObject var navigation: MainWindowModel
    var focusScrolls = true
    var todayScrolls = true

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
        .padding(.vertical, Tokens.Space.s)
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
            interimCanvas(
                title: "Insights",
                detail: "Evidence-backed patterns will appear when enough history exists.",
                symbol: "sparkles"
            )
        case .settings:
            SettingsView(model: settings)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    /// Temporary route destination only. Later tab tasks replace these with
    /// their purpose-built canvases; keeping it here avoids building their UI
    /// inside the shell task.
    private func interimCanvas(title: String, detail: String, symbol: String) -> some View {
        VStack {
            Spacer(minLength: Tokens.Space.xl)
            SurfacePanel(title: nil, showsHeader: false) {
                EmptyState(title, detail: detail, icon: symbol)
            }
            .frame(maxWidth: 520)
            Spacer(minLength: Tokens.Space.xl)
        }
        .padding(Tokens.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
