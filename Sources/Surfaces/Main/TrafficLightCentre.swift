import AppKit
import SwiftUI

/// Keeps the window buttons level with the middle of the chrome row. The
/// system sets them in a 28pt title bar; the row is taller than that and grows
/// with the interface zoom, so left alone they ride above its controls.
struct TrafficLightCentre: NSViewRepresentable {
    /// The height of the band the buttons are centred in: the chrome row.
    let height: CGFloat

    func makeNSView(context: Context) -> TrafficLightCentreAnchor { TrafficLightCentreAnchor() }

    func updateNSView(_ nsView: TrafficLightCentreAnchor, context: Context) {
        nsView.height = height
    }
}

final class TrafficLightCentreAnchor: NSView {
    var height: CGFloat = 0 {
        didSet { if height != oldValue { centre() } }
    }
    private weak var host: NSWindow?
    private var observers: [NSObjectProtocol] = []

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // `WindowDormancy` lifts the content out of its window and back; that
        // is not a new window, and what watches the old one must survive it.
        guard let window, window !== host else { return }
        observers.forEach(NotificationCenter.default.removeObserver)
        host = window
        // AppKit lays its title bar out again on each of these, which puts
        // the buttons back where it keeps them.
        let center = NotificationCenter.default
        observers = [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
                     NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification].map { name in
            center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.centre()
            }
        }
        // Outside the view update that is adding this anchor.
        DispatchQueue.main.async { [weak self] in self?.centre() }
    }

    /// The title bar's container grows to the row's height, at the top of the
    /// window, and each button sits in the middle of it. The container is
    /// what takes the clicks, so the buttons cannot just be moved below it.
    private func centre() {
        guard height > 0, let window, !window.styleMask.contains(.fullScreen),
              let close = window.standardWindowButton(.closeButton),
              let titlebar = close.superview, let container = titlebar.superview,
              let frame = container.superview else { return }
        let (band, y) = Self.placement(row: height, button: close.frame.height)
        var box = container.frame
        box.size.height = band
        box.origin.y = frame.isFlipped ? 0 : frame.bounds.height - band
        container.frame = box
        titlebar.frame = container.bounds
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(kind) else { continue }
            button.setFrameOrigin(NSPoint(x: button.frame.origin.x, y: y))
        }
    }

    /// The band the buttons sit in, and how far up it a button's lower edge
    /// is: the band is the row, never shorter than a button, and the button
    /// is in its middle, on a whole point so it is drawn sharp.
    static func placement(row: CGFloat, button: CGFloat) -> (band: CGFloat, y: CGFloat) {
        let band = max(row, button)
        return (band, ((band - button) / 2).rounded())
    }
}
