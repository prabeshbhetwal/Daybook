import SwiftUI

/// Plain-language explanations of the figures on screen.
///
/// `.help()` was not enough: it renders one grey string, so a two-sentence
/// explanation reads as a wall, and there is no way to tune when it appears.
/// These carry a heading, wrap properly, and are written for someone who has
/// never seen the code. See `TipCenter.delay` for the timing.
///
/// Built on an anchor preference rather than a per-view overlay so the bubble is
/// drawn once, at the root, and cannot be clipped by the 320pt popover window
/// when the thing being explained sits near an edge.
struct Tip {
    let id: String
    /// What the number *is*, in three or four words.
    let title: String
    /// How it is worked out, in sentences. No jargon, no units of measurement
    /// the reader has to look up, no words like "median" without an aside.
    let detail: String
}

/// Which explanation is showing. This is an object because `@State` does not
/// compile in this build — the SDK ships no `SwiftUIMacros` plugin without a
/// full Xcode install — so every piece of view state in this app lives in an
/// `ObservableObject`.
final class TipCenter: ObservableObject {
    @Published var active: String?

    /// How long the pointer must rest before an explanation appears.
    ///
    /// Some delay is essential: with none, every pass of the pointer across the
    /// header flashes a panel, and the panel is large enough that the flicker is
    /// worse than the ignorance it cures. Common practice puts this at 300–500 ms
    /// for web UI and around a second for native macOS help tags; this sits
    /// between the two — long enough that crossing the header is quiet, short
    /// enough that resting on a figure does not feel ignored.
    static let delay: TimeInterval = 0.8
    private var pending: DispatchWorkItem?
    /// Which figure the pending show belongs to. Needed by `leave`.
    private var pendingID: String?

    /// Every figure waits out the full delay, including one entered while
    /// another explanation is already open.
    ///
    /// This deliberately does *not* carry the native-tooltip behaviour where the
    /// first tip is delayed and the rest of a cluster appear at once. Sliding
    /// the pointer down the panel then popped an explanation over every figure
    /// on the way past, which reads as the app shouting rather than answering.
    func enter(_ id: String) {
        pending?.cancel()
        pendingID = id
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.pendingID == id else { return }
            self.active = id
            self.pending = nil
            self.pendingID = nil
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + TipCenter.delay, execute: item)
    }

    /// Only the view that is currently showing may clear it. Without the guard,
    /// leaving view A after entering view B wipes B's tip and nothing shows
    /// while the pointer slides across a dense row of figures.
    func leave(_ id: String) {
        // And only a pending show belonging to *this* view may be cancelled.
        // Moving between neighbouring figures can deliver B's enter before A's
        // leave, so cancelling whatever happens to be pending would throw away
        // the show just scheduled for B and nothing would ever appear.
        if pendingID == id {
            pending?.cancel()
            pending = nil
            pendingID = nil
        }
        if active == id { active = nil }
    }
}

private struct TipAnchor {
    let tip: Tip
    let bounds: Anchor<CGRect>
}

private struct TipKey: PreferenceKey {
    static var defaultValue: [TipAnchor] = []
    static func reduce(value: inout [TipAnchor], nextValue: () -> [TipAnchor]) {
        value.append(contentsOf: nextValue())
    }
}

/// Read through the environment rather than `@EnvironmentObject`, which traps at
/// runtime when nothing has been injected. A figure that is explained on one
/// surface and reused unexplained on another must not crash the menu bar; with a
/// default instance and no layer observing it, the tip simply never appears.
private struct TipCenterKey: EnvironmentKey {
    static let defaultValue = TipCenter()
}

extension EnvironmentValues {
    var tipCenter: TipCenter {
        get { self[TipCenterKey.self] }
        set { self[TipCenterKey.self] = newValue }
    }
}

private struct TipSource: ViewModifier {
    let tip: Tip
    @Environment(\.tipCenter) private var center

    func body(content: Content) -> some View {
        content
            .anchorPreference(key: TipKey.self, value: .bounds) {
                [TipAnchor(tip: tip, bounds: $0)]
            }
            .onHover { $0 ? center.enter(tip.id) : center.leave(tip.id) }
            // The same words reach VoiceOver, which never sees a hover.
            .accessibilityHint(tip.detail)
    }
}

private struct TipBubble: View {
    let tip: Tip

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(tip.title)
                .font(Tokens.Typography.caption)
            Text(tip.detail)
                .font(Tokens.Typography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.leading)
        .padding(.horizontal, Tokens.Space.m)
        .padding(.vertical, Tokens.Space.s)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.control).strokeBorder(.quaternary))
        .shadow(color: .black.opacity(0.28), radius: 10, y: 3)
    }
}

extension View {

    /// Attaches a plain-English explanation to a figure.
    func explains(_ id: String, _ title: String, _ detail: String) -> some View {
        modifier(TipSource(tip: Tip(id: id, title: title, detail: detail)))
    }

    /// Draws whichever explanation is active, and publishes the centre to the
    /// figures beneath. Apply once, at the root of the surface, *after* its
    /// width is fixed — the geometry read here is what keeps the bubble inside
    /// the window.
    func tipLayer(_ center: TipCenter) -> some View {
        modifier(TipLayer(center: center))
            .environment(\.tipCenter, center)
    }
}

private struct TipLayer: ViewModifier {
    /// Observed, not merely read: this is the one place that needs to redraw
    /// when the active tip changes.
    @ObservedObject var center: TipCenter

    /// Wide enough for two sentences without becoming a paragraph, and always
    /// narrower than the popover it sits in.
    private let width: CGFloat = 268

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(TipKey.self) { anchors in
            GeometryReader { proxy in
                if let id = center.active,
                   let match = anchors.first(where: { $0.tip.id == id }) {
                    let rect = proxy[match.bounds]
                    // Below the figure normally; above it once the figure is far
                    // enough down that a bubble underneath would fall out of the
                    // window. Anchoring the ZStack to the matching edge is what
                    // lets this work without knowing the bubble's height.
                    let below = rect.maxY < proxy.size.height * 0.55
                    ZStack(alignment: below ? .topLeading : .bottomLeading) {
                        Color.clear
                        TipBubble(tip: match.tip)
                            .frame(width: min(width, proxy.size.width))
                            .offset(x: clamp(rect.minX, limit: proxy.size.width),
                                    y: below ? rect.maxY + 6
                                             : rect.minY - 6 - proxy.size.height)
                    }
                }
            }
            // Never take the pointer. A bubble that can be hovered steals the
            // hover from the figure underneath it and the pair flickers.
            .allowsHitTesting(false)
        }
    }

    private func clamp(_ x: CGFloat, limit: CGFloat) -> CGFloat {
        max(0, min(x, limit - min(width, limit)))
    }
}


/// One measured height that a view can bind to. `@State` is unavailable on this
/// toolchain — Command Line Tools ships no SwiftUIMacros plugin — so even a
/// single `CGFloat` needs an object behind it.
final class HeightBox: ObservableObject {
    @Published var value: CGFloat = 0
}

/// Reports a subtree's measured height upward.
struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}


/// A single boolean a view can bind to. `@State` is unavailable on this
/// toolchain, so even one flag needs an object behind it.
final class BoolBox: ObservableObject {
    @Published var value = false
}

/// Which row the pointer is over, for lists that highlight on hover. One per
/// list; `@State` is unavailable on this toolchain.
final class HoverBox: ObservableObject {
    @Published var id: String?
}
