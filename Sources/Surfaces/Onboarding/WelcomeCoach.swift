import SwiftUI
import AppKit

/// Runs the welcome.
///
/// It owns where the reader is and nothing else. The window state the cards
/// wait on is *observed*, never driven, so every payoff a card points at is
/// the application's real behaviour rather than a rehearsal of it. The few
/// things the app does *for* a card — reveal the strip, show History, raise
/// the sample away card — are declared on the card and applied by the
/// application, which reads this position and never the other way round.
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

    func back() {
        guard var next = progress else { return }
        next.back()
        apply(next)
    }

    func jump(to chapter: FirstRunChapter) {
        guard var next = progress else { return }
        next.jump(to: chapter)
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
                if let anchor = progress.current.anchor, let bounds = anchors[anchor] {
                    CoachRing(rect: proxy[bounds], bounds: proxy.frame(in: .local))
                        .transition(Tokens.Motion.transition(.opacity, reduceMotion: reduceMotion))
                        .id(anchor.rawValue)
                }
                WelcomeCoachCard(progress: progress,
                                 onForward: { coach.advance() },
                                 onBack: { coach.back() },
                                 onJump: { coach.jump(to: $0) },
                                 onSkip: { coach.skip() })
                    .padding(Tokens.Space.xl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .animation(Tokens.Motion.animation(Tokens.Motion.reveal, reduceMotion: reduceMotion),
                       value: progress)
        }
    }
}

/// One card of the welcome, and the chapter list it can turn into.
struct WelcomeCoachCard: View {
    let progress: FirstRunProgress
    let onForward: () -> Void
    let onBack: () -> Void
    let onJump: (FirstRunChapter) -> Void
    let onSkip: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var listShown = BoolBox()
    /// Where the keyboard goes when the card changes: onto the way forward,
    /// or onto the chapter list when it opens. Only Full Keyboard Access
    /// focuses buttons at all, so without it this moves nothing.
    @FocusState private var focus: CardFocus?
    /// VoiceOver's cursor, moved onto each new card so the listener is not
    /// left somewhere in the story below while the welcome carries on.
    @AccessibilityFocusState private var readerOnCard: Bool

    private enum CardFocus: Hashable {
        case forward
        case chapter(FirstRunChapter)
    }

    static let width: CGFloat = 420

    private var card: FirstRunScript.Card { progress.current }
    private var showsResult: Bool { progress.phase == .done && card.result != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            header
            chapterBar
            Group {
                if listShown.value {
                    chapterList
                } else {
                    content
                        // A new card, or a step being completed, is a new
                        // reading and therefore a new view — otherwise the
                        // words change under the reader with no sign that
                        // anything happened.
                        .id("\(progress.chapter.rawValue)-\(progress.card)-\(progress.phase.rawValue)")
                        .transition(Tokens.Motion.transition(
                            .opacity.combined(with: .offset(y: 6)), reduceMotion: reduceMotion))
                }
            }
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
        .storyRenderEvidence(.firstRun(progress.chapter))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome, \(FirstRunScript.eyebrow(chapter: progress.chapter, card: progress.card))")
        .accessibilityFocused($readerOnCard)
        .onAppear {
            announce()
            takeFocus()
        }
        .onChange(of: progress) { _ in
            listShown.value = false
            announce()
            takeFocus()
        }
        .onChange(of: listShown.value) { shown in
            focus = shown ? .chapter(progress.chapter) : .forward
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
            // Sentence case like every other title in the app; spaced
            // capitals at this size were the hardest line on the card to read.
            Text(FirstRunScript.eyebrow(chapter: progress.chapter, card: progress.card))
                .font(Tokens.Typography.metadata.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: Tokens.Space.s)
            Button(listShown.value ? "Close" : "Chapters") { listShown.value.toggle() }
                .buttonStyle(StoryLinkStyle())
                .accessibilityHint(listShown.value ? "Back to the card"
                                                   : "Choose a chapter to jump to")
        }
    }

    /// One thin segment per chapter, filled to where the reader is. A tour
    /// this long owes the reader a sense of how far through it they are,
    /// and this says it without a number to read.
    private var chapterBar: some View {
        HStack(spacing: 3) {
            ForEach(FirstRunChapter.allCases) { chapter in
                Capsule()
                    .fill(chapter.number <= progress.chapter.number
                          ? StoryStyle.focus : Color.secondary.opacity(0.18))
                    .frame(height: 3)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Chapter list

    private var chapterList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(FirstRunChapter.allCases) { chapter in
                let isCurrent = chapter == progress.chapter
                let seen = progress.visited.contains(chapter) && !isCurrent
                Button {
                    onJump(chapter)
                    listShown.value = false
                } label: {
                    HStack(spacing: Tokens.Space.s) {
                        Text("\(chapter.number)")
                            .font(Tokens.Typography.microValue.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 18, alignment: .trailing)
                        Text(chapter.title)
                            .font(Tokens.Typography.metadata.weight(isCurrent ? .semibold : .regular))
                            .foregroundStyle(isCurrent ? AnyShapeStyle(StoryStyle.focus)
                                                       : AnyShapeStyle(.primary))
                        Spacer(minLength: 0)
                        if seen {
                            Image(systemName: "checkmark")
                                .font(Tokens.Typography.micro.weight(.heavy))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, Tokens.Space.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(StoryPressStyle(hovers: true, cornerRadius: Tokens.Radius.control))
                .focused($focus, equals: .chapter(chapter))
                .accessibilityLabel("Chapter \(chapter.number), \(chapter.title)"
                                    + (isCurrent ? ", current" : seen ? ", read" : ""))
            }
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
                // The paragraph the whole card exists to say, so it is set
                // for reading: primary ink at control size, not the grey
                // metadata style used for asides.
                Text(card.body)
                    .font(Tokens.Typography.control)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = card.note { self.note(note) }
            }
        }
    }

    /// A card's second paragraph, set off in a well. On the menu bar card it
    /// carries the menu bar's own glyph: the welcome cannot draw a ring on the
    /// system menu bar, so it shows the reader the shape to look for instead.
    private func note(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Tokens.Space.s) {
            if progress.chapter == .menuBar,
               let glyph = MenuBarGlyph.image(progress: 0.45, paused: false,
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

    /// Escape and Return are left alone: they belong to the activity field
    /// and the Start button that two of these steps send the reader to, and
    /// binding them here would let a cancelled edit dismiss the welcome
    /// mid-sentence. ⌘] and ⌘[ are the page-forward and page-back keys Safari
    /// and Finder use, and nothing in the window already claims them, so a
    /// reader without a mouse can still turn the pages.
    private var controls: some View {
        HStack(spacing: Tokens.Space.s) {
            Button("Skip tour", action: onSkip)
                .buttonStyle(StoryLinkStyle())
                .accessibilityHint("Ends the tour for good; Settings can start it again")
            Spacer(minLength: Tokens.Space.s)
            if !progress.isFirstCard {
                Button("Back", action: onBack)
                    .buttonStyle(StoryActionStyle())
                    .keyboardShortcut("[", modifiers: .command)
                    .help("Back (⌘[)")
            }
            Button(forwardTitle, action: onForward)
                .buttonStyle(StoryActionStyle(tint: StoryStyle.focus))
                .keyboardShortcut("]", modifiers: .command)
                .focused($focus, equals: .forward)
                .help("\(forwardTitle) (⌘])")
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
        Announcement.post(spoken)
    }

    /// A card that is waiting for the reader to act leaves the keyboard where
    /// they will act; anything else puts it on the way forward.
    private func takeFocus() {
        readerOnCard = true
        guard !progress.isWaiting else { return }
        DispatchQueue.main.async { focus = .forward }
    }
}
