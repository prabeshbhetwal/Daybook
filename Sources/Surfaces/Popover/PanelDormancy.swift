import AppKit
import SwiftUI

/// Rests a panel's content while the panel is off screen.
///
/// A window that has been ordered out keeps its SwiftUI tree live: every store
/// change re-evaluates and redraws it, material blur included, for nobody.
/// The menu bar panel is ordered out, not destroyed, once it has been opened,
/// so from then on it cost more each second than everything else the app does
/// — measured at about 45 ms a second while a session ran. Hiding the view
/// saves nothing; taking it out of the window saves all of it.
///
/// So while the panel is hidden its content view waits outside the window,
/// held here, with a stand-in of the same size in its place. The same view —
/// same state, scroll position and measured height — goes back the moment the
/// panel is shown, before it draws, and brings itself up to date there.
struct PanelDormancy: NSViewRepresentable {
    func makeNSView(context: Context) -> PanelDormancyAnchor { PanelDormancyAnchor() }
    func updateNSView(_ nsView: PanelDormancyAnchor, context: Context) {}
}

final class PanelDormancyAnchor: NSView {
    private weak var panel: NSWindow?
    private var observers: [NSObjectProtocol] = []
    /// The panel's real content while it rests, and what had focus in it.
    private var resting: NSView?
    private weak var restingResponder: NSResponder?

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Resting takes this view out of the window too; that is not a new
        // panel, and the observers on the old one must survive it.
        guard let window, window !== panel else { return }
        observers.forEach(NotificationCenter.default.removeObserver)
        panel = window
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window,
                               queue: .main) { [weak self] _ in self?.wake(force: true) },
            center.addObserver(forName: NSWindow.didUpdateNotification, object: window,
                               queue: .main) { [weak self] _ in self?.wake(force: false) },
            center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window,
                               queue: .main) { [weak self] _ in
                self?.wake(force: false)
                self?.restIfHidden()
            },
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: window,
                               queue: .main) { [weak self] _ in self?.restIfHidden() }
        ]
    }

    /// Only once the panel has actually left the screen: resigning key can
    /// precede the order-out by a turn of the run loop, and a panel still
    /// showing must keep its content.
    private func restIfHidden() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, !panel.isVisible, self.resting == nil,
                  let content = panel.contentView, !(content is RestingStandIn) else { return }
            self.restingResponder = panel.firstResponder
            self.resting = content
            panel.contentView = RestingStandIn(standingIn: content)
        }
    }

    /// Becoming key means the panel is being presented, so the content goes
    /// back before the first frame. Any update or occlusion change that finds
    /// the panel visible is a second route back, never a first.
    private func wake(force: Bool) {
        guard let panel, let content = resting, force || panel.isVisible else { return }
        resting = nil
        // Only undo our own stand-in; anything else put there is not ours.
        guard panel.contentView is RestingStandIn else { return }
        panel.contentView = content
        if let responder = restingResponder as? NSView, responder.isDescendant(of: content) {
            panel.makeFirstResponder(responder)
        }
        restingResponder = nil
    }
}

/// Holds the panel's place at the resting content's size, so anything that
/// measures the panel while it is hidden reads what it will show.
private final class RestingStandIn: NSView {
    private weak var original: NSView?

    init(standingIn view: NSView) {
        original = view
        super.init(frame: view.frame)
        autoresizingMask = view.autoresizingMask
    }

    required init?(coder: NSCoder) { nil }

    override var fittingSize: NSSize { original?.fittingSize ?? frame.size }
    override var intrinsicContentSize: NSSize { original?.intrinsicContentSize ?? frame.size }
}
