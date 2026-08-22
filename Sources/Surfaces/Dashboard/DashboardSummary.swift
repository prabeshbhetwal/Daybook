import SwiftUI
import AppKit

/// The day — or the period — in words: the figures the page already shows,
/// joined into a few sentences that are always true of the data. Bold marks
/// the figures so the paragraph scans; the copy button puts the plain text on
/// the pasteboard for a journal or a message.
struct SummaryCard: View {
    let sentences: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack(alignment: .center) {
                SectionHeader(title: "Summary")
                Spacer()
                // A quiet text button, not a control: this is a reading card.
                Button {
                    let board = NSPasteboard.general
                    board.clearContents()
                    board.setString(SummaryText.plain(sentences), forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .help("Copy the summary as plain text")
            }
            Text(attributed)
                .font(.callout)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                // A measure: a line of 1,300pt is unreadable, whatever the type.
                .frame(maxWidth: 880, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .combine)
    }

    private var attributed: AttributedString {
        let markdown = sentences.joined(separator: " ")
        return (try? AttributedString(markdown: markdown))
            ?? AttributedString(SummaryText.plain(sentences))
    }
}
