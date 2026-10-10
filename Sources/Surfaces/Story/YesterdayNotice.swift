import SwiftUI

/// Yesterday on Today's rail: its figures, the day's note and a Done that
/// closes the notice for that date. Gone while the model is unusable.
///
/// The rail works out `place` and `figures` when it offers the notice, since
/// both read projections, and holds them. `store` is not observed: the store
/// publishes every second, and nothing here changes with it.
struct YesterdayNotice: View {
    let store: SessionStore
    @ObservedObject var writer: NoteWriter
    let place: HistoryPlace
    /// "1h 30m focus · goal missed · 1 session".
    let figures: String
    @State private var closed = false

    var body: some View {
        if writer.isUsable, !closed {
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
                Button("Done") {
                    store.dismissYesterdayNote()
                    closed = true
                }
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
