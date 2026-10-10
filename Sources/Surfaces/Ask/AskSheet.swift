import SwiftUI

/// Ask Daybook: one question field, and the chat below it, each turn with
/// its answer and the lookups the answer rested on. The sheet only shows
/// `AskModel`'s state and hands the typed question to `model.ask`; a lookup
/// can start nowhere else.
struct AskSheet: View {
    @ObservedObject var model: AskModel
    /// The field's own text. Emptied once a question starts an answer.
    @State private var text = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            if model.canAsk { field }
            if let notice = model.notice { noticeLine(notice) }
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.m) {
                    ForEach(model.turns) { turn in turnView(turn) }
                    if showsExamples { examples }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .padding(Tokens.Space.xl)
        .onAppear {
            model.prepare()
            fieldFocused = true
        }
        .onChange(of: model.isAnswering) { wasAnswering, isAnswering in
            guard wasAnswering, !isAnswering else { return }
            fieldFocused = true
            if let last = model.turns.last, last.state == .answered {
                AccessibilityNotification.Announcement(last.answer).post()
            }
        }
    }

    // MARK: Field

    private var fieldShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous)
    }

    private var field: some View {
        TextField("Ask about your focus…", text: $text)
            .textFieldStyle(.plain)
            .focused($fieldFocused)
            .onSubmit { send(text) }
            .disabled(model.isAnswering)
            .accessibilityLabel("Question")
            .padding(.horizontal, Tokens.Space.m)
            .frame(height: FilterChip<EmptyView, EmptyView>.height)
            .background(fieldShape.fill(Tokens.Colour.elevated)
                .shadow(color: StoryStyle.focus.opacity(fieldFocused ? 0.28 : 0), radius: 6.zoomed))
            .overlay(fieldShape.strokeBorder(fieldFocused ? StoryStyle.focus : Tokens.Colour.line,
                                             lineWidth: fieldFocused ? 1.5.zoomed : 1))
    }

    // MARK: Notice and answer

    private func noticeLine(_ notice: AskNotice) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
            Text(notice.text)
                .font(Tokens.Typography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if notice.opensSettings {
                Button("Open Settings") { model.openIntelligenceSettings() }
                    .buttonStyle(StoryLinkStyle())
            }
        }
    }

    private func send(_ question: String) {
        model.ask(question)
        if model.isAnswering { text = "" }
    }

    /// The question, then what its turn has to show: the lookup being made, the
    /// answer as it streams, or the notice for an answer that failed.
    private func turnView(_ turn: AskTurn) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text(turn.question)
                .font(Tokens.Typography.caption)
                .foregroundStyle(.secondary)
            switch turn.state {
            case let .lookingUp(line):
                HStack(spacing: Tokens.Space.s) {
                    ProgressView().controlSize(.small)
                    if let line { Text(line).font(Tokens.Typography.caption).foregroundStyle(.secondary) }
                }
            case .answering, .answered, .stopped:
                Text(turn.answer)
                    .font(Tokens.Typography.control)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if turn.state == .stopped { caption("Stopped.") }
                if turn.state == .answered, !turn.provenance.isEmpty {
                    caption("Used: " + turn.provenance.joined(separator: " · "))
                }
            case let .failed(notice):
                noticeLine(notice)
            }
        }
    }

    private func caption(_ line: String) -> some View {
        Text(line)
            .font(Tokens.Typography.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }

    // MARK: Examples and footer

    /// Before the first question: an empty sheet does not say what it can
    /// answer, and someone who found Ask by its button has not seen one asked.
    private var showsExamples: Bool {
        model.canAsk && model.turns.isEmpty && model.notice == nil
    }

    private var examples: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text("Try asking")
                .font(Tokens.Typography.caption)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            ForEach(AskModel.examples, id: \.self) { example in
                Button(example) { send(example) }
                .buttonStyle(StoryLinkStyle())
                .accessibilityHint("Asks this question")
            }
        }
    }

    /// Who answers, under Apple's own mark for it: the one place the
    /// Apple Intelligence glyph may stand, since it names Apple Intelligence.
    private var footer: some View {
        HStack(spacing: Tokens.Space.s) {
            HStack(spacing: Tokens.Space.xs) {
                Image(systemName: "apple.intelligence")
                    .accessibilityHidden(true)
                Text("Answered by Apple Intelligence on this Mac. Nothing leaves it.")
            }
            .font(Tokens.Typography.caption)
            .foregroundStyle(.secondary)
            Spacer()
            if !model.turns.isEmpty {
                Button("New chat") {
                    model.newChat()
                    text = ""
                    fieldFocused = true
                }
                .buttonStyle(StoryActionStyle())
            }
        }
    }
}
