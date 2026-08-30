import SwiftUI
import AppKit

private final class QuickPromptModel: ObservableObject {
    @Published var away: TimeInterval = 0
    @Published var range: (start: Date, end: Date)?
    @Published var note: String?
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
    let onAnswer: (UserDecision) -> Void
    let onReason: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Triangle()
                .fill(Tokens.Colour.surface)
                .frame(width: 18, height: 9)
            AwayAnswerGrid(away: model.away, range: model.range, compact: true,
                           note: model.note, onAnswer: onAnswer, onReason: onReason)
                .padding(Tokens.Space.m)
                .frame(width: 300, alignment: .leading)
                .background(Tokens.Colour.surface,
                            in: RoundedRectangle(cornerRadius: Tokens.Radius.panel,
                                                 style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.panel, style: .continuous)
                    .strokeBorder(Tokens.Colour.attention.opacity(0.42), lineWidth: 1))
        }
        .fixedSize()
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
}

/// The light way to ask: a small card with an arrow, under the menu-bar item,
/// that never brings the app forward — one click answers. Fades after twenty
/// seconds; the popover card stays.
@MainActor
final class AwayQuickPanel {
    private let panel: QuickAskPanel
    private let model = QuickPromptModel()
    private let relay = SizeRelay()
    private var fade: DispatchWorkItem?
    private var generation = 0
    private var lastSize: CGSize?

    init(onAnswer: @escaping (UserDecision) -> Void, onReason: @escaping (String) -> Void) {
        let panel = QuickAskPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 220),
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
                                      onAnswer: onAnswer, onReason: onReason))
        relay.onSize = { [weak self] size in self?.layout(to: size) }
    }

    func show(away: TimeInterval, range: (start: Date, end: Date)?, note: String?) {
        generation += 1
        let current = generation
        fade?.cancel()
        model.away = away
        model.range = range
        model.note = note
        // Place it at the last known size now so it appears where it belongs;
        // the preference corrects the size the moment SwiftUI has laid out.
        layout(to: lastSize ?? CGSize(width: 300, height: 220))
        panel.orderFrontRegardless()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = 1
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                panel.animator().alphaValue = 1
            }
        }
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
    /// frame, so the status-bar window is the best evidence there is.
    private static func anchor(for size: CGSize) -> NSPoint {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)
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
