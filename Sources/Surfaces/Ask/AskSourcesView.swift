import SwiftUI

/// Whether the sources list always sets a row's role under its label. The side
/// panel is always narrow, so it says so; the sheet lets the list decide.
private struct StacksAskSourcesKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var stacksAskSources: Bool {
        get { self[StacksAskSourcesKey.self] }
        set { self[StacksAskSourcesKey.self] = newValue }
    }
}

/// The places an answer rests on, in the order a reader can check it by. Each
/// row opens History at its place. Five show at first and "Show N more" opens
/// the rest. This list is the whole record, reachable by keyboard and
/// VoiceOver; the links inside the answer's text are only a convenience for
/// the eye. The rows read in the primary ink and the chevron says they open, so
/// the list does not outweigh the answer; the action colour is for the answer's
/// links and for "Show N more".
///
/// The layout is decided once for the whole list, so its rows are one height:
/// stacked (the role under the label) in the side panel, and in the sheet on one
/// line when every row fits there, stacked for all of them when one does not.
struct AskSourcesView: View {
    let sources: [AskSource]
    let onFollow: (AskLink) -> Void
    @Environment(\.stacksAskSources) private var alwaysStacked
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
                .font(Tokens.Typography.label)
                .foregroundStyle(StoryStyle.supportingInk)
                .accessibilityAddTraits(.isHeader)
            rows(shown)
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

    @ViewBuilder private func rows(_ shown: [AskSource]) -> some View {
        if alwaysStacked {
            list(shown, stacked: true)
        } else {
            ViewThatFits(in: .horizontal) {
                list(shown, stacked: false)
                list(shown, stacked: true)
            }
        }
    }

    private func list(_ shown: [AskSource], stacked: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, source in
                if index > 0 { Divider().padding(.horizontal, Tokens.Space.s) }
                AskSourceRow(number: index + 1, source: source, stacked: stacked, onFollow: onFollow)
            }
        }
    }

    private static var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous)
    }
}

/// One source: its number in the list, a calendar for a day or a period or a
/// clock for a session, its label, why it is listed, and a chevron. `stacked`
/// sets the role under the label; otherwise the two share a line.
private struct AskSourceRow: View {
    let number: Int
    let source: AskSource
    let stacked: Bool
    let onFollow: (AskLink) -> Void

    private var glyph: String {
        if case .session = source.link.target { return "clock" }
        return "calendar"
    }

    private var label: some View {
        Text(source.link.label)
            .font(Tokens.Typography.label)
            .foregroundStyle(.primary)
            .lineLimit(1)
    }

    private var role: some View {
        Text(source.link.role.rawValue)
            .font(Tokens.Typography.body)
            .foregroundStyle(StoryStyle.supportingInk)
            .lineLimit(1)
    }

    var body: some View {
        Button { onFollow(source.link) } label: {
            HStack(spacing: Tokens.Space.s) {
                Text("\(number)")
                    .font(Tokens.Typography.body.monospacedDigit())
                    .foregroundStyle(StoryStyle.supportingInk)
                    .frame(minWidth: 16.zoomed, alignment: .trailing)
                Image(systemName: glyph)
                    .font(Tokens.Typography.body)
                    .foregroundStyle(StoryStyle.supportingInk)
                    .frame(width: 16.zoomed)
                if stacked {
                    // The label gives up its middle: the date at the end of a
                    // session's label is the part that places it.
                    VStack(alignment: .leading, spacing: 0) {
                        label.truncationMode(.middle)
                        role
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    label.fixedSize()
                    Spacer(minLength: Tokens.Space.s)
                    role.fixedSize()
                }
                Image(systemName: "chevron.right")
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(StoryStyle.supportingInk)
            }
            .padding(.horizontal, Tokens.Space.s)
            .padding(.vertical, Tokens.Space.xs)
            .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(StoryPressStyle(hovers: true, cornerRadius: Tokens.Radius.control))
        .help(source.link.label)
        // The Button keeps its own press action; `.ignore` here took it away,
        // and VoiceOver could read a source but not open it.
        .accessibilityLabel(AskSourcesView.accessibilityLabel(for: source))
    }
}
