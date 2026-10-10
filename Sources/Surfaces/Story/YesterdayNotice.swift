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

    init(writer: NoteWriter, place: HistoryPlace, figures: String, onDone: @escaping () -> Void) {
        self.writer = writer
        self.place = place
        self.figures = figures
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
                    .foregroundStyle(.secondary)
                    .padding(.top, Tokens.Space.xs)
                PeriodNote(writer: writer, place: place, trigger: .automatic, tipLabel: "For today:",
                           insets: EdgeInsets(top: Tokens.Space.s, leading: 0, bottom: 0, trailing: 0))
                Button("Done", action: onDone)
                    .buttonStyle(StoryLinkStyle(tint: .secondary))
                    .padding(.top, Tokens.Space.xs)
            }
            .noteCard()
            .accessibilityElement(children: .contain)
        }
    }
}

extension View {
    /// The look of a notice on the rail: the backup offer's card.
    func noteCard() -> some View {
        padding(Tokens.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tokens.Colour.elevated,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
    }
}
