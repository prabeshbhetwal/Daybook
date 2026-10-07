import AppKit
import SwiftUI

/// Rests the menu bar panel's content while the panel is closed, without
/// taking anything out of its window.
///
/// `WindowDormancy` rests a window by lifting its content view out. The menu
/// bar panel's own hosting view never measures itself again after going back
/// in, so the panel kept whatever height it had before its first rest, and
/// anything taller scrolled. Measured on a real `MenuBarExtra`: rested once,
/// it stayed 330pt tall for 600pt of content and then for 780pt.
///
/// Here the hosting view stays put. While the panel is off screen it draws an
/// empty stand-in of the size it last showed, so nothing in the content runs,
/// and SwiftUI keeps sizing the panel to what it shows.
struct PanelRest<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @StateObject private var shown = BoolBox()
    @StateObject private var size = SizeBox()

    var body: some View {
        Group {
            if shown.value {
                content().background(GeometryReader { proxy in
                    Color.clear
                        .onAppear { size.value = proxy.size }
                        .onChange(of: proxy.size) { _, newSize in size.value = newSize }
                })
            } else {
                Color.clear.frame(width: size.value.width, height: size.value.height)
            }
        }
        .background(WindowVisibility { visible in
            if shown.value != visible { shown.value = visible }
        })
    }
}

/// Reports whether its window is on screen: once when it arrives in a window,
/// then every time the window is ordered in or out.
private struct WindowVisibility: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) { view.onChange = onChange }

    final class Anchor: NSView {
        var onChange: ((Bool) -> Void)?
        private var visibility: NSKeyValueObservation?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            visibility = nil
            guard let window else { return }
            // Arriving happens inside a SwiftUI update, which must not publish.
            // The window is read when the report runs, not now: it can be
            // ordered in meanwhile, and a stale "hidden" landing after that
            // left the open panel showing its empty stand-in.
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                self.onChange?(window.isVisible)
            }
            // Ordering in flips `isVisible` synchronously, ahead of the first
            // draw, so the content is back before the panel shows.
            visibility = window.observe(\.isVisible, options: [.new]) { [weak self] window, _ in
                self?.onChange?(window.isVisible)
            }
        }
    }
}
