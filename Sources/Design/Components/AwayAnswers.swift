import SwiftUI

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
    let onAnswer: (UserDecision) -> Void
    /// A name for the break, in the user's words — "dinner", "a call" — so it
    /// reaches the record. Nil hides the field. At most 24 characters: it has
    /// to fit on a timeline label.
    var onReason: ((String) -> Void)?
    @StateObject private var reason = ReasonBox()

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
                    // Return answers "break" — unless the reason field has text,
                    // when Return must log the name instead. Both firing on one
                    // keystroke recorded a nameless break before the name landed.
                    button(answers[0])
                        .keyboardShortcut(reason.text.isEmpty ? .defaultAction : nil)
                    button(answers[1])
                }
                HStack(spacing: Tokens.Space.s) {
                    button(answers[2])
                    button(answers[3])
                }
            }
            if onReason != nil { reasonField }
        }
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
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Color.accentColor, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Log it (Return)")
                .accessibilityLabel("Log the reason")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hasText)
        .padding(.horizontal, controlHorizontalPadding)
        // Same vertical room as the buttons (and the same optical shift), less
        // the submit circle's overhang, so the field matches the row above.
        .padding(.top, hasText ? max(1, controlVerticalPadding - 3) : controlVerticalPadding - 1)
        .padding(.bottom, hasText ? max(3, controlVerticalPadding - 1) : controlVerticalPadding + 1)
        .background(Tokens.Surface.well,
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.control, style: .continuous)
            .strokeBorder(Tokens.Surface.hairline))
        .help("Name the break and it is written down under that name")
    }

    private func submitReason() {
        let words = reason.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let trimmed = String(words.prefix(24)).trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        reason.text = ""
        onReason?(trimmed)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
            Label("Away \(Tokens.duration(away))", systemImage: "moon.zzz.fill")
                .font(compact ? .headline : .title3.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
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
        Button { onAnswer(answer.decision) } label: {
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
            .padding(.horizontal, controlHorizontalPadding)
            // Optically centred: SF's line box carries more headroom than
            // descent, so equal padding leaves the glyphs sitting low and the
            // tails reading as tight against the edge. Measured at 2×: 23 px
            // above the ink, 20 px below — hence a point shifted downward.
            .padding(.top, controlVerticalPadding - 1)
            .padding(.bottom, controlVerticalPadding + 1)
            .background(answer.prominent ? AnyShapeStyle(Color.accentColor)
                                         : AnyShapeStyle(Tokens.Surface.control),
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.control,
                                             style: .continuous))
            .foregroundStyle(answer.prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.control))
        }
        .buttonStyle(.plain)
        .help(showsCaptions ? "" : answer.caption)
        .accessibilityLabel("\(answer.title). \(answer.caption)")
    }
}

/// The reason field's text. `@State` is unavailable on this toolchain, so even
/// a single string needs an object behind it.
private final class ReasonBox: ObservableObject {
    @Published var text = ""
}
