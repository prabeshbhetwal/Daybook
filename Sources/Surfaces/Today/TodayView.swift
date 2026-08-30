import SwiftUI

/// Today's invariant reading sequence. A qualification that appears after the
/// figures it governs has already misled the reader, so its position is part of
/// the contract rather than a layout preference.
enum DaySurfaceOrder: CaseIterable {
    case header, qualification, timeline, selectedDetail, supportingGroups, recap

    static func visible(hasQualification: Bool, hasSelection: Bool) -> [DaySurfaceOrder] {
        allCases.filter { section in
            switch section {
            case .qualification: return hasQualification
            case .selectedDetail: return hasSelection
            default: return true
            }
        }
    }
}

/// The evidence-led narrative of one calendar day. The ribbon is the dominant
/// full-width visual; supporting groups read the same selected-day cache and do
/// not recompute or reinterpret accounting.
struct TodayView: View {
    @ObservedObject var store: SessionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    TodayInspector(
                        data: inspector,
                        appSessions: inspector.bundleID.map(store.sessions(for:)) ?? []
                    ) { store.clearTodaySelection() }
                        .transition(.opacity)
                }
            }

            ViewThatFits(in: .horizontal) {
                supportingGroups(horizontal: true)
                supportingGroups(horizontal: false)
            }

            TodayRecap(store: store)
        }
        .padding(Tokens.Space.xxl)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onExitCommand { Self.handleEscape(in: store) }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: store.dayOffset)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: store.todayInspector)
    }

    /// The exact action behind Escape. Browsing scope is deliberately distinct
    /// from transient inspection, so this must never call `goToToday` or change
    /// `dayOffset`.
    static func handleEscape(in store: SessionStore) {
        store.clearTodaySelection()
    }

    @ViewBuilder
    private func supportingGroups(horizontal: Bool) -> some View {
        let sessions = SurfacePanel(showsHeader: false) {
            SessionsCard(
                entries: store.daySessions,
                selected: store.selectedSession,
                watchingSessionID: watchingSessionID,
                onHover: { store.hoverSession($0) },
                onSelect: { store.selectTodaySession($0) })
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)

        let apps = SurfacePanel(showsHeader: false) {
            TodayAppsList(apps: store.rankedApps, store: store,
                          selectedBundleID: store.todayInspector?.kind == .app
                              ? store.todayInspector?.bundleID : nil)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)

        if horizontal {
            HStack(alignment: .top, spacing: Tokens.Space.l) { sessions; apps }
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: Tokens.Space.l) { sessions; apps }
                .fixedSize(horizontal: false, vertical: true)
        }
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
