import SwiftUI

/// A review note for one place: the model's story and pattern, a tip where a
/// label is given, and a caption saying where it was written. It draws
/// nothing while the model is unusable, whatever is still in memory, so
/// switching Apple Intelligence off hides every note at once.
///
/// A note is shown whenever the writer holds one for the place, however the
/// view came to be: an on-request note that was written, or one that failed
/// when asked for, is shown again when its view is rebuilt, unless its facts
/// have changed since (`NoteWriter.forgetIfStale`), when its link returns. The
/// link shows only while there is nothing to show.
struct PeriodNote: View {
    enum Trigger {
        /// Written when the note appears.
        case automatic
        /// Written when the person presses the link.
        case onRequest(label: String)
    }

    @ObservedObject var writer: NoteWriter
    let place: HistoryPlace
    let trigger: Trigger
    /// The tip's label ("For today:"); nil leaves the tip out.
    let tipLabel: String?
    /// Room around the note, kept only while there is something to draw, so a
    /// note that shows nothing leaves no gap.
    let insets: EdgeInsets
    /// Whether the model was usable when the parent built this view. The
    /// writer does not publish when the switch changes, so a view that read
    /// it in its own body could be skipped as unchanged; read here, in the
    /// parent's redraw (which a change in Settings causes), it is an input
    /// that differs.
    private let usable: Bool
    /// Whether the person pressed the link in this view, so only a note they
    /// asked for in front of them is announced to VoiceOver.
    @State private var asked = false

    init(writer: NoteWriter, place: HistoryPlace, trigger: Trigger, tipLabel: String?,
         insets: EdgeInsets = EdgeInsets()) {
        self.writer = writer
        self.place = place
        self.trigger = trigger
        self.tipLabel = tipLabel
        self.insets = insets
        usable = writer.isUsable
    }

    static let failure = "Couldn't write a note for this period."
    private static let caption = "Apple Intelligence · on this Mac"

    private enum Shown {
        case link(String), writing, written(WrittenNote), failure
    }

    /// Nothing is shown for an automatic note with no state or an automatic
    /// failure; an on-request note shows its link then.
    private var shown: Shown? {
        guard usable else { return nil }
        switch (writer.state(for: place), trigger) {
        case (.writing?, _): return .writing
        case (.written(let note)?, _): return .written(note)
        case (.failed(requested: true)?, _): return .failure
        case (_, .onRequest(let label)): return .link(label)
        case (_, .automatic): return nil
        }
    }

    var body: some View {
        let shown = self.shown
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            switch shown {
            case .link(let label)?:
                Button(label) {
                    asked = true
                    writer.request(place, requested: true)
                }
                .buttonStyle(StoryLinkStyle())
                .accessibilityHint("Writes a short note with Apple Intelligence on this Mac.")
            case .writing?:
                Text("Writing…").font(Tokens.Typography.body).foregroundStyle(.secondary)
            case .written(let note)?:
                written(note)
            case .failure?:
                Text(Self.failure).font(Tokens.Typography.body).foregroundStyle(.secondary)
            case nil:
                EmptyView()
            }
        }
        .padding(shown == nil ? EdgeInsets() : insets)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear(perform: write)
        .onChange(of: usable) { _, usable in if usable { write() } else { writer.cancelAll() } }
        .onDisappear { writer.cancel(place) }
        .announcesChanges(to: asked ? announcement : nil)
    }

    private func written(_ note: WrittenNote) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text(durations: note.paragraph)
                .font(Tokens.Typography.body)
                .fixedSize(horizontal: false, vertical: true)
            if let tip = tipLine(note) {
                Text(durations: tip)
                    .font(Tokens.Typography.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label(Self.caption, systemImage: "apple.intelligence")
                .font(Tokens.Typography.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func tipLine(_ note: WrittenNote) -> String? {
        guard let tipLabel, let tip = note.tip else { return nil }
        return tipLabel + " " + tip
    }

    /// An automatic note is written as it appears. `request` is cheap to call
    /// again: an unchanged note comes back from memory, a renamed session's
    /// is written afresh. An on-request note is not written, but one written
    /// for figures that have since moved is forgotten, so its link is back.
    private func write() {
        switch trigger {
        case .automatic: writer.request(place, requested: false)
        case .onRequest: writer.forgetIfStale(place)
        }
    }

    /// What VoiceOver is told when a note the person asked for arrives.
    private var announcement: String? {
        switch writer.state(for: place) {
        case .written(let note)?: return [note.paragraph, tipLine(note)].compactMap { $0 }.joined(separator: " ")
        case .failed(requested: true)?: return Self.failure
        default: return nil
        }
    }
}

private extension WrittenNote {
    /// Story and pattern read as one paragraph.
    var paragraph: String { story + " " + pattern }
}
