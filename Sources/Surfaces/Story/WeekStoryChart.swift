import SwiftUI

/// The week as seven named columns: the figure above each bar, the weekday
/// under it, and a dash where nothing was recorded. A bar is tracked time and
/// only tracked time — work-type composition is told separately, never stacked
/// into the height.
struct WeekStoryChart: View {
    let days: [PeriodDay]
    let average: TimeInterval
    let selectedDay: Date?
    let onPickDay: (Date) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The tallest bar sets the scale. An empty week has no scale to draw, so
    /// the column heights stay flat rather than dividing by zero.
    private var peak: TimeInterval {
        max(days.map(\.tracked).max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Text("Tracked by day")
                .font(Tokens.Typography.metadata.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: Tokens.Space.s) {
                ForEach(days) { day in
                    column(for: day)
                }
            }
            .frame(height: 208)
            if average > 0 {
                Text("Bars are tracked time. The active-day average is "
                     + "\(Tokens.duration(average)).")
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Week by day")
    }

    private func column(for day: PeriodDay) -> some View {
        let isSelected = selectedDay.map {
            Calendar.current.isDate($0, inSameDayAs: day.date)
        } ?? false
        return Button { onPickDay(day.date) } label: {
            VStack(spacing: Tokens.Space.xs) {
                Text(day.tracked > 0 ? Tokens.preciseDuration(day.tracked) : "—")
                    .font(Tokens.Typography.metadata.weight(.semibold).monospacedDigit())
                    .foregroundStyle(day.tracked > 0 ? .primary : .tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(fill(isSelected: isSelected, tracked: day.tracked))
                            .frame(height: max(day.tracked > 0 ? 5 : 3,
                                               geometry.size.height
                                                   * (day.tracked / peak)))
                    }
                }
                Text(Tokens.weekdayName(day.date).prefix(3).uppercased())
                    .font(.caption2.weight(isSelected ? .bold : .semibold))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Tokens.Colour.focus)
                                                : AnyShapeStyle(.secondary))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Tokens.Motion.animation(Tokens.Motion.selection, reduceMotion: reduceMotion),
                   value: isSelected)
        .accessibilityLabel("\(Tokens.longDate(day.date)), "
                            + (day.tracked > 0 ? Tokens.spent(day.tracked) : "nothing recorded"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Show this day")
    }

    private func fill(isSelected: Bool, tracked: TimeInterval) -> Color {
        guard tracked > 0 else { return Tokens.Colour.elevated }
        return isSelected ? Tokens.Colour.focus : Tokens.Colour.focus.opacity(0.72)
    }
}

/// How the period's focus divided across work types, as the design's inline
/// legend. Shares come from the period rollup, so this is composition of
/// recorded focus and never a share of the whole day.
struct WorkTypeLegend: View {
    let shares: [WorkTypeShare]

    var body: some View {
        if !shares.isEmpty {
            HStack(spacing: Tokens.Space.l) {
                ForEach(shares) { share in
                    HStack(spacing: Tokens.Space.xs) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Tokens.Palette.workType(share.workType))
                            .frame(width: 10, height: 10)
                        Text(share.workType.displayName)
                            .font(Tokens.Typography.metadata)
                            .foregroundStyle(.secondary)
                        Text("\(Int((share.share * 100).rounded()))%")
                            .font(Tokens.Typography.metadata.weight(.semibold).monospacedDigit())
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(share.workType.displayName), "
                                        + "\(Int((share.share * 100).rounded())) per cent")
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Focus by work type")
        }
    }
}
