import SwiftUI

/// The desktop Focus canvas: one operational hero, no KPI grid, followed by a
/// bounded continuation path and one quiet break line.
struct FocusView: View {
    @ObservedObject var store: SessionStore
    /// `ImageRenderer` gives a `ScrollView` no intrinsic content. The repository
    /// snapshot harness opts out of scrolling while rendering the same canvas.
    var scrolls = true
    @FocusState private var intentFocused: Bool

    var body: some View {
        Group {
            if scrolls {
                ScrollView { content }
            } else {
                content
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .background(Tokens.Colour.ground)
        .onAppear {
            store.refresh()
            intentFocused = store.isIdle
        }
    }

    private var content: some View {
        VStack(spacing: Tokens.Space.l) {
            SurfacePanel(showsHeader: false) {
                FocusHero(store: store,
                          intentFocused: $intentFocused,
                          compact: false,
                          wide: true)
            }
            if store.focusSurfaceComposition.showsContinuationSection {
                SurfacePanel(showsHeader: false) {
                    FocusContinuations(store: store, limit: 3)
                }
            }
            FocusBreakLine(store: store)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Tokens.Space.s)
        }
        .frame(maxWidth: 760)
        .padding(Tokens.Space.xl)
        .frame(maxWidth: .infinity, alignment: .top)
    }
}
