import SwiftUI
import AppKit

private final class FullPromptModel: ObservableObject {
    @Published var away: TimeInterval = 0
    @Published var range: (start: Date, end: Date)?
    @Published var note: String?
    @Published var error: String?
}

private struct FullPromptView: View {
    @ObservedObject var model: FullPromptModel
    let onAnswer: (UserDecision) -> Bool
    let onReason: (String) -> Bool
    let onRetry: () -> Void
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
                               note: model.note, error: model.error, onRetry: onRetry,
                               onAnswer: onAnswer, onReason: onReason)
                HStack {
                    Spacer()
                    // The 28pt frame sits inside the label: outside the button
                    // it made room but left only the word clickable.
                    Button(action: onLater) {
                        Text("Later")
                            .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(StoryPressStyle())
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityHint("Keeps the question available for later")
                }
            }
            .padding(Tokens.Space.xl)
            .frame(width: 520.zoomed)
            // The card is its content's size, never the window's. A prompt on
            // a display a window manager has made tall must still be a card.
            .fixedSize(horizontal: false, vertical: true)
            .background(Tokens.Colour.surface,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.panel + 4.zoomed,
                                             style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.panel + 4.zoomed, style: .continuous)
                .strokeBorder(Tokens.Colour.attention.opacity(0.42), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 30.zoomed, y: 12.zoomed)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Away decision")
        }
        .controlSize(Tokens.Zoom.rootControlSize)
    }
}

/// A borderless window that can take the keyboard, so Return and Esc work.
private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// The frame this window insists on while it is shown. A tiling or window
    /// manager driving the accessibility API can otherwise resize a borderless
    /// panel into a column; every AppKit resize path lands in `setFrame`, so
    /// refusing it there covers the manager, the API and our own strays alike.
    private var lockedFrame: NSRect?

    func lock(to frame: NSRect) {
        lockedFrame = nil
        super.setFrame(frame, display: false)
        lockedFrame = frame
    }

    func unlock() { lockedFrame = nil }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(lockedFrame ?? frameRect, display: flag)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool, animate: Bool) {
        super.setFrame(lockedFrame ?? frameRect, display: flag, animate: animate)
    }

    override func setContentSize(_ size: NSSize) {
        if let lockedFrame {
            super.setFrame(lockedFrame, display: false)
        } else {
            super.setContentSize(size)
        }
    }

    override func setFrameOrigin(_ point: NSPoint) {
        super.setFrameOrigin(lockedFrame?.origin ?? point)
    }
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
    private let onAnswer: (UserDecision) -> Bool
    private let onReason: (String) -> Bool
    private let onRetry: () -> Void
    private let onLater: () -> Void

    init(onAnswer: @escaping (UserDecision) -> Bool,
         onReason: @escaping (String) -> Bool,
         onRetry: @escaping () -> Void = {},
         onLater: @escaping () -> Void) {
        self.onAnswer = onAnswer
        self.onReason = onReason
        self.onRetry = onRetry
        self.onLater = onLater
    }

    /// A deterministic safe host for the exact full-screen production root.
    /// No AppKit window is created, no app is activated and no dismissal
    /// callback has side effects, while the backdrop and Later/Escape route
    /// remain part of the rendered hierarchy.
    static func snapshotView(
        away: TimeInterval,
        range: (start: Date, end: Date)?,
        note: String? = nil,
        error: String? = nil
    ) -> some View {
        let model = FullPromptModel()
        model.away = away
        model.range = range
        model.note = note
        model.error = error
        return FullPromptView(model: model,
                              onAnswer: { _ in true },
                              onReason: { _ in true },
                              onRetry: {},
                              onLater: {})
            .frame(width: 760, height: 620) // zoom: fixed, stands in for the screen
    }

    private var screenObserver: NSObjectProtocol?

    func show(away: TimeInterval, range: (start: Date, end: Date)?, note: String?) {
        model.away = away
        model.range = range
        model.note = note
        model.error = nil
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let window = self.window ?? makeWindow()
        window.lock(to: screen.frame)
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : front
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            window.alphaValue = 1
        } else {
            window.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                window.animator().alphaValue = 1
            }
        }
    }

    func showError(_ error: String) {
        model.error = error
    }

    func dismiss() {
        guard let window, window.isVisible else { return }
        let previous = previousApp
        previousApp = nil
        window.unlock()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            window.alphaValue = 0
            window.orderOut(nil)
            release(window)
            previous?.activate(options: [])
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // Shown again during the fade: that presentation owns it now.
            MainActor.assumeIsolated {
                guard window.alphaValue == 0 else { return }
                window.orderOut(nil)
                self?.release(window)
                previous?.activate(options: [])
            }
        })
    }

    /// A screen-sized window with a live blur and its SwiftUI tree is too much
    /// to keep for a prompt that may not come back for days. `show` builds a
    /// fresh one when it does.
    private func release(_ window: KeyableWindow) {
        guard self.window === window else { return }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        window.contentView = nil
        self.window = nil
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
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self, weak window] _ in
                guard let window, window.isVisible,
                      let screen = window.screen ?? NSScreen.main else { return }
                window.lock(to: screen.frame)
                _ = self
            }

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]
        let hosting = NSHostingView(rootView: FullPromptView(model: model,
                                                             onAnswer: onAnswer,
                                                             onReason: onReason,
                                                             onRetry: onRetry,
                                                             onLater: onLater))
        hosting.autoresizingMask = [.width, .height]
        blur.addSubview(hosting)
        window.contentView = blur
        hosting.frame = blur.bounds
        self.window = window
        return window
    }
}
