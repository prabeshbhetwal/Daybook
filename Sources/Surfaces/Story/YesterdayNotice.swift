import SwiftUI

/// Yesterday on Today's rail: its figures, the day's note and a Done that
/// closes the notice for that date. Gone while the model is unusable.
///
/// The rail works out `place` and `figures` when it offers the notice, since
/// both read projections, and holds them. `onDone` is the rail's to answer:
/// it records the dismissal and stops offering the notice, so a notice that is
/// closed stays closed when the rail is rebuilt.
struct YesterdayNotice: View {
    @ObservedObject var writer: NoteWriter
    let place: HistoryPlace
    /// "1h 30m focus · goal missed · 1 session".
    let figures: String
    let onDone: () -> Void
    /// Read when the rail builds the notice; see `PeriodNote.usable`.
    private let usable: Bool
    /// Read when the rail builds the notice, so the note under the figures
    /// checks its facts again when the archive changes; see `PeriodNote.evidence`.
    private let evidence: SessionStore.NoteEvidence

    init(writer: NoteWriter, place: HistoryPlace, figures: String, evidence: SessionStore.NoteEvidence,
         onDone: @escaping () -> Void) {
        self.writer = writer
        self.place = place
        self.figures = figures
        self.evidence = evidence
        self.onDone = onDone
        usable = writer.isUsable
    }

    var body: some View {
        if usable {
            VStack(alignment: .leading, spacing: 0) {
                Text("Yesterday")
                    .font(Tokens.Typography.rowTitle)
                    .accessibilityAddTraits(.isHeader)
                Text(durations: figures)
                    .font(Tokens.Typography.body.monospacedDigit())
                    .foregroundStyle(StoryStyle.supportingInk)
                    .padding(.top, Tokens.Space.xs)
                PeriodNote(writer: writer, place: place, evidence: evidence, trigger: .automatic,
                           insets: EdgeInsets(top: Tokens.Space.s, leading: 0, bottom: 0, trailing: 0))
                Button("Done", action: onDone)
                    .buttonStyle(StoryLinkStyle(tint: StoryStyle.supportingInk))
                    .padding(.top, Tokens.Space.xs)
            }
            .noteCard()
            .accessibilityElement(children: .contain)
        }
    }
}

extension View {
    /// The look of a notice on the rail: a row like the tiles below it, set
    /// off by the same hairline rather than a card of its own. The rail is one
    /// inspector column, and a grey card at its top read as a second surface.
    func noteCard() -> some View {
        modifier(RailNoticeRow())
    }
}

private struct RailNoticeRow: ViewModifier {
    @Environment(\.focusInterfaceDensity) private var density

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: StoryStyle.railSpacing(for: density)) {
            content
                .padding(.vertical, Tokens.Space.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
        }
    }
}
