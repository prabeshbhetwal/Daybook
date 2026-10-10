import SwiftUI

/// The places an answer rests on, in the order a reader can check it by. Each
/// row opens History at its place. Five show at first and "Show N more" opens
/// the rest. This list is the whole record, reachable by keyboard and
/// VoiceOver; the links inside the answer's text are only a convenience for
/// the eye.
struct AskSourcesView: View {
    let sources: [AskSource]
    let onFollow: (AskLink) -> Void
    @State private var expanded = false

    nonisolated static func visible(_ sources: [AskSource], expanded: Bool) -> (shown: [AskSource], hidden: Int) {
        let limit = AskSourcePicker.shownAtOnce
        guard !expanded, sources.count > limit else { return (sources, 0) }
        return (Array(sources.prefix(limit)), sources.count - limit)
    }

    /// "<label>, <role, lowercased>. Opens in History." The row shows its label
    /// on one line, cut short if it is long, so this carries all of it.
    nonisolated static func accessibilityLabel(for source: AskSource) -> String {
        "\(source.link.label), \(source.link.role.rawValue.lowercased()). Opens in History."
    }

    var body: some View {
        let (shown, hidden) = Self.visible(sources, expanded: expanded)
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Text("Sources")
                .font(Tokens.Typography.eyebrow)
                .textCase(.uppercase)
                .kerning(0.8.zoomed)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.offset) { index, source in
                    if index > 0 { Divider().padding(.horizontal, Tokens.Space.s) }
                    AskSourceRow(number: index + 1, source: source, onFollow: onFollow)
                }
            }
            .padding(Tokens.Space.xs)
            .background(Tokens.Colour.surface, in: Self.shape)
            .overlay(Self.shape.strokeBorder(Tokens.Colour.line, lineWidth: 1))
            if hidden > 0 {
                Button("Show \(hidden) more") { expanded = true }
                    .buttonStyle(StoryLinkStyle())
                    .accessibilityHint("Lists the other sources")
            }
        }
        .storyRenderEvidence(.askSources)
    }

    private static var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous)
    }
}

/// One source: its number in the list, a calendar for a day or a period or a
/// clock for a session, its label, why it is listed, and a chevron.
private struct AskSourceRow: View {
    let number: Int
    let source: AskSource
    let onFollow: (AskLink) -> Void

    private var glyph: String {
        if case .session = source.link.target { return "clock" }
        return "calendar"
    }

    private var label: some View {
        Text(source.link.label)
            .font(Tokens.Typography.label)
            .foregroundStyle(StoryStyle.action)
            .lineLimit(1)
    }

    private var role: some View {
        Text(source.link.role.rawValue)
            .font(Tokens.Typography.body)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    var body: some View {
        Button { onFollow(source.link) } label: {
            HStack(spacing: Tokens.Space.s) {
                Text("\(number)")
                    .font(Tokens.Typography.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 16.zoomed, alignment: .trailing)
                Image(systemName: glyph)
                    .font(Tokens.Typography.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 16.zoomed)
                // Label and role share a line when both fit whole. Otherwise
                // the role goes under the label, which gives up its middle:
                // the date at the end of a session's label is the part that
                // places it.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Tokens.Space.s) {
                        label.fixedSize()
                        Spacer(minLength: Tokens.Space.s)
                        role.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        label.truncationMode(.middle)
                        role
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Image(systemName: "chevron.right")
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Tokens.Space.s)
            .padding(.vertical, Tokens.Space.xs)
            .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(StoryPressStyle(hovers: true, cornerRadius: Tokens.Radius.control))
        .help(source.link.label)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AskSourcesView.accessibilityLabel(for: source))
        .accessibilityAddTraits(.isButton)
    }
}
