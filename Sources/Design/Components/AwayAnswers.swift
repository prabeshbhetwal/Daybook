import SwiftUI
import AppKit

/// Native focus/action target over the existing SwiftUI answer visuals. This
/// keeps Return and Space local to the focused answer on macOS 13 and avoids a
/// window-scoped default shortcut that could fire from History search.
final class AwayAnswerNSButton: NSButton {
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let commandModifiers: NSEvent.ModifierFlags = [.command, .option, .control]
        if event.modifierFlags.intersection(commandModifiers).isEmpty,
           event.keyCode == 36 || event.keyCode == 49 {
            performClick(nil)
        } else {
            super.keyDown(with: event)
        }
    }
}

private struct AwayAnswerNativeButton: NSViewRepresentable {
    let label: String
    let help: String
    let action: () -> Void

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func activate() { action() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> AwayAnswerNSButton {
        let button = AwayAnswerNSButton(title: "", target: context.coordinator,
                                        action: #selector(Coordinator.activate))
        button.isBordered = false
        button.isTransparent = true
        button.focusRingType = .default
        configure(button, coordinator: context.coordinator)
        return button
    }

    func updateNSView(_ button: AwayAnswerNSButton, context: Context) {
        configure(button, coordinator: context.coordinator)
    }

    private func configure(_ button: AwayAnswerNSButton, coordinator: Coordinator) {
        coordinator.action = action
        button.setAccessibilityRole(.button)
        button.setAccessibilityLabel(label)
        button.setAccessibilityHelp(help)
    }
}

/// The four answers to "what was that?", as one grid used by every surface that
/// asks: the popover card, the dashboard card, the quick prompt, the full
/// prompt. Header says how long and when; the recommended answer is filled.
struct AwayAnswerGrid: View {
    let away: TimeInterval
    var range: (start: Date, end: Date)?
    var showsCaptions: Bool = false
    var compact: Bool = false
    /// What answering means for the work in hand — "Deep work continues — 2h
    /// 14m so far." Falls back to the bare fact when the caller has none.
    var note: String?
    var error: String?
    var onRetry: (() -> Void)?
    let onAnswer: (UserDecision) -> Bool
    /// A name for the break, in the user's words — "dinner", "a call" — so it
    /// reaches the record. Nil hides the field. At most 24 characters: it has
    /// to fit on a timeline label.
    var onReason: ((String) -> Bool)?
    @StateObject private var reason = AwayReasonDraft()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One set of metrics for the buttons and the field, so the field is the
    /// same height as the row above it and the text sits with air below it.
    /// SF Rounded, as the hero numerals already are. SF Pro's lowercase t is
    /// short with a slant-cut top, which at button size reads as a chopped
    /// letter — it is the typeface, not clipping (verified against plain
    /// AppKit), and Rounded's terminals make the same glyph read whole.
    private var controlFont: Font {
        Font.system(compact ? .callout : .body, design: .rounded).weight(.semibold)
    }
    private var controlVerticalPadding: CGFloat { compact ? 9 : (showsCaptions ? Tokens.Space.m : 11) }
    private var controlHorizontalPadding: CGFloat { compact ? Tokens.Space.m : Tokens.Space.l }

    private struct Answer: Identifiable {
        let decision: UserDecision
        let title: String
        let caption: String
        let prominent: Bool
        var id: String { decision.rawValue }
    }

    private var answers: [Answer] {
        [
            Answer(decision: .tookBreak, title: "It was a break",
                   caption: "Not counted, written down as rest", prominent: true),
            Answer(decision: .mergeTime, title: "I was working",
                   caption: "Count it as work on this session", prominent: false),
            Answer(decision: .continueSession, title: "I was away",
                   caption: "Not counted, nothing recorded", prominent: false),
            Answer(decision: .resetTimer, title: "Start fresh",
                   caption: "End that session where you left, begin a new one",
                   prominent: false)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? Tokens.Space.s : Tokens.Space.m) {
            header
            Text(note ?? "Not counted. Your session is still running.")
                .font(compact ? .caption : .callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: Tokens.Space.s) {
                HStack(spacing: Tokens.Space.s) {
                    button(answers[0])
                    button(answers[1])
                }
                HStack(spacing: Tokens.Space.s) {
                    button(answers[2])
                    button(answers[3])
                }
            }
            if onReason != nil { reasonField }
            if let error {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Answer not saved", systemImage: "exclamationmark.triangle")
                        .font(.caption.weight(.semibold))
                    Text(error).font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    if let onRetry {
                        Button("Retry saving", action: onRetry)
                            .buttonStyle(.borderless)
                            .font(.caption.weight(.semibold))
                            .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Tokens.Colour.attention.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Answer not saved")
            }
        }
        .onChange(of: range?.start) { _ in reason.text = "" }
    }

    /// One line: a word or three for what the break was. Return logs it as a
    /// break under that name; the field empties for next time.
    private var reasonField: some View {
        let hasText = !reason.text.trimmingCharacters(in: .whitespaces).isEmpty
        return HStack(spacing: Tokens.Space.s) {
            Image(systemName: "pencil.line")
                .font(.system(size: compact ? 12 : 13, weight: .medium))
                .foregroundStyle(.tertiary)
            TextField("Name it — dinner, a call, a walk", text: $reason.text)
                .textFieldStyle(.plain)
                .font(Font.system(compact ? .callout : .body, design: .rounded))
                .onSubmit(submitReason)
            // Appears with the first character; Return does the same thing.
            if hasText {
                Button(action: submitReason) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Tokens.Colour.onFocus)
                        .frame(width: AccessibilityMetrics.minimumTargetSize,
                               height: AccessibilityMetrics.minimumTargetSize)
                        .background(Tokens.Colour.focus, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Log it (Return)")
                .accessibilityLabel("Log the reason")
                .transition(reduceMotion ? .identity : .scale.combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8),
                   value: hasText)
        .padding(.horizontal, controlHorizontalPadding)
        // Same vertical room as the buttons (and the same optical shift), less
        // the submit circle's overhang, so the field matches the row above.
        .padding(.top, hasText ? max(1, controlVerticalPadding - 3) : controlVerticalPadding - 1)
        .padding(.bottom, hasText ? max(3, controlVerticalPadding - 1) : controlVerticalPadding + 1)
        .background(Tokens.Colour.elevated,
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous)
            .strokeBorder(Tokens.Colour.line))
        .help("Name the break and it is written down under that name")
    }

    private func submitReason() {
        guard let onReason else { return }
        reason.submit(using: onReason)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
            Label("Away \(Tokens.duration(away))", systemImage: "moon.zzz.fill")
                .font(compact ? .headline : .title3.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Tokens.Colour.attention)
            if let range {
                Text(Tokens.timeRange(range.start, range.end))
                    .font(compact ? .caption : .callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func button(_ answer: Answer) -> some View {
        card(answer)
            // An overlay is sized by what it covers. A ZStack sibling asking
            // for infinite height would instead let one card absorb whatever
            // the window offered, which is how a resized prompt spread its
            // answers down a whole display.
            .overlay(
                AwayAnswerNativeButton(
                    label: "\(answer.title). \(answer.caption)",
                    help: answer.caption,
                    action: {
                        if onAnswer(answer.decision) { reason.text = "" }
                    })
            )
            .help(showsCaptions ? "" : answer.caption)
    }

    private func card(_ answer: Answer) -> some View {
        VStack(alignment: .leading, spacing: 2) {
                Text(answer.title)
                    .font(controlFont)
                if showsCaptions {
                    Text(answer.caption)
                        .font(.caption)
                        .opacity(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
            .padding(.horizontal, controlHorizontalPadding)
            // Optically centred: SF's line box carries more headroom than
            // descent, so equal padding leaves the glyphs sitting low and the
            // tails reading as tight against the edge. Measured at 2×: 23 px
            // above the ink, 20 px below — hence a point shifted downward.
            .padding(.top, controlVerticalPadding - 1)
            .padding(.bottom, controlVerticalPadding + 1)
            .background(answer.prominent ? AnyShapeStyle(Tokens.Colour.focus)
                                         : AnyShapeStyle(Tokens.Colour.elevated),
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.nested,
                                             style: .continuous))
            .foregroundStyle(answer.prominent ? AnyShapeStyle(Tokens.Colour.onFocus)
                                              : AnyShapeStyle(.primary))
            .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.nested))
            .accessibilityHidden(true)
    }
}

/// A submitted label stays editable unless the owning answer is saved.
final class AwayReasonDraft: ObservableObject {
    @Published var text = ""

    @discardableResult
    func submit(using answer: (String) -> Bool) -> Bool {
        let words = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let trimmed = String(words.prefix(24)).trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        guard answer(trimmed) else { return false }
        text = ""
        return true
    }
}
