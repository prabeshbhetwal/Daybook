import SwiftUI

/// What the Mac did across the day, under its story, drawn like a gap card.
/// Folded, it says how long the Mac was locked or asleep and how often
/// Daybook quit, beside a bar of the day; unfolded, the track gains its times
/// and each stretch away from the desk gets a line, newest first like the
/// story above. The stretches are the ones the gap cards tell, read across
/// the whole day, so a lock and its unlock make one line, not four.
struct DayMachineEvents: View {
    let account: DayMacAccount
    @State private var isOpen = false
    @Environment(\.focusInterfaceDensity) private var density

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Button { isOpen.toggle() } label: { header }
                .buttonStyle(StoryPressStyle())
                .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
                .accessibilityHint(isOpen ? "Fold what the Mac did"
                                          : "Show when the Mac was locked, asleep or off, and when Daybook quit")
            if isOpen {
                GapTrack(span: account.span, anatomy: account.anatomy, plainUnexplained: true)
                Rectangle().fill(StoryStyle.line).frame(height: 1)
                GapStretchList(anatomy: account.anatomy, stretches: account.rows)
            }
        }
        .padding(StoryStyle.entryInsets(for: density))
        .background(StoryStyle.well.opacity(0.6), in: RoundedRectangle(cornerRadius: StoryStyle.entryRadius))
    }

    private var header: some View {
        HStack(spacing: Tokens.Space.m) {
            VStack(alignment: .leading, spacing: 2.zoomed) {
                Text("What the Mac did").font(Tokens.Typography.label)
                Text(account.summary).font(Tokens.Typography.body).foregroundStyle(StoryStyle.supportingInk)
            }
            Spacer(minLength: Tokens.Space.s)
            if !isOpen {
                GapBar(span: account.span, anatomy: account.anatomy, plainUnexplained: true)
                    .frame(width: 120.zoomed, height: 5.zoomed)
            }
            Image(systemName: "chevron.right")
                .font(Tokens.Typography.caption).foregroundStyle(StoryStyle.supportingInk)
                .rotationEffect(.degrees(isOpen ? 90 : 0))
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("What the Mac did, \(Tokens.timeRange(account.span.start, account.span.end)). "
                            + DurationText.spoken(in: account.summary) + ".")
    }
}
