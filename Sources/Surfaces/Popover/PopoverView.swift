import SwiftUI
import AppKit

/// The whole day at a glance, without opening the dashboard. A hero card, then
/// the glance cards, then a footer. Sized by `PopoverMetrics`; the middle
/// scrolls only on screens too short to hold it.
struct PopoverView: View {
    @ObservedObject var store: SessionStore
    @FocusState private var intentFocused: Bool
    @StateObject private var tips = TipCenter()
    /// Measured height of the scrolling middle. A `ScrollView` reports no
    /// intrinsic height, and this panel is sized to its content, so without
    /// measuring it collapsed to nothing.
    @StateObject private var middleHeight = HeightBox()
    var onOpenDashboard: () -> Void = {}

    /// Overridden by the snapshot harness so its output does not depend on the
    /// display the build machine happens to have attached.
    var metricsOverride: PopoverMetrics?

    private var metrics: PopoverMetrics {
        metricsOverride
            ?? PopoverMetrics.fitting(NSScreen.main?.visibleFrame.size
                                      ?? CGSize(width: 1_440, height: 900))
    }

    /// `ScrollView` has no intrinsic content under `ImageRenderer`, so the
    /// snapshot harness renders the panel unscrolled. Same views either way.
    var scrolls: Bool = true

    var body: some View {
        let metrics = self.metrics
        return VStack(alignment: .leading, spacing: metrics.stackSpacing) {
            header
            HeroCard(store: store, intentFocused: $intentFocused,
                     dense: metrics.dense, twoColumn: metrics.twoColumn)
            middle(cap: metrics.scrollCap, twoColumn: metrics.twoColumn)
            PopoverFooter(store: store, onOpenDashboard: onOpenDashboard)
        }
        .padding(metrics.outerPadding)
        .frame(width: metrics.width)
        .background(Tokens.Surface.ground)
        .background(.regularMaterial)
        .tipLayer(tips)
        .onAppear {
            store.refresh()
            intentFocused = store.isIdle
        }
    }

    @ViewBuilder private func middle(cap: CGFloat, twoColumn: Bool) -> some View {
        let content = GlanceCards(store: store, metrics: metrics)
            .frame(maxWidth: .infinity, alignment: .leading)

        if scrolls {
            ScrollView {
                content
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: ContentHeightKey.self,
                                               value: proxy.size.height)
                    })
            }
            .frame(height: min(max(middleHeight.value, 1), cap))
            .onPreferenceChange(ContentHeightKey.self) { middleHeight.value = $0 }
        } else {
            content
        }
    }

    /// At the Mac on the left, the streak on the right. The two day figures that
    /// are not the goal.
    private var header: some View {
        HStack(spacing: Tokens.Space.s) {
            Text("At the Mac today \(Tokens.duration(store.trackedToday))")
                .foregroundStyle(.secondary)
                .explains("atTheMac", "Hands on the keyboard today",
                          "Time you spent actually working the machine since midnight — "
                          + "typing, clicking, scrolling. It stops after "
                          + "\(Int(AppUsageTracker.idleCutoff / 60)) minutes without a "
                          + "keypress or a click, and picks up again the moment you touch "
                          + "it.\n\nThis is not the same as the focus time in the ring, and "
                          + "either one can be the larger. A session runs on the clock from "
                          + "Start to Stop; this number only counts the minutes your hands "
                          + "were busy.")
            Spacer()
            StreakBadge(days: store.streak)
                .explains("streak", "Days in a row",
                          "How many days running you have focused for at least "
                          + "\(Int(FocusConstants.streakMinimum / 60)) minutes. Today joins "
                          + "the count as soon as you pass that. Miss a day and it starts "
                          + "again from one.")
        }
        .font(.caption)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("At the Mac \(Tokens.spent(store.trackedToday)), "
                            + "\(store.streak) day streak")
    }
}
