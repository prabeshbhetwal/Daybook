import SwiftUI
import AppKit

/// What a button does. The words are the copy's; the doing is the caller's.
enum BreakHUDAction: Equatable {
    case start, later, skip, resume, extend, done
}

struct BreakHUDButton {
    let title: String
    let isPrimary: Bool
    let action: () -> Void
}

struct BreakHUDContent {
    let title: String
    let detail: String
    let symbolName: String
    let buttons: [BreakHUDButton]
    let duration: TimeInterval
    /// Runs when the HUD goes away with no button pressed.
    let onTimeout: (() -> Void)?
}

/// The words on the break HUD, apart from the panel so they are checked
/// without a screen. A button's position here is its position in the row; the
/// coordinator pairs each with what it does.
enum BreakHUDCopy {
    typealias Choice = (title: String, action: BreakHUDAction)

    static func reminder(_ prompt: BreakPrompt) -> (title: String, detail: String, buttons: [Choice]) {
        var buttons: [Choice] = [("Start break", .start)]
        switch prompt.tier {
        case .micro: buttons = []
        case .cognitive:
            if prompt.canLater { buttons.append(("Later", .later)) }
            buttons.append(("Skip", .skip))
        case .ultradian:
            // The long-stretch prompt is put off for 15 minutes, never skipped.
            if prompt.canLater { buttons.append(("Remind me in 15 min", .later)) }
        }
        return (prompt.title, prompt.body, buttons)
    }

    /// `threadName` is the session the break paused, or nil when none was.
    static func breakOver(threadName: String?) -> (title: String, detail: String, buttons: [Choice]) {
        ("Break's over", threadName.map { "Back to \($0)?" } ?? "",
         [threadName == nil ? ("Done", .done) : ("Resume", .resume), ("+5 min", .extend)])
    }
}

@MainActor
private final class BreakHUDModel: ObservableObject {
    @Published var content: BreakHUDContent?
}

private struct BreakHUDView: View {
    @ObservedObject var model: BreakHUDModel
    let onButton: (BreakHUDButton) -> Void

    var body: some View {
        if let content = model.content {
            HStack(alignment: .top, spacing: Tokens.Space.m) {
                Image(systemName: content.symbolName)
                    .font(Tokens.Typography.heading)
                    .foregroundStyle(StoryStyle.successInk)
                    .frame(width: Tokens.Space.xl)
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    Text(content.title)
                        .font(Tokens.Typography.label)
                        .lineLimit(2)
                    if !content.detail.isEmpty {
                        Text(content.detail)
                            .font(Tokens.Typography.body)
                            .foregroundStyle(StoryStyle.supportingInk)
                            .lineLimit(6)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: Tokens.Space.s) {
                        ForEach(Array(content.buttons.enumerated()), id: \.offset) { _, button in
                            Button(button.title) { onButton(button) }
                                .buttonStyle(StoryActionStyle(tint: button.isPrimary ? StoryStyle.action : nil))
                        }
                    }
                    .padding(.top, Tokens.Space.xs)
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
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(content.title). \(content.detail)")
            .zoomRoot()
        }
    }
}

/// A break reminder, or the moment a break is over, with the buttons that
/// answer it. Never takes focus, like the reward HUD it is built beside: the
/// panel cannot become key, so a click is a first-mouse click.
@MainActor
final class BreakHUD {
    private let panel: NonActivatingHUDPanel
    private let hostingView: FirstMouseHostingView<BreakHUDView>
    private let model = BreakHUDModel()
    private var dismissWorkItem: DispatchWorkItem?
    /// Bumped on every show and dismiss, so a fade-out scheduled for an earlier
    /// content cannot hide the one that replaced it.
    private var generation = 0
    /// What to run if the content on screen goes away unanswered.
    private var pendingTimeout: (() -> Void)?
    /// Cleared by `show`, set by the first press: the panel is still under the
    /// pointer while it fades, and a second click must not answer twice.
    private var answered = false
    private var zoomFollower: ZoomFollower?

    init() {
        let panel = NonActivatingHUDPanel(
            contentRect: NSRect(x: 0, y: 0, width: Int(Tokens.popoverWidth), height: Int(80.zoomed)),
            styleMask: [.nonactivatingPanel, .hudWindow, .borderless],
            backing: .buffered,
            defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.alphaValue = 0
        let hostingView = FirstMouseHostingView(rootView: BreakHUDView(model: model, onButton: { _ in }))
        panel.contentView = hostingView
        self.panel = panel
        self.hostingView = hostingView
        hostingView.rootView = BreakHUDView(model: model, onButton: { [weak self] in self?.pressed($0) })
        zoomFollower = ZoomFollower { [weak self] in
            if self?.panel.isVisible == true { self?.reposition() }
        }
    }

    func show(_ content: BreakHUDContent) {
        // Content replaced before it was answered went away unanswered.
        let replaced = pendingTimeout
        pendingTimeout = nil
        replaced?()
        generation += 1
        let thisGeneration = generation
        dismissWorkItem?.cancel()
        answered = false
        panel.ignoresMouseEvents = false
        model.content = content
        pendingTimeout = content.onTimeout
        reposition()
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
        Announcement.post(Self.spoken(content))
        // VoiceOver cannot move into a panel that is never key: a listener
        // hears it once and needs time to act elsewhere.
        let shownFor = NSWorkspace.shared.isVoiceOverEnabled ? content.duration * 3 : content.duration
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, thisGeneration == self.generation else { return }
            let timeout = self.pendingTimeout
            self.pendingTimeout = nil
            self.dismiss()
            timeout?()
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + shownFor, execute: workItem)
    }

    /// What VoiceOver says. The buttons cannot be reached from a panel that is
    /// never key, so a listener is told where a break can be taken or ended:
    /// the menu bar offers those two, not the reminder's Later or Skip.
    static func spoken(_ content: BreakHUDContent) -> String {
        let said = RewardHUD.spoken(title: content.title, detail: content.detail, hasUndo: false)
        guard !content.buttons.isEmpty else { return said }
        return said + " You can also take or end a break from Daybook in the menu bar."
    }

    /// Takes the HUD away without running its timeout: whoever calls it has
    /// already dealt with what it asked.
    func dismiss() {
        panel.ignoresMouseEvents = true
        generation += 1
        pendingTimeout = nil
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        fadeOutAndOrderOut(generation: generation)
    }

    /// The first press answers; any later one, while the panel fades, is ignored.
    func pressed(_ button: BreakHUDButton) {
        guard !answered else { return }
        answered = true
        dismiss()
        button.action()
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
            Task { @MainActor in
                guard let self, generation == self.generation else { return }
                self.panel.orderOut(nil)
            }
        })
    }

    /// Top-right of the screen the pointer is on: that is the one being looked at.
    private func reposition() {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) })
                ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        hostingView.layoutSubtreeIfNeeded()
        let fitting = hostingView.fittingSize
        let width = max(fitting.width, Tokens.popoverWidth)
        let height = fitting.height > 0 ? fitting.height : 80.zoomed
        let origin = NSPoint(x: visible.maxX - width - Tokens.Space.l,
                             y: visible.maxY - height - Tokens.Space.l)
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)),
                       display: false)
    }
}
