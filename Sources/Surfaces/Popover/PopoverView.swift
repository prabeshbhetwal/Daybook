import SwiftUI
import AppKit

/// A compact Focus entry point: shared operational hero, no Today/Review/
/// Insights dashboard, then at most three continuations and explicit routes.
struct PopoverView: View {
    @ObservedObject var store: SessionStore
    @FocusState private var intentFocused: Bool
    @StateObject private var tips = TipCenter()
    /// Measured height of the scrolling middle. A `ScrollView` reports no
    /// intrinsic height, and this panel is sized to its content, so without
    /// measuring it collapsed to nothing.
    @StateObject private var middleHeight = HeightBox()
    var onOpenFocus: () -> Void = {}
    var onOpenSettings: () -> Void = {}

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
            HeroCard(store: store, intentFocused: $intentFocused,
                     dense: metrics.dense, twoColumn: metrics.twoColumn)
            middle(cap: metrics.scrollCap, twoColumn: metrics.twoColumn)
            PopoverFooter(onOpenFocus: onOpenFocus,
                          onOpenSettings: onOpenSettings)
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

}
