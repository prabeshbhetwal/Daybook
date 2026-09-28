import SwiftUI
import AppKit

/// Backing store for the hosted SwiftUI content. `@State`/`@Observable` are
/// unavailable on this toolchain — Command Line Tools ships no SwiftUIMacros
/// plugin, so those two property wrappers don't compile here — so the panel's
/// content lives in a small `ObservableObject` instead, same as `SessionStore`
/// elsewhere in this module.
private final class RewardHUDContentModel: ObservableObject {
    @Published var title: String = ""
    @Published var detail: String = ""
    @Published var symbolName: String = "checkmark.circle.fill"
    @Published var undo: (() -> Void)?
}

private struct RewardHUDView: View {
    @ObservedObject var model: RewardHUDContentModel
    let onUndoTapped: () -> Void
    let onBackgroundTapped: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Space.m) {
            Image(systemName: model.symbolName)
                .font(Tokens.Typography.sectionTitle)
                // The ink, not the swatch: system green on the light panel
                // was about 2:1, under the 3:1 a meaningful symbol needs.
                .foregroundStyle(StoryStyle.successInk)
                .frame(width: Tokens.Space.xl)
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text(model.title)
                    .font(Tokens.Typography.metadata.weight(.semibold))
                    .lineLimit(2)
                Text(model.detail)
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    // A break prompt carries its reason, which is two sentences.
                    // At two lines the reason was the half that got truncated,
                    // leaving an instruction with no argument behind it.
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
                if model.undo != nil {
                    Button("Undo", action: onUndoTapped)
                        .buttonStyle(StoryLinkStyle())
                        .font(Tokens.Typography.metadata.weight(.medium))
                        .foregroundStyle(Tokens.Colour.focus)
                        .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Tokens.Space.m)
        .frame(width: Tokens.popoverWidth, alignment: .leading)
        .background(Tokens.Colour.surface,
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.panel))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.panel)
                .strokeBorder(Tokens.Colour.progress.opacity(0.38), lineWidth: 1)
        )
        // A tap anywhere dismisses; the Undo button is the deepest hit-tested
        // view at its location, so SwiftUI resolves its own tap first and this
        // background gesture never steals it.
        .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.panel))
        .onTapGesture(perform: onBackgroundTapped)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(model.title). \(model.detail)")
    }
}

/// A panel that can be seen but never touched by the window server's notion of
/// "focus". `.nonactivatingPanel` in the style mask keeps `orderFrontRegardless()`
/// from activating the app, but that alone is only a hint — AppKit will still
/// hand a nonactivating panel key status if nothing else claims it first (e.g.
/// right after the last regular window closes). Hardwiring both methods to
/// `false` is the actual OS-level guarantee: this window can never become key
/// or main, full stop, which is what "nothing ever steals focus" requires.
final class NonActivatingHUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The panel is never key, so every click in it is a "first mouse" click, and
/// `NSView` refuses those by default. Without this the Undo button silently
/// swallows its first click — and Undo is the only way to reject a session the
/// app invented.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Earned-moment praise, shown without ever taking focus. One panel is created
/// once and reused for every reward — `NSAlert` was rejected for this project
/// specifically because a modal alert grabs key status; this is its replacement.
@MainActor
final class RewardHUD {
    private let panel: NonActivatingHUDPanel
    private let hostingView: FirstMouseHostingView<RewardHUDView>
    private let model = RewardHUDContentModel()
    private var dismissWorkItem: DispatchWorkItem?
    /// Bumped on every `show`/`dismiss`. A fade-out's completion handler is
    /// scheduled up to 0.3s in the future; checking this before it acts on the
    /// panel is what stops a stale fade-out from hiding a panel that a later
    /// `show` already replaced the content of and re-shown.
    private var generation = 0

    init() {
        let panel = NonActivatingHUDPanel(
            contentRect: NSRect(x: 0, y: 0, width: Int(Tokens.popoverWidth), height: 80),
            styleMask: [.nonactivatingPanel, .hudWindow, .borderless],
            backing: .buffered,
            defer: false)
        panel.level = .floating
        // Without `.fullScreenAuxiliary` the panel cannot appear over another
        // app's full-screen space — exactly where deep work happens.
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        // Transparent chrome so `.regularMaterial` in the SwiftUI content is
        // what actually paints the panel, not an opaque HUD background behind it.
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.alphaValue = 0

        let hostingView = FirstMouseHostingView(rootView: RewardHUDView(model: model,
                                                                  onUndoTapped: {},
                                                                  onBackgroundTapped: {}))
        panel.contentView = hostingView

        self.panel = panel
        self.hostingView = hostingView

        // Deferred until after `self` is fully assigned above — the closures
        // below capture it.
        hostingView.rootView = RewardHUDView(
            model: model,
            onUndoTapped: { [weak self] in self?.handleUndo() },
            onBackgroundTapped: { [weak self] in self?.dismiss() })
    }

    /// The PNG/gallery harness renders the exact hosted content without
    /// ordering the production non-activating panel or starting its timer.
    static func snapshotView(for reward: Reward) -> some View {
        let model = RewardHUDContentModel()
        model.title = reward.title
        model.detail = reward.detail
        model.symbolName = reward.symbolName
        return RewardHUDView(model: model,
                             onUndoTapped: {},
                             onBackgroundTapped: {})
    }

    /// - Parameter duration: how long it stays up. A break prompt needs longer
    ///   than a congratulation: it is asking for something, and five seconds is
    ///   not enough to read a reason and act on it.
    func show(title: String, detail: String, symbolName: String,
              duration: TimeInterval = FocusConstants.hudDisplaySeconds,
              undo: (() -> Void)?) {
        generation += 1
        let thisGeneration = generation

        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        model.title = title
        model.detail = detail
        model.symbolName = symbolName
        model.undo = undo

        reposition()

        // Every call restarts the fade from invisible, so a reward that
        // replaces one still on screen gets its own clean 0.2s entrance
        // rather than an ambiguous cross-fade from wherever the old one was.
        panel.orderFrontRegardless()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = 1
        } else {
            panel.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().alphaValue = 1
            }
        }
        Announcement.post(Self.spoken(title: title, detail: detail, hasUndo: undo != nil))

        // The panel can never be focused, so VoiceOver cannot move into it:
        // a listener hears it once and needs time to act on it elsewhere.
        let shownFor = NSWorkspace.shared.isVoiceOverEnabled ? duration * 3 : duration
        let workItem = DispatchWorkItem { [weak self] in
            self?.fadeOutAndOrderOut(generation: thisGeneration)
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + shownFor, execute: workItem)
    }

    /// What VoiceOver says when the panel appears. The Undo here can only be
    /// clicked, so a listener is told where the same Undo is: the automatic
    /// session's controls, which list it for as long as the session runs.
    static func spoken(title: String, detail: String, hasUndo: Bool) -> String {
        var sentences = [title, detail].filter { !$0.isEmpty }
        if hasUndo {
            sentences.append("To undo it, open session controls with Command-7 "
                             + "and choose Undo automatic session")
        }
        return sentences
            .map { $0.last.map { ".?!".contains($0) } == true ? $0 : $0 + "." }
            .joined(separator: " ")
    }

    func dismiss() {
        generation += 1
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        fadeOutAndOrderOut(generation: generation)
    }

    private func handleUndo() {
        model.undo?()
        dismiss()
    }

    private func fadeOutAndOrderOut(generation: Int) {
        guard panel.isVisible, generation == self.generation else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = 0
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // AppKit's completion block is `@Sendable`, so touching main-actor
            // state has to hop back through a `Task` rather than reading it
            // inline — the block itself still only ever runs on the main
            // thread, this just satisfies the compiler's isolation check.
            Task { @MainActor in
                guard let self, generation == self.generation else { return }
                self.panel.orderOut(nil)
            }
        })
    }

    /// Top-right of the screen holding the menu bar, inset below it.
    private func reposition() {
        // `NSScreen.screens.first` is always the display carrying the menu
        // bar, independent of which window (if any) is key — unlike `.main`,
        // which tracks key-window location and would follow the wrong screen
        // on a multi-monitor setup.
        guard let screen = NSScreen.screens.first ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        // Measured after a layout pass: `fittingSize` read straight after the
        // model changed still describes the previous message, clipping a
        // taller one on its first showing.
        hostingView.layoutSubtreeIfNeeded()
        let fitting = hostingView.fittingSize
        let width = max(fitting.width, Tokens.popoverWidth)
        let height = fitting.height > 0 ? fitting.height : 80
        let origin = NSPoint(x: visible.maxX - width - Tokens.Space.l,
                              y: visible.maxY - height - Tokens.Space.l)
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)),
                        display: false)
    }
}
