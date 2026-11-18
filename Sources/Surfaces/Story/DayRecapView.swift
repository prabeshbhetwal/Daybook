import SwiftUI

/// Yesterday's figures at a glance: how the day compares with a typical one,
/// then where the time went, longest first, each row with a bar scaled to the
/// day's longest row, and when the focus peaked. All of it comes from `DayRecap`.
struct DayRecapView: View {
    let recap: DayRecap

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            if let delta = recap.delta { deltaChip(delta) }
            group("Sessions", rows: recap.sessions, more: recap.moreSessions, noun: "session")
            group("Apps", rows: recap.apps, more: recap.moreApps, noun: "app")
            if let peak = recap.peak {
                HStack(alignment: .firstTextBaseline) {
                    Text("Peak").foregroundStyle(StoryStyle.supportingInk)
                    Spacer(minLength: Tokens.Space.xs)
                    Text(durations: "\(peak.label) · \(DurationText.compact(peak.focused))")
                }
                .font(Tokens.Typography.caption.monospacedDigit())
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func deltaChip(_ delta: DayRecap.Delta) -> some View {
        let ink = delta.isAbove ? StoryStyle.successInk : StoryStyle.attentionInk
        return Label(delta.text, systemImage: delta.isAbove ? "arrow.up.right" : "arrow.down.right")
            .font(Tokens.Typography.label.monospacedDigit())
            .foregroundStyle(ink)
            .padding(.horizontal, 8.zoomed)
            .padding(.vertical, 3.zoomed)
            .background(ink.opacity(0.13), in: Capsule())
            .help(delta.detail)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(delta.text)
            .accessibilityHint(delta.detail)
    }

    @ViewBuilder private func group(_ title: String, rows: [DayRecap.Row], more: Int, noun: String) -> some View {
        if let longest = rows.first?.worked, longest > 0 {
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text(title).font(Tokens.Typography.caption).foregroundStyle(StoryStyle.supportingInk)
                ForEach(rows.indices, id: \.self) { row(rows[$0], longest: longest) }
                if more > 0 {
                    Text("+ \(more) more \(noun)\(more == 1 ? "" : "s")")
                        .font(Tokens.Typography.caption).foregroundStyle(StoryStyle.supportingInk)
                }
            }
        }
    }

    private func row(_ row: DayRecap.Row, longest: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 2.zoomed) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.name).lineLimit(1)
                Spacer(minLength: Tokens.Space.xs)
                Text(durations: DurationText.compact(row.worked)).monospacedDigit()
            }
            .font(Tokens.Typography.body)
            GeometryReader { bar in
                Capsule().fill(StoryStyle.action.opacity(0.55))
                    .frame(width: max(3.zoomed, bar.size.width * row.worked / longest))
            }
            .frame(height: 3.zoomed)
        }
        .accessibilityElement(children: .combine)
    }
}
