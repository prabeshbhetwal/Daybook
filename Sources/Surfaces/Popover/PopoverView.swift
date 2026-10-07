import SwiftUI
import AppKit

/// A compact Focus entry point: shared operational hero, no Today/Review/
/// Insights dashboard, then at most three continuations and explicit routes.
struct PopoverView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var settings: SettingsModel
    @FocusState private var intentFocused: Bool
    @StateObject private var tips = TipCenter()
    /// Measured height of the single overflow body. A `ScrollView` reports no
    /// intrinsic height, and this panel is sized to its content, so without
    /// measuring it collapsed to nothing.
    @StateObject private var contentHeight = HeightBox()
    var onOpenApplication: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    /// Nil where there is no updater: the snapshot harness and previews.
    var onCheckForUpdates: (() -> Void)? = nil
    /// Nil when nothing can route to Settings — the snapshot harness — so the
    /// pickers do not offer a door that opens on nothing.
    var onOpenCategoryEditor: ((CategoryEditorRequest) -> Void)? = nil
    var onOpenActivityEditor: ((ActivityEditorRequest) -> Void)? = nil

    /// Overridden by the snapshot harness so its output does not depend on the
    /// display the build machine happens to have attached.
    var metricsOverride: PopoverMetrics?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var metrics: PopoverMetrics {
        metricsOverride
            ?? PopoverMetrics.fitting(NSScreen.main?.visibleFrame.size
                                      ?? CGSize(width: 1_440, height: 900)) // zoom: fixed, a screen's size
    }

    /// `ScrollView` has no intrinsic content under `ImageRenderer`, so the
    /// snapshot harness renders the panel unscrolled. Same views either way.
    var scrolls: Bool = true

    var body: some View {
        let metrics = self.metrics
        return VStack(alignment: .leading,
                      spacing: settings.interfaceDensity == .compact
                        ? max(Tokens.Space.xs, metrics.stackSpacing - 4.zoomed)
                        : metrics.stackSpacing) {
            operationalContent(cap: bodyCap(metrics))
            PopoverFooter(onOpenApplication: onOpenApplication,
                          onOpenSettings: onOpenSettings,
                          onCheckForUpdates: onCheckForUpdates)
        }
        .padding(settings.interfaceDensity == .compact
                 ? max(Tokens.Space.m, metrics.outerPadding - 4.zoomed)
                 : metrics.outerPadding)
        .frame(width: metrics.width)
        .background(Tokens.Colour.ground)
        .background(.regularMaterial)
        .environment(\.focusInterfaceDensity, settings.interfaceDensity)
        .zoomRoot()
        .environment(\.focusShowsTimelineLabels, settings.showsTimelineLabels)
        .environment(\.openCategoryEditor, onOpenCategoryEditor)
        .environment(\.openActivityEditor, onOpenActivityEditor)
        .tipLayer(tips)
        .onAppear {
            store.refresh()
            intentFocused = store.isIdle
        }
    }

    private func bodyCap(_ metrics: PopoverMetrics) -> CGFloat {
        let padding = settings.interfaceDensity == .compact
            ? max(Tokens.Space.m, metrics.outerPadding - 4.zoomed) : metrics.outerPadding
        return max(1, metrics.maxHeight - (padding * 2) - 52.zoomed - metrics.stackSpacing)
    }

    @ViewBuilder private func operationalContent(cap: CGFloat) -> some View {
        let content = VStack(alignment: .leading, spacing: metrics.stackSpacing) {
            HeroCard(store: store, intentFocused: $intentFocused,
                     dense: metrics.dense)
            if let choice = store.pendingActivityChoice {
                ActivityQuietChoiceView(store: store, choice: choice)
            }
            if let error = store.activityAutomationError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(Tokens.Typography.body).foregroundStyle(Tokens.Colour.danger)
            }
            if store.focusSurfaceComposition.showsContinuationSection {
                ContinueTodaySection(store: store, limit: 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: metrics.dense ? Tokens.Space.m : Tokens.Space.l)
            }
            FocusBreakLine(store: store)
                .padding(.horizontal, Tokens.Space.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Tokens.Motion.animation(Tokens.Motion.swap, reduceMotion: reduceMotion),
                   value: store.isIdle)

        if scrolls {
            ScrollView {
                content
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: ContentHeightKey.self,
                                               value: proxy.size.height)
                    })
            }
            .frame(height: min(max(contentHeight.value, 1), cap))
            .onPreferenceChange(ContentHeightKey.self) { contentHeight.value = $0 }
        } else {
            content
        }
    }

}
