import AppKit
import SwiftUI

/// Keeps a window big enough for the zoom it is open at.
///
/// A view's minimum size follows the zoom by itself, but a window that is
/// already open stays as large as it was, so a zoom-up leaves it too small for
/// its content. This anchor grows its window to the new minimum when the zoom
/// changes, keeping the top-left corner and moving the window back onto the
/// screen if the growth pushed it off. It never shrinks one.
///
/// It also reports the visible size of the window's screen, which a view needs
/// to cap its own minimum (see `minimum(base:screenVisible:)`).
struct ZoomWindowFit: NSViewRepresentable {
    /// The window's content minimum at 100%.
    let base: CGSize
    /// Told the visible size of the window's screen when it is found, and
    /// again when the window moves to another.
    let onScreen: (CGSize) -> Void

    /// The content minimum at the current zoom, held to a screen's visible
    /// size: the one the window is on once it is known (`screenVisible` not
    /// zero), else the main screen's, else no cap. Read while a view draws.
    static func minimum(base: CGSize, screenVisible: CGSize = .zero) -> CGSize {
        let visible = screenVisible == .zero
            ? NSScreen.main?.visibleFrame.size ?? CGSize(width: CGFloat.infinity, height: CGFloat.infinity)
            : screenVisible
        return InterfaceZoom.windowMinimum(base: base, scale: ZoomModel.shared.scale, visible: visible)
    }

    func makeNSView(context: Context) -> ZoomWindowFitAnchor {
        let anchor = ZoomWindowFitAnchor()
        anchor.base = base
        anchor.onScreen = onScreen
        return anchor
    }

    func updateNSView(_ nsView: ZoomWindowFitAnchor, context: Context) {
        nsView.base = base
        nsView.onScreen = onScreen
    }
}

final class ZoomWindowFitAnchor: NSView {
    var base = CGSize.zero
    var onScreen: ((CGSize) -> Void)?
    private weak var host: NSWindow?
    private var reported: CGSize?
    private var follower: ZoomFollower?
    private var screenObserver: NSObjectProtocol?

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // `WindowDormancy` lifts the content out of its window and back; that
        // is not a new window, and what watches the old one must survive it.
        guard let window, window !== host else { return }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        host = window
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification, object: window, queue: .main) { [weak self] _ in
                self?.reportScreen()
        }
        follower = follower ?? ZoomFollower { [weak self] in self?.fit() }
        reportScreen()
    }

    /// Outside the view update that is adding this anchor: a change to the
    /// view's own state in the middle of one is not allowed.
    private func reportScreen() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let visible = self.host?.visibleScreenFrame?.size, visible != self.reported else { return }
            self.reported = visible
            self.onScreen?(visible)
        }
    }

    /// The window grown to the zoom's minimum.
    private func fit() {
        guard let window = host, !window.styleMask.contains(.fullScreen),
              let visible = window.visibleScreenFrame else { return }
        window.growContent(toFit: InterfaceZoom.windowMinimum(
            base: base, scale: ZoomModel.shared.scale, visible: visible.size))
    }
}

extension NSWindow {
    /// The visible area of the window's screen, the main screen's when the
    /// window is on none (an ordered-out window may report no screen).
    var visibleScreenFrame: CGRect? { (screen ?? NSScreen.main)?.visibleFrame }

    /// Grown to hold content of at least `minimum`, never shrunk: the
    /// top-left corner stays, and the window moves back onto its screen.
    func growContent(toFit minimum: CGSize) {
        guard let visible = visibleScreenFrame else { return }
        move(to: InterfaceZoom.grownFrame(frame, toFit: frameSize(forContent: minimum), within: visible))
    }

    /// Resized to hold content of exactly `size`, larger or smaller: the
    /// top-left corner stays, and the window moves back onto its screen.
    func resizeContent(to size: CGSize) {
        guard let visible = visibleScreenFrame else { return }
        move(to: InterfaceZoom.resized(frame, to: frameSize(forContent: size), within: visible))
    }

    /// The window's frame for content of `size`, which carries the title bar
    /// the way `NSWindow(contentRect:)` does.
    private func frameSize(forContent size: CGSize) -> CGSize {
        frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
    }

    private func move(to target: CGRect) {
        if target != frame { setFrame(target, display: true) }
    }
}
