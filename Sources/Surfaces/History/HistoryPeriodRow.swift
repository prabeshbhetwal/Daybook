import SwiftUI

/// A top row of History: the period's focus in one sentence, what stands out
/// about it, and where its focus went. The period holding today is the one
/// card; every other is a quiet row on the spine. It is the row's button
/// label, so it opens and folds as a plain row does.
struct HistoryPeriodRow: View {
    @ObservedObject var store: SessionStore
    let row: HistoryRow
    let facts: HistoryRowFacts
    let isCurrent: Bool
    let isOpen: Bool
    let isFocused: Bool
    @Environment(\.focusInterfaceDensity) private var density

    /// The gutter beside the spine for a root level: 0 for days,
    /// 56 for weeks, 32 for months, 36 for years (`.zoomed`).
    static func gutterWidth(for level: HistoryLevel) -> CGFloat {
        switch level {
        case .day: return 0
        case .week: return 56.zoomed
        case .month: return 32.zoomed
        case .year: return 36.zoomed
        }
    }

    var body: some View {
        let line = sentence(HistoryRowText.sentence(row, today: store.historyTop().today))
            .font(Tokens.Typography.rowTitle.monospacedDigit())
        let detail = HistoryRowText.detail(facts, row: row, calendar: SessionStore.historyCalendar)
        let parts = row.focused > 0 ? store.historySplit(for: row.place) : []
        return HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
            HistoryTreeRow.dot(row)
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                    if isCurrent {
                        line.storyRenderEvidence(.historySoFar)
                    } else {
                        line
                    }
                    Spacer(minLength: Tokens.Space.s)
                    if !row.isEmpty {
                        Image(systemName: "chevron.right")
                            .font(Tokens.Typography.caption)
                            .foregroundStyle(StoryStyle.supportingInk)
                            .rotationEffect(.degrees(isOpen ? 90 : 0))
                    }
                }
                if let detail {
                    Text(detail)
                        .font(Tokens.Typography.body)
                        .foregroundStyle(StoryStyle.supportingInk)
                }
                if !parts.isEmpty {
                    HistorySplitBar(parts: parts)
                        .padding(.top, Tokens.Space.xs)
                }
            }
            .padding(StoryStyle.entryInsets(for: density))
            .frame(maxWidth: .infinity, alignment: .leading)
            // The tint is the card's own, in front of its fill. On the button
            // it also covered the dot and the padding around the card, a
            // rectangle that stuck out of the card's edge on three sides.
            .hoverHighlight(cornerRadius: StoryStyle.entryRadius)
            .background(fill,in: RoundedRectangle(cornerRadius: StoryStyle.entryRadius, style: .continuous))
            .overlay {
                if isCurrent {
                    RoundedRectangle(cornerRadius: StoryStyle.entryRadius, style: .continuous)
                        .strokeBorder(isOpen ? Tokens.Colour.focus.opacity(0.55) : Tokens.Colour.line,
                                      lineWidth: isOpen ? 1.5.zoomed : 1)
                }
            }
            .keyboardFocusRing(isFocused, cornerRadius: StoryStyle.entryRadius)
        }
        .padding(.horizontal, HistoryRowLayout.inset)
        .padding(.bottom, Tokens.Space.s)
        .contentShape(Rectangle())
    }

    /// Only the period holding today is a card; a quiet row shows its fill
    /// only while the keyboard is on it.
    private var fill: AnyShapeStyle {
        if isFocused { return AnyShapeStyle(Tokens.Colour.focus.opacity(0.12)) }
        return isCurrent ? AnyShapeStyle(StoryStyle.card) : AnyShapeStyle(Color.clear)
    }

    /// The figure in the ink the headline gives its own, then the rest.
    private func sentence(_ line: (figure: String?, rest: String)) -> Text {
        guard let figure = line.figure else { return Text(line.rest) }
        return Text(figure).foregroundColor(StoryStyle.focus) + Text(" \(line.rest)")
    }
}
