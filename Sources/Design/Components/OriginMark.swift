import SwiftUI

/// How a session began, as a small quiet mark (spec section 4, "Origin is shown, quietly"): a symbol and a
/// few words in the supporting ink. The words carry the meaning and the symbol only helps the eye; VoiceOver
/// and the tooltip give the whole sentence however much of it the row has room for.
struct OriginMark: View {
    let text: OriginText
    /// One fact to a line, each with its own symbol (the report), else one line that gives way when the
    /// row is narrow (the session row).
    var stacked = false

    var spoken: String { text.sentence }

    static func symbol(for kind: OriginText.Kind) -> String {
        switch kind {
        case .manual: return "person"
        case .rule: return "arrow.triangle.branch"
        case .automatic: return "bolt.badge.automatic"
        case .carriedOn: return "arrow.uturn.forward"
        case .namedByApp: return "tag"
        }
    }

    var body: some View {
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    ForEach(text.lines, id: \.kind) { fact($0.kind, $0.text) }
                }
            } else if let first = text.lines.first {
                fact(first.kind, text.lines.map(\.text).joined(separator: " · "))
            }
        }
        .help(spoken)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private func fact(_ kind: OriginText.Kind, _ words: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.xs) {
            Image(systemName: Self.symbol(for: kind))
                .frame(width: stacked ? 16.zoomed : nil)
            Text(words)
                .lineLimit(stacked ? nil : 1)
                .fixedSize(horizontal: false, vertical: stacked)
        }
        .font(Tokens.Typography.caption)
        .foregroundStyle(StoryStyle.supportingInk)
    }
}
