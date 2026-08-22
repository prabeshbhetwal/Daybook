import SwiftUI
import AppKit

private final class FullPromptModel: ObservableObject {
    @Published var away: TimeInterval = 0
    @Published var range: (start: Date, end: Date)?
    @Published var note: String?
}

private struct FullPromptView: View {
    @ObservedObject var model: FullPromptModel
    let onAnswer: (UserDecision) -> Void
    let onReason: (String) -> Void
    let onLater: () -> Void

    var body: some View {
        ZStack {
            // Click-catcher: anywhere outside the card is "later".
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onLater)
            VStack(alignment: .leading, spacing: Tokens.Space.l) {
                AwayAnswerGrid(away: model.away, range: model.range, showsCaptions: true,
                               note: model.note, onAnswer: onAnswer, onReason: onReason)
                HStack {
                    Spacer()
                    Button("Later", action: onLater)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(Tokens.Space.xl)
            .frame(width: 520)
            .background(Tokens.Surface.card,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.card + 4,
                                             style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card + 4, style: .continuous)
                .strokeBorder(Tokens.Surface.hairline))
            .shadow(color: .black.opacity(0.25), radius: 30, y: 12)
        }
    }
}

/// A borderless window that can take the keyboard, so Return and Esc work.
private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The heavy way to ask: the display under the pointer goes soft behind a
/// centred card. For absences long enough that the thread is lost anyway, so
/// a centred question costs nothing and a missed one would.
@MainActor
final class AwayFullPrompt {
    private var window: KeyableWindow?
    /// Whoever was in front before the prompt took the keyboard. Handed back on
    /// dismiss: a menu-bar app has no window of its own to leave the user in.
    private var previousApp: NSRunningApplication?
    private let model = FullPromptModel()
    private let onAnswer: (UserDecision) -> Void
    private let onReason: (String) -> Void
    private let onLater: () -> Void

    init(onAnswer: @escaping (UserDecision) -> Void,
         onReason: @escaping (String) -> Void,
         onLater: @escaping () -> Void) {
        self.onAnswer = onAnswer
        self.onReason = onReason
        self.onLater = onLater
    }

    func show(away: TimeInterval, range: (start: Date, end: Date)?, note: String?) {
        model.away = away
        model.range = range
        model.note = note
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let window = self.window ?? makeWindow()
        window.setFrame(screen.frame, display: false)
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : front
        NSApp.activate(ignoringOtherApps: true)
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            window.animator().alphaValue = 1
        }
    }

    func dismiss() {
        guard let window, window.isVisible else { return }
        let previous = previousApp
        previousApp = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
            previous?.activate(options: [])
        })
    }

    private func makeWindow() -> KeyableWindow {
        let window = KeyableWindow(contentRect: NSScreen.main?.frame ?? .zero,
                                   styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = false

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]
        let hosting = NSHostingView(rootView: FullPromptView(model: model,
                                                             onAnswer: onAnswer,
                                                             onReason: onReason,
                                                             onLater: onLater))
        hosting.autoresizingMask = [.width, .height]
        blur.addSubview(hosting)
        window.contentView = blur
        hosting.frame = blur.bounds
        self.window = window
        return window
    }
}
