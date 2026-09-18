import SwiftUI
import AppKit

/// Runs the welcome.
///
/// It owns where the reader is and nothing else. The window state the cards
/// wait on is *observed*, never driven, so every payoff a card points at is
/// the application's real behaviour rather than a rehearsal of it.
final class FirstRunCoach: ObservableObject {
    @Published private(set) var progress: FirstRunProgress?
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void = {}) {
        self.onFinish = onFinish
    }

    var isActive: Bool { progress != nil }

    func begin() {
        guard progress == nil else { return }
        progress = FirstRunProgress()
    }

    func observe(_ signals: FirstRunSignals) {
        guard var next = progress else { return }
        next.observe(signals)
        apply(next)
    }

    func advance() {
        guard var next = progress else { return }
        next.advance()
        apply(next)
    }

    func skip() {
        guard var next = progress else { return }
        next.skip()
        apply(next)
    }

    /// However the welcome ends — read through, stepped past or skipped — it is
    /// written down as answered. Skip is an answer, not a postponement.
    private func apply(_ next: FirstRunProgress) {
        guard next != progress else { return }
        if next.isFinished {
            progress = nil
            onFinish()
        } else {
            progress = next
        }
    }
}

/// The welcome, laid over the live story.
///
/// Two things are load-bearing here. The card sits at the low leading corner,
/// which is the one place clear of everything the cards point at — the chrome
/// above, the rail to the right, and the sentence at the top of the page that
/// two of the steps ask the reader to watch. And nothing is modal: the window
/// stays fully usable, because the steps are instructions to use it.
struct WelcomeCoachOverlay: View {
    @ObservedObject var coach: FirstRunCoach
    let anchors: [CoachAnchor: Anchor<CGRect>]
    let proxy: GeometryProxy
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let progress = coach.progress {
            ZStack(alignment: .bottomLeading) {
                if let anchor = FirstRunScript.card(for: progress.beat).anchor,
                   let bounds = anchors[anchor] {
                    CoachRing(rect: proxy[bounds])
                        .transition(Tokens.Motion.transition(.opacity, reduceMotion: reduceMotion))
                        .id(anchor.rawValue)
                }
                WelcomeCoachCard(progress: progress,
                                 onForward: { coach.advance() },
                                 onSkip: { coach.skip() })
                    .padding(Tokens.Space.xl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .animation(Tokens.Motion.animation(Tokens.Motion.reveal, reduceMotion: reduceMotion),
                       value: progress)
        }
    }
}

/// One card of the welcome.
struct WelcomeCoachCard: View {
    let progress: FirstRunProgress
    let onForward: () -> Void
    let onSkip: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let width: CGFloat = 380

    private var card: FirstRunScript.Card { FirstRunScript.card(for: progress.beat) }
    private var showsResult: Bool { progress.phase == .done && card.result != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            header
            content
                // A new beat, or a step being completed, is a new reading and
                // therefore a new view — otherwise the words change under the
                // reader with no sign that anything happened.
                .id("\(progress.beat.rawValue)-\(progress.phase.rawValue)")
                .transition(Tokens.Motion.transition(
                    .opacity.combined(with: .offset(y: 6)), reduceMotion: reduceMotion))
            controls
        }
        .padding(Tokens.Space.l)
        .frame(width: Self.width, alignment: .leading)
        .background(StoryStyle.card,
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Tokens.Radius.panel, style: .continuous)
                .strokeBorder(StoryStyle.line, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.20), radius: 24, x: 0, y: 12)
        .storyRenderEvidence(.firstRun(progress.beat))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome, \(FirstRunScript.eyebrow(for: progress.beat))")
        .onAppear { announce() }
        .onChange(of: progress) { _ in announce() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
            Text(FirstRunScript.eyebrow(for: progress.beat).uppercased())
                .font(Tokens.Typography.microLabel.weight(.bold))
                .kerning(0.8)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if FirstRunScript.stepNumber(for: progress.beat) != nil { dots }
        }
    }

    /// One mark per step that asks something. A tick means the reader actually
    /// did it; a step they stepped past keeps its hollow mark, because claiming
    /// they had done it would be the first untrue thing the app ever told them.
    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(FirstRunScript.actionBeats, id: \.self) { beat in
                mark(for: beat)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private func mark(for beat: FirstRunBeat) -> some View {
        let task = FirstRunScript.card(for: beat).task
        let performed = task.map { progress.performed.contains($0) } ?? false
        if performed {
            Image(systemName: "checkmark")
                .font(Tokens.Typography.micro.weight(.heavy))
                .foregroundStyle(StoryStyle.focus)
                .frame(width: 8, height: 8)
        } else if beat == progress.beat {
            Circle().fill(StoryStyle.focus).frame(width: 8, height: 8)
        } else {
            Circle().strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
                .frame(width: 8, height: 8)
        }
    }

    // MARK: - Body

    @ViewBuilder private var content: some View {
        if showsResult, let result = card.result {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .font(Tokens.Typography.rowTitle)
                    .foregroundStyle(StoryStyle.successInk)
                Text(result)
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                Text(card.sentence)
                    .font(Tokens.Typography.sectionTitle)
                    .fixedSize(horizontal: false, vertical: true)
                Text(card.body)
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = card.note { self.note(note) }
            }
        }
    }

    /// The closing card's second paragraph, with the menu bar's own glyph
    /// beside it — the welcome cannot draw a ring around the system menu bar,
    /// so it shows the reader the shape to look for instead.
    private func note(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Tokens.Space.s) {
            if let glyph = MenuBarGlyph.image(progress: 0.45, paused: false,
                                              attention: false, isMet: false) {
                Image(nsImage: glyph)
                    .renderingMode(.template)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Tokens.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StoryStyle.well,
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
    }

    // MARK: - Controls

    /// No keyboard shortcuts. Escape and Return belong to the activity field
    /// and the Start button that two of these steps send the reader to; binding
    /// them here would let a cancelled edit dismiss the welcome mid-sentence.
    private var controls: some View {
        HStack(spacing: Tokens.Space.s) {
            Button("Skip", action: onSkip)
                .buttonStyle(StoryLinkStyle())
                .accessibilityHint("Closes the welcome for good")
            Spacer(minLength: Tokens.Space.s)
            Button(forwardTitle, action: onForward)
                .buttonStyle(StoryActionStyle(tint: StoryStyle.focus))
        }
        .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
    }

    private var forwardTitle: String {
        if progress.isWaiting, let waiting = card.waiting { return waiting }
        return card.forward
    }

    private func announce() {
        let spoken = showsResult ? (card.result ?? card.sentence)
            : ([card.sentence, card.body, card.note].compactMap { $0 }.joined(separator: " "))
        NSAccessibility.post(element: NSApp as Any,
                             notification: .announcementRequested,
                             userInfo: [
                                .announcement: spoken,
                                .priority: NSAccessibilityPriorityLevel.high.rawValue
                             ])
    }
}
