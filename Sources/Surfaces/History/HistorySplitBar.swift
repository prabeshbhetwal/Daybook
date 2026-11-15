import SwiftUI

/// A period row's focus by category: one thin bar with a gap between parts,
/// labelled as `CategoryShareBar` is. A part muted beside a neighbour of the
/// same hue draws at 55% of its colour, and Other in grey.
struct HistorySplitBar: View {
    let parts: [HistorySplitPart]

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            GeometryReader { geometry in
                // The gaps come out of the width first, so the bar stays
                // inside its row.
                let gap = 2.zoomed
                let width = max(0, geometry.size.width - gap * CGFloat(max(0, parts.count - 1)))
                HStack(spacing: gap) {
                    ForEach(parts) { part in
                        RoundedRectangle(cornerRadius: 2.zoomed, style: .continuous)
                            .fill(Self.colour(part))
                            .frame(width: max(2.zoomed, width * part.share))
                    }
                }
            }
            .frame(height: 8.zoomed)
            .accessibilityHidden(true)
            ChipFlow(spacing: Tokens.Space.m) {
                ForEach(parts) { part in
                    HStack(spacing: Tokens.Space.xs) {
                        Circle().fill(Self.colour(part))
                            .frame(width: 8.zoomed, height: 8.zoomed)
                        Text("\(part.workType?.displayName ?? "Other") \(DurationText.percent(part.share))")
                            .font(Tokens.Typography.body)
                            .foregroundStyle(StoryStyle.supportingInk)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    static func colour(_ part: HistorySplitPart) -> Color {
        guard let type = part.workType else { return Tokens.Palette.warmGrey }
        return Tokens.Palette.workType(type).opacity(part.isMuted ? 0.55 : 1)
    }
}
