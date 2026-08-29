import SwiftUI

/// The evidence-led narrative of one calendar day. The ribbon is the dominant
/// full-width visual; supporting groups read the same selected-day cache and do
/// not recompute or reinterpret accounting.
struct TodayView: View {
    @ObservedObject var store: SessionStore
    /// `ImageRenderer` gives a `ScrollView` no intrinsic content. The repository
    /// harness renders this exact canvas unscrolled.
    var scrolls = true

    var body: some View {
        Group {
            if scrolls {
                ScrollView { content }
            } else {
                content.frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .background(Tokens.Colour.ground)
        .onAppear {
            if store.period != .day { store.period = .day }
            store.refresh()
            store.setDashboardVisible(true)
        }
        .onDisappear { store.setDashboardVisible(false) }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.l) {
            TodayHeader(store: store)

            // Qualification precedes every app-use figure it governs: ribbon,
            // inspector, At the Mac rows and recap.
            if let note = store.selectedDayIntegrityNote {
                IntegrityNotice(note)
            }

            SurfacePanel(showsHeader: false) {
                SectionHeader(title: "Time ribbon",
                              trailing: "app activity · focus brackets beneath")
                DayTimelineView(store: store, dominant: true, showsDetail: false,
                                usesTodaySelection: true)
                if let inspector = store.todayInspector {
                    TodayInspector(data: inspector) { store.clearTodaySelection() }
                        .transition(.opacity)
                }
            }

            HStack(alignment: .top, spacing: Tokens.Space.l) {
                SurfacePanel(showsHeader: false) {
                    SessionsCard(
                        entries: store.daySessions,
                        selected: store.selectedSession,
                        watchingSessionID: watchingSessionID,
                        onHover: { store.hoverSession($0) },
                        onSelect: { store.selectTodaySession($0) })
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                SurfacePanel(showsHeader: false) {
                    TodayAppsList(apps: store.rankedApps, store: store,
                                  selectedBundleID: store.todayInspector?.kind == .app
                                      ? store.todayInspector?.bundleID : nil)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .fixedSize(horizontal: false, vertical: true)

            TodayRecap(store: store)
        }
        .padding(Tokens.Space.xxl)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onExitCommand { store.clearTodaySelection() }
        .animation(.easeInOut(duration: 0.18), value: store.dayOffset)
        .animation(.easeInOut(duration: 0.16), value: store.todayInspector)
    }

    private var watchingSessionID: UUID? {
        guard store.isToday,
              FocusSurfaceMode(state: store.state) == .watching else { return nil }
        return store.daySessions.compactMap { entry -> DaySession? in
            if case .session(let session) = entry { return session }
            return nil
        }.last(where: \.isRunning)?.id
    }
}
