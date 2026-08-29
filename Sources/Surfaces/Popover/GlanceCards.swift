import SwiftUI

/// Focus-only supporting content for the menu-bar popover. Today timelines,
/// app rankings and report metrics belong to their desktop tabs.
struct GlanceCards: View {
    @ObservedObject var store: SessionStore
    let metrics: PopoverMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.stackSpacing) {
            ContinueTodaySection(store: store, limit: 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: metrics.dense ? Tokens.Space.m : Tokens.Space.l)
            FocusBreakLine(store: store)
                .padding(.horizontal, Tokens.Space.xs)
        }
    }
}
