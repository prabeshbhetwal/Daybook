import SwiftUI

/// One question and what became of it: the question as a quiet pill, then the
/// lookup being made, the answer as prose with the places it names as links
/// and the sources it rests on, or the notice for an answer that failed.
/// VoiceOver reads a turn as one: what was asked and what Ask answered, with
/// the controls (sources, Open Settings) still reachable inside it.
struct AskTurnView: View {
    let turn: AskTurn
    let onFollow: (AskLink) -> Void
    let openSettings: () -> Void

    /// The scheme of a link inside an answer. The system never opens one:
    /// `OpenURLAction` below takes every click.
    nonisolated static let scheme = "daybook-ask"

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            question
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in
            guard let link = Self.link(for: url, in: turn.sources) else { return .discarded }
            onFollow(link)
            return .handled
        })
        .storyRenderEvidence(.askTranscript)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Self.spokenLabel(for: turn))
    }

    private var question: some View {
        Text(turn.question)
            .font(Tokens.Typography.body)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Tokens.Space.m)
            .padding(.vertical, Tokens.Space.s)
            .background(Tokens.Colour.elevated,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
            .padding(.leading, Tokens.Space.xxl)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var content: some View {
        switch turn.state {
        case let .lookingUp(line):
            HStack(spacing: Tokens.Space.s) {
                ProgressView().controlSize(Tokens.Zoom.controlSize(.small))
                if let line { Text(line).font(Tokens.Typography.body).foregroundStyle(StoryStyle.supportingInk) }
            }
            .accessibilityHidden(true)
        case .answering:
            prose
        case .answered:
            prose
            if !turn.sources.isEmpty { AskSourcesView(sources: turn.sources, onFollow: onFollow) }
        case .stopped:
            // What had streamed is dimmed, so a cut-off answer does not read as a finished one.
            if !turn.answer.isEmpty { prose(dimmed: true) }
            Text("Stopped.")
                .font(Tokens.Typography.body)
                .foregroundStyle(StoryStyle.supportingInk)
                .accessibilityHidden(true)
        case let .failed(notice):
            AskNoticeLine(notice: notice, tint: Tokens.Colour.danger, readsAloud: false, openSettings: openSettings)
        }
    }

    /// The longest an answer's lines run: about 75 characters at 13 points. The
    /// sheet is wider than that; the side panel is narrower, so it is unchanged.
    private static var proseMeasure: CGFloat { 480.zoomed }

    private var prose: some View { prose(dimmed: false) }

    private func prose(dimmed: Bool) -> some View {
        Text(Self.attributed(answer: turn.answer, sources: turn.sources))
            .font(Tokens.Typography.control)
            .foregroundStyle(dimmed ? AnyShapeStyle(StoryStyle.supportingInk) : AnyShapeStyle(.primary))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: Self.proseMeasure, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
    }
}

extension AskTurnView {
    /// The answer with each place it names a link to that place's row. Mentions
    /// become `.link` runs to `daybook-ask://source/<index>`, the index being the
    /// source's place in the list. Sources are taken in list order, and one whose
    /// words overlap a link already placed gets none: a week named by its two
    /// ends and a day inside it, or a day written without a year that names
    /// several. Mentions are Character offsets into `answer`, not UTF-16.
    /// The spaces inside a link are non-breaking, one Character each as before,
    /// so a date such as "Tue 15 Sep" is not split across two lines at a large zoom.
    nonisolated static func attributed(answer: String, sources: [AskSource]) -> AttributedString {
        var characters = Array(answer)
        var placed: [(url: URL, mention: Range<Int>)] = []
        for (index, source) in sources.enumerated() {
            guard let mention = source.mention, mention.lowerBound >= 0, mention.upperBound <= characters.count,
                  !mention.isEmpty, !placed.contains(where: { $0.mention.overlaps(mention) }),
                  let url = URL(string: "\(scheme)://source/\(index)") else { continue }
            placed.append((url, mention))
        }
        for link in placed {
            for position in link.mention where characters[position] == " " { characters[position] = "\u{00A0}" }
        }
        let spaced = String(characters)
        var text = AttributedString(spaced)
        for link in placed {
            let start = spaced.index(spaced.startIndex, offsetBy: link.mention.lowerBound)
            let end = spaced.index(start, offsetBy: link.mention.count)
            guard let range = Range(start..<end, in: text) else { continue }
            text[range].link = link.url
            text[range].foregroundColor = StoryStyle.action
            text[range].underlineStyle = .single
        }
        return text
    }

    /// The source a link in the text opens; nil for any other URL or an index the list lacks.
    nonisolated static func link(for url: URL, in sources: [AskSource]) -> AskLink? {
        guard url.scheme == scheme, url.host == "source", let index = Int(url.lastPathComponent),
              sources.indices.contains(index) else { return nil }
        return sources[index].link
    }

    /// "You asked … Ask answered …", with durations in words.
    nonisolated static func spokenLabel(for turn: AskTurn) -> String {
        let asked = "You asked \(sentence(turn.question))"
        let answer = DurationText.spoken(in: turn.answer)
        switch turn.state {
        case let .lookingUp(line): return "\(asked) \(line ?? "Ask is working on it.")"
        case .answering: return "\(asked) Ask is answering."
        case .answered: return "\(asked) Ask answered \(answer)"
        case .stopped: return answer.isEmpty ? "\(asked) Stopped." : "\(asked) Ask answered \(sentence(answer)) Stopped."
        case let .failed(notice): return "\(asked) \(notice.text)"
        }
    }

    private nonisolated static func sentence(_ text: String) -> String {
        guard let last = text.last, !".?!…".contains(last) else { return text }
        return text + "."
    }
}

/// Why Ask has no answer: one line, with the button that opens the pane that
/// fixes it when it has one. `tint` is the danger token for an answer that
/// failed, and the secondary colour for a Mac that cannot answer at all.
struct AskNoticeLine: View {
    let notice: AskNotice
    var tint: Color?
    /// False where the line's text is already part of what VoiceOver reads for the turn.
    var readsAloud = true
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
            Text(notice.text)
                .font(Tokens.Typography.body)
                .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(StoryStyle.supportingInk))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(!readsAloud)
            if notice.opensSettings {
                Button("Open Settings", action: openSettings)
                    .buttonStyle(StoryLinkStyle())
            }
        }
    }
}
