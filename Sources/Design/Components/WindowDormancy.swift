import AppKit
import SwiftUI

/// Rests a window's content while the window is off screen.
///
/// SwiftUI keeps the tree of a window it has shown once: the menu bar panel is
/// only ordered out when it closes, and a closed `Window` scene is kept whole.
/// Either way every store change still re-evaluates and redraws it, material
/// blur included, for nobody — measured at about 45 ms a second for the panel
/// while a session ran. Hiding the view saves nothing; taking it out of the
/// window saves all of it.
///
/// So while the window is hidden its content view waits outside it, held
/// here, with a stand-in of the same size in its place. The same view — same
/// state, scroll position and measured height — goes back the moment the
/// window is ordered in, before it draws, and brings itself up to date there.
/// A minimised window is left alone: nothing announces its return from the
/// Dock early enough to restore it unseen.
struct WindowDormancy: NSViewRepresentable {
    /// True when the window comes on screen, false when it closes. A window
    /// minimised to the Dock is still open.
    var onOpenChange: ((Bool) -> Void)?

    func makeNSView(context: Context) -> WindowDormancyAnchor {
        let anchor = WindowDormancyAnchor()
        anchor.onOpenChange = onOpenChange
        return anchor
    }

    func updateNSView(_ nsView: WindowDormancyAnchor, context: Context) {
        nsView.onOpenChange = onOpenChange
    }
}

final class WindowDormancyAnchor: NSView {
    private weak var host: NSWindow?
    private var visibility: NSKeyValueObservation?
    private var observers: [NSObjectProtocol] = []
    var onOpenChange: ((Bool) -> Void)?
    /// The window's real content while it rests, and what had focus in it.
    private var resting: NSView?
    private weak var restingResponder: NSResponder?

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Resting takes this view out of the window too; that is not a new
        // window, and what watches the old one must survive it.
        guard let window, window !== host else { return }
        observers.forEach(NotificationCenter.default.removeObserver)
        host = window
        // Ordering in flips `isVisible` synchronously, ahead of the first
        // draw: the one signal every way of showing a window shares.
        visibility = window.observe(\.isVisible, options: [.new]) { [weak self] window, _ in
            if window.isVisible {
                self?.onOpenChange?(true)
                self?.wake()
            } else {
                self?.restIfHidden()
            }
        }
        let center = NotificationCenter.default
        observers = [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification,
                     NSWindow.didChangeOcclusionStateNotification].map { name in
            center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.restIfHidden()
            }
        }
        // Closed, not hidden with the app or minimised: only a close ends it.
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                            queue: .main) { [weak self] _ in self?.onOpenChange?(false) })
    }

    /// Only once the window has actually left the screen, checked a turn of
    /// the run loop later: a close or a resign can precede the order-out, and
    /// SwiftUI sometimes orders a window out and straight back in.
    private func restIfHidden() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let host = self.host, !host.isVisible, !host.isMiniaturized,
                  self.resting == nil,
                  let content = host.contentView, !(content is RestingStandIn) else { return }
            let standIn = RestingStandIn(standingIn: content)
            // A second route back: whatever shows the window draws it first.
            standIn.onShown = { [weak self] in self?.wake() }
            self.restingResponder = host.firstResponder
            self.resting = content
            host.contentView = standIn
        }
    }

    private func wake() {
        guard let host, let content = resting else { return }
        resting = nil
        // Only undo our own stand-in; anything else put there is not ours.
        guard host.contentView is RestingStandIn else { return }
        host.contentView = content
        if let responder = restingResponder as? NSView, responder.isDescendant(of: content) {
            host.makeFirstResponder(responder)
        }
        restingResponder = nil
    }
}

/// Holds the window's place at the resting content's size, so anything that
/// measures the window while it is hidden reads what it will show.
private final class RestingStandIn: NSView {
    private weak var original: NSView?
    var onShown: (() -> Void)?

    init(standingIn view: NSView) {
        original = view
        super.init(frame: view.frame)
        autoresizingMask = view.autoresizingMask
        needsDisplay = true
    }

    required init?(coder: NSCoder) { nil }

    override func viewWillDraw() {
        super.viewWillDraw()
        if window?.isVisible == true { onShown?() }
    }

    override var fittingSize: NSSize { original?.fittingSize ?? frame.size }
    override var intrinsicContentSize: NSSize { original?.intrinsicContentSize ?? frame.size }
}
