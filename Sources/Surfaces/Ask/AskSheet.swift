import SwiftUI

/// Ask Daybook: one question field, the answer below it, and the lookups the
/// answer rested on. The sheet only shows `AskModel`'s state and hands the
/// typed question to `model.ask`; a lookup can start nowhere else.
struct AskSheet: View {
    @ObservedObject var model: AskModel
    /// The field's own text. Kept after an answer or a failure, so ↩ asks
    /// again; only "New question" empties it.
    @State private var text: String
    @FocusState private var fieldFocused: Bool

    init(model: AskModel) {
        self.model = model
        _text = State(initialValue: model.question)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            if model.canAsk { field }
            if let notice = model.notice { noticeLine(notice) }
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.s) {
                    answer
                    if showsExamples { examples }
                    if !model.used.isEmpty {
                        Text(model.used)
                            .font(Tokens.Typography.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
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
            if model.notice == nil, !model.answer.isEmpty {
                AccessibilityNotification.Announcement(model.answer).post()
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
            .onSubmit { model.ask(text) }
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

    @ViewBuilder private var answer: some View {
        if model.answer.isEmpty {
            if model.isAnswering { ProgressView().controlSize(.small) }
        } else {
            Text(model.answer)
                .font(Tokens.Typography.control)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Examples and footer

    /// Before the first question: an empty sheet does not say what it can
    /// answer, and someone who found Ask by its button has not seen one asked.
    private var showsExamples: Bool {
        model.canAsk && model.answer.isEmpty && !model.isAnswering && model.notice == nil
    }

    private var examples: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text("Try asking")
                .font(Tokens.Typography.caption)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            ForEach(AskModel.examples, id: \.self) { example in
                Button(example) {
                    text = example
                    model.ask(example)
                }
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
            if !model.answer.isEmpty {
                Button("New question") {
                    model.newQuestion()
                    text = ""
                    fieldFocused = true
                }
                .buttonStyle(StoryActionStyle())
            }
        }
    }
}
