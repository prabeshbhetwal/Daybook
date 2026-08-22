import SwiftUI

/// The roomier version of the same hierarchy. A plain window in slice 1 — there
/// is exactly one destination until Insights exists, and an empty sidebar is
/// worse than no sidebar.
struct TodayView: View {
    @ObservedObject var store: SessionStore
    @FocusState private var intentFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.xl) {
                hero
                rhythm
                stats
            }
            .padding(Tokens.Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
        .onAppear { store.refresh() }
    }

    @ViewBuilder private var hero: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            if let away = store.pendingAway {
                ResolveCard(away: away,
                            onMerge: { store.resolve(.mergeTime) },
                            onBreak: { store.resolve(.continueSession) },
                            onDiscard: { store.resolve(.resetTimer) })
            } else if store.isIdle {
                Text("Ready when you are")
                    .font(.largeTitle.weight(.semibold))
                HStack(spacing: Tokens.Space.m) {
                    IntentField(text: $store.intent) { store.start() }
                        .focused($intentFocused)
                        .frame(maxWidth: 320)
                    WorkTypePicker(selection: $store.workType)
                    StartButton { store.start() }
                        .frame(maxWidth: 200)
                }
            } else {
                LiveTimer(seconds: store.elapsed,
                          paused: store.isPaused,
                          intent: store.activeIntent)
                HStack(spacing: Tokens.Space.s) {
                    Button(store.isPaused ? "Resume" : "Pause") { store.togglePause() }
                    Button("Stop") { store.stop() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var rhythm: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Text("This week")
                .font(.headline)
            WeekChart(bars: store.weekBars, height: 120)
        }
    }

    private var stats: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Tokens.Space.m),
                                 count: 4),
                  spacing: Tokens.Space.m) {
            StatTile(title: "Focused today",
                     value: Tokens.duration(store.todayTotal),
                     symbol: "timer")
            StatTile(title: "Current streak",
                     value: store.streak == 1 ? "1 day" : "\(store.streak) days",
                     symbol: "flame.fill")
            StatTile(title: "Sessions today",
                     value: "\(store.sessionsToday)",
                     symbol: "checkmark.circle.fill")
            StatTile(title: "Longest today",
                     value: Tokens.duration(store.longestToday),
                     symbol: "arrow.up.right")
        }
    }
}
