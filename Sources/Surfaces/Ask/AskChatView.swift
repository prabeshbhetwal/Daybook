import SwiftUI

/// Ask Daybook as a conversation: the transcript, and under it the composer.
/// The view only shows `AskModel`'s state and hands what is typed to
/// `model.ask`; a lookup can start nowhere else. The sheet and the side panel
/// both show it.
struct AskChatView: View {
    @ObservedObject var model: AskModel
    /// What a source, in the text or in the list, opens.
    let onFollow: (AskLink) -> Void
    /// The field's own text. Emptied once a question starts an answer.
    @State private var text = ""
    @FocusState private var fieldFocused: Bool
    /// Whether the cursor was in the field when the question in progress was
    /// asked, and has not left it since. Only then does it come back to the
    /// field with the answer: beside History, a finished answer must not pull
    /// the cursor out of History.
    @State private var askedFromField = false

    init(model: AskModel, onFollow: @escaping (AskLink) -> Void) {
        self.model = model
        self.onFollow = onFollow
    }

    /// What Ask says aloud when an answer finishes: the answer, then its sources.
    nonisolated static func announcement(for turn: AskTurn) -> String {
        let answer = DurationText.spoken(in: turn.answer)
        let count = turn.sources.count
        return count == 0 ? answer : "\(answer) \(count) \(count == 1 ? "source" : "sources")."
    }

    var body: some View {
        VStack(spacing: 0) {
            transcript
            Divider()
            composer
        }
        .onAppear {
            model.prepare()
            focusField()
        }
        // A new chat, from outside this view (the header's button), forgets
        // what was typed and leaves the cursor where the next question goes.
        .onChange(of: model.turns.isEmpty) { _, isEmpty in
            guard isEmpty else { return }
            text = ""
            focusField()
        }
        // The cursor moved on while the answer was worked out, to History say: it stays there.
        .onChange(of: fieldFocused) { _, focused in
            if !focused, model.isAnswering { askedFromField = false }
        }
        .onChange(of: model.isAnswering) { wasAnswering, isAnswering in
            guard wasAnswering, !isAnswering else { return }
            if askedFromField { fieldFocused = true }
            if let last = model.turns.last, last.state == .answered {
                Announcement.post(Self.announcement(for: last))
            }
        }
    }

    // MARK: Transcript

    /// Fills the room it is given, from the top, and once it outgrows it stays
    /// at the bottom while an answer streams in.
    private var transcript: some View {
        GeometryReader { geometry in
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: Tokens.Space.xl) {
                        if model.turns.isEmpty {
                            emptyChat
                        } else {
                            ForEach(model.turns) { turn in
                                AskTurnView(turn: turn, onFollow: onFollow, openSettings: model.openIntelligenceSettings)
                                    .id(turn.id)
                            }
                        }
                    }
                    .padding(Tokens.Space.xl)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .topLeading)
                }
                .defaultScrollAnchor(.bottom)
                // A question asked after scrolling up is brought into view.
                .onChange(of: model.turns.count) { _, _ in
                    if let last = model.turns.last { reader.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    /// Before the first question: an empty chat does not say what it can
    /// answer, and someone who found Ask by its button has not seen one asked.
    private var emptyChat: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.l) {
            Text("Ask about your focus. Each answer lists the days and sessions it came from.")
                .font(Tokens.Typography.control)
                .fixedSize(horizontal: false, vertical: true)
            if model.canAsk && model.notice == nil {
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    Text("Try asking")
                        .font(Tokens.Typography.label)
                        .foregroundStyle(StoryStyle.supportingInk)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(AskModel.examples, id: \.self) { example in
                        Button(example) { send(example) }
                            .buttonStyle(StoryLinkStyle())
                            .accessibilityHint("Asks this question")
                    }
                }
            }
        }
    }

    // MARK: Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            if let notice = model.notice {
                AskNoticeLine(notice: notice, openSettings: model.openIntelligenceSettings)
            }
            HStack(spacing: Tokens.Space.s) {
                field
                if model.isAnswering {
                    Button { model.stop() } label: { Text("Stop").frame(minWidth: 40.zoomed) }
                        .buttonStyle(StoryActionStyle())
                        .keyboardShortcut(".", modifiers: .command)
                        .help("Stop answering (⌘.)")
                } else {
                    Button { send(text) } label: { Text("Send").frame(minWidth: 40.zoomed) }
                        .buttonStyle(StoryActionStyle(tint: StoryStyle.action))
                        .disabled(!model.canAsk || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            footer
        }
        .padding(.horizontal, Tokens.Space.xl)
        .padding(.vertical, Tokens.Space.m)
    }

    private var fieldShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous)
    }

    /// Stays editable while an answer is worked out; Return does nothing until it is done.
    /// One line high until the question needs more, then up to four.
    private var field: some View {
        TextField("Question", text: $text,
                  prompt: Text("Ask about your focus…").foregroundStyle(StoryStyle.supportingInk), axis: .vertical)
            .lineLimit(1...4)
            .textFieldStyle(.plain)
            .focused($fieldFocused)
            .onSubmit { send(text) }
            .accessibilityLabel("Question")
            .padding(.horizontal, Tokens.Space.m)
            .padding(.vertical, Tokens.Space.xs)
            .frame(minHeight: FilterChip<EmptyView, EmptyView>.height)
            .background(fieldShape.fill(Tokens.Colour.elevated)
                .shadow(color: StoryStyle.focus.opacity(fieldFocused ? 0.28 : 0), radius: 6.zoomed))
            .overlay(fieldShape.strokeBorder(fieldFocused ? StoryStyle.focus : Tokens.Colour.line,
                                             lineWidth: fieldFocused ? 1.5.zoomed : 1))
    }

    private func send(_ question: String) {
        guard !model.isAnswering else { return }
        let fromField = fieldFocused
        model.ask(question)
        if model.isAnswering {
            text = ""
            askedFromField = fromField
        }
    }

    /// The cursor goes to the field whenever the chat opens or starts over. Set
    /// while the view is still going into the window, the focus is lost to the
    /// control that had it (the bar's activity field, when the panel opens), so
    /// it is set a turn later.
    private func focusField() {
        DispatchQueue.main.async { fieldFocused = true }
    }

    /// Who answers, under Apple's own mark for it: the one place the
    /// Apple Intelligence glyph may stand, since it names Apple Intelligence.
    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.xs) {
            Image(systemName: "apple.intelligence")
                .accessibilityHidden(true)
            Text("Answered by Apple Intelligence on this Mac. Nothing leaves it.")
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(Tokens.Typography.body)
        .foregroundStyle(StoryStyle.supportingInk)
    }
}
