import SwiftUI

/// A review note for one place: the model's story and pattern, a tip where a
/// label is given, and a caption saying where it was written. It draws
/// nothing while the model is unusable, whatever is still in memory, so
/// switching Apple Intelligence off hides every note at once.
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
    var insets = EdgeInsets()
    /// An on-request note stays behind its link until the link is pressed;
    /// it is asked for again, with its figures as they now are, each time
    /// the view comes back.
    @State private var asked = false

    static let failure = "Couldn't write a note for this period."
    private static let caption = "Apple Intelligence · on this Mac"

    private enum Shown {
        case link(String), writing, written(WrittenNote), failure
    }

    private var shown: Shown? {
        guard writer.isUsable else { return nil }
        let state = writer.state(for: place)
        if case .onRequest(let label) = trigger, !asked || state == nil { return .link(label) }
        switch state {
        case .writing?: return .writing
        case .written(let note)?: return .written(note)
        case .failed(requested: true)?: return .failure
        case .failed(requested: false)?, nil: return nil
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
        .onChange(of: writer.isUsable) { _, usable in if usable { write() } }
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
    /// is written afresh.
    private func write() {
        if case .automatic = trigger { writer.request(place, requested: false) }
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
