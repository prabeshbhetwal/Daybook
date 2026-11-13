import AppKit
import SwiftUI

/// The room the chrome keeps for the native window buttons at its leading
/// edge. In full screen the system hides the buttons, so the room goes with
/// them instead of leaving an empty gap before the first control.
struct TrafficLightGap: View {
    @State private var fullScreen = false

    var body: some View {
        Color.clear
            .frame(width: MainWindowChrome.clearance(fullScreen: fullScreen), height: 1)
            .background(FullScreenReader { fullScreen = $0 })
            .accessibilityHidden(true)
    }
}

/// Tells its closure whether the window holding it is full screen: when it
/// finds the window, and as the window enters or leaves full screen.
struct FullScreenReader: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> FullScreenAnchor {
        let anchor = FullScreenAnchor()
        anchor.onChange = onChange
        return anchor
    }

    func updateNSView(_ nsView: FullScreenAnchor, context: Context) {
        nsView.onChange = onChange
    }
}

final class FullScreenAnchor: NSView {
    var onChange: ((Bool) -> Void)?
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
        // Each edge waits until the buttons are certainly gone, or back, so
        // the controls never sit under them during the animation.
        let center = NotificationCenter.default
        observers = [
            (NSWindow.didEnterFullScreenNotification, true),
            (NSWindow.willExitFullScreenNotification, false),
        ].map { name, fullScreen in
            center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.onChange?(fullScreen)
            }
        }
        // Outside the view update that is adding this anchor: a change to the
        // view's own state in the middle of one is not allowed.
        DispatchQueue.main.async { [weak self, weak window] in
            self?.onChange?(window?.styleMask.contains(.fullScreen) ?? false)
        }
    }
}
