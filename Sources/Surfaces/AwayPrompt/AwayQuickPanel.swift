import SwiftUI
import AppKit

private final class QuickPromptModel: ObservableObject {
    @Published var away: TimeInterval = 0
    @Published var range: (start: Date, end: Date)?
    @Published var note: String?
    @Published var error: String?
}

/// Carries the hosted view's measured size back to the panel. A reference
/// object rather than a closure captured at init, because the panel is not
/// fully initialised when the hosting view is built.
private final class SizeRelay {
    var onSize: ((CGSize) -> Void)?
}

private struct QuickSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

private struct QuickPromptView: View {
    @ObservedObject var model: QuickPromptModel
    let relay: SizeRelay
    let onAnswer: (UserDecision) -> Bool
    let onReason: (String) -> Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Triangle()
                .fill(Tokens.Colour.surface)
                .frame(width: 18.zoomed, height: 9.zoomed)
            AwayAnswerGrid(away: model.away, range: model.range, compact: true,
                           note: model.note, error: model.error, onRetry: onRetry,
                           onAnswer: onAnswer, onReason: onReason)
                .padding(Tokens.Space.m)
                .frame(width: 300.zoomed, alignment: .leading)
                .background(Tokens.Colour.surface,
                            in: RoundedRectangle(cornerRadius: Tokens.Radius.panel,
                                                 style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.panel, style: .continuous)
                    .strokeBorder(Tokens.Colour.attention.opacity(0.42), lineWidth: 1))
        }
        .fixedSize()
        .controlSize(Tokens.Zoom.rootControlSize)
        // SwiftUI reports its own laid-out size; the panel follows it. AppKit's
        // `fittingSize` and even the hosting view's intrinsic size lagged a
        // pass behind and clipped the last row of buttons.
        .background(GeometryReader { proxy in
            Color.clear.preference(key: QuickSizeKey.self, value: proxy.size)
        })
        .onPreferenceChange(QuickSizeKey.self) { relay.onSize?($0) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Away decision")
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Non-activating, but able to become key: clicking a button answers without
/// bringing the app forward, and clicking into the reason field lets the user
/// type — a nonactivating panel takes key status without activating its app,
/// the way Spotlight does.
private final class QuickAskPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    /// Told when the panel takes or gives up the keyboard, so the fade can
    /// wait for someone who is answering.
    var onKeyChange: (() -> Void)?

    override func becomeKey() {
        super.becomeKey()
        onKeyChange?()
    }

    override func resignKey() {
        super.resignKey()
        onKeyChange?()
    }
}

/// The light way to ask: a small card with an arrow, under the menu-bar item,
/// that never brings the app forward — one click answers. Fades after twenty
/// seconds unless someone is answering it; the popover card stays.
@MainActor
final class AwayQuickPanel {
    private let panel: QuickAskPanel
    private let model = QuickPromptModel()
    private let relay = SizeRelay()
    private var fade: DispatchWorkItem?
    private var generation = 0
    private var lastSize: CGSize?
    private var isShowing = false
    /// Hears of a zoom change for as long as the panel lives.
    private var zoomFollower: ZoomFollower?

    init(onAnswer: @escaping (UserDecision) -> Bool, onReason: @escaping (String) -> Bool,
         onRetry: @escaping () -> Void = {}) {
        let panel = QuickAskPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 220), // zoom: fixed, a first size
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.alphaValue = 0
        self.panel = panel
        panel.contentView = FirstMouseHostingView(
            rootView: QuickPromptView(model: model, relay: relay,
                                      onAnswer: onAnswer, onReason: onReason, onRetry: onRetry))
        relay.onSize = { [weak self] size in self?.layout(to: size) }
        panel.onKeyChange = { [weak self] in self?.scheduleFade() }
        zoomFollower = ZoomFollower { [weak self] in self?.zoomChanged() }
    }

    /// AppKit resizes the window with its content but keeps its left edge, so
    /// at a new zoom the card would hang off the screen it is anchored to.
    /// Laid out afresh, it is measured and placed the way `layout` does. The
    /// layout pass comes first: measured before it, the size is the old one.
    private func zoomChanged() {
        guard let content = panel.contentView else { return }
        content.layoutSubtreeIfNeeded()
        layout(to: content.fittingSize)
    }

    /// The Gallery/PNG harness hosts the exact production SwiftUI root without
    /// constructing or ordering its non-activating panel and without starting
    /// the twenty-second fade timer.
    static func snapshotView(
        away: TimeInterval,
        range: (start: Date, end: Date)?,
        note: String? = nil,
        error: String? = nil
    ) -> some View {
        let model = QuickPromptModel()
        model.away = away
        model.range = range
        model.note = note
        model.error = error
        return QuickPromptView(model: model, relay: SizeRelay(),
                               onAnswer: { _ in true }, onReason: { _ in true }, onRetry: {})
    }

    /// `takesFocus` is for the global hotkey: the person asked for the
    /// question, so the panel takes the keyboard (still without bringing the
    /// app forward) and can be answered without a pointer. Shown on its own,
    /// it stays out of the way of whatever has the keyboard.
    func show(away: TimeInterval, range: (start: Date, end: Date)?, note: String?,
              takesFocus: Bool = false) {
        generation += 1
        fade?.cancel()
        isShowing = true
        model.away = away
        model.range = range
        model.note = note
        model.error = nil
        // Place it at the last known size now so it appears where it belongs;
        // the preference corrects the size the moment SwiftUI has laid out.
        layout(to: lastSize ?? CGSize(width: 300.zoomed, height: 220.zoomed))
        if takesFocus {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = 1
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                panel.animator().alphaValue = 1
            }
        }
        // A card that appears under the menu bar is otherwise silent.
        Announcement.post("Away \(Tokens.spent(away)). How should that time count?")
        scheduleFade()
    }

    func showError(_ error: String) {
        generation += 1
        fade?.cancel()
        fade = nil
        isShowing = true
        model.error = error
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    /// Fades the card after twenty seconds, unless it has the keyboard: a
    /// slow typist used to lose the card mid-word. Once they click away the
    /// count starts again, half-typed reason or not, so a card with no close
    /// control never stays over every Space for good; the reason itself
    /// survives the fade until the away changes. After a failed save it
    /// never fades.
    private func scheduleFade() {
        fade?.cancel()
        fade = nil
        guard isShowing, model.error == nil, !panel.isKeyWindow else { return }
        let current = generation
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.generation == current else { return }
            self.dismiss()
        }
        fade = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: item)
    }

    func dismiss() {
        generation += 1
        fade?.cancel()
        fade = nil
        isShowing = false
        guard panel.alphaValue > 0 else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = 0
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
        })
    }

    /// Top edge anchored under the status item; the frame grows downward.
    private func layout(to size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        lastSize = size
        let origin = AwayQuickPanel.anchor(for: size)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    /// Centred under the status item when its window can be found; otherwise
    /// tucked into the top-right of the main screen. `MenuBarExtra` exposes no
    /// frame, so the status-bar window is the best evidence there is. The
    /// margins to the screen's edge and the status item are the system's, not
    /// the interface's, so they stay fixed.
    private static func anchor(for size: CGSize) -> NSPoint {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_440, height: 900) // zoom: fixed, a screen's size
        let menuBarTop = screen?.frame.maxY ?? visible.maxY
        if let item = NSApp.windows.first(where: {
            $0.className == "NSStatusBarWindow" && $0.frame.maxY >= menuBarTop - 1
        }) {
            let x = item.frame.midX - size.width / 2
            let clampedX = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
            return NSPoint(x: clampedX, y: item.frame.minY - size.height - 2)
        }
        return NSPoint(x: visible.maxX - size.width - 16, y: visible.maxY - size.height - 8)
    }
}
