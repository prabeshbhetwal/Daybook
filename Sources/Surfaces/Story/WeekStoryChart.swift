import SwiftUI

/// The week as seven named columns. The bar is logged focus — the same measure
/// the headline ranks its strongest day by, and the same one the Month calendar
/// tints its cells with — so the three cannot disagree about which day was
/// best. Recorded app use is drawn behind it as context, never as the height.
struct WeekStoryChart: View {
    let days: [PeriodDay]
    /// Focus per day, keyed by local midnight.
    let facts: [Date: DayFacts]
    /// Recorded app use per day that has any, which is what the pale bars show.
    /// It is not a focus figure: the headline already states focus per day.
    let appUseAverage: TimeInterval
    let selectedDay: Date?
    let onPickDay: (Date) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let calendar = Calendar.current

    private func focused(_ day: PeriodDay) -> TimeInterval {
        facts[calendar.startOfDay(for: day.date)]?.focused ?? 0
    }

    /// One scale for both series, so the pale app-use bar is comparable with
    /// the focus bar rather than separately normalised.
    private var peak: TimeInterval {
        max(days.map { max(focused($0), $0.tracked) }.max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Text("Focus by day")
                .font(Tokens.Typography.metadata.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: Tokens.Space.s) {
                ForEach(days) { day in
                    column(for: day)
                }
            }
            .frame(height: 208)
            Text(caption)
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Focus by day")
    }

    private var caption: String { Self.caption(appUseAverage: appUseAverage) }

    static func caption(appUseAverage: TimeInterval) -> String {
        let base = "Solid bars are logged focus; the pale bar behind is recorded app use."
        guard appUseAverage > 0 else { return base }
        return base + " Recorded app use averages \(Tokens.duration(appUseAverage)) on days with any."
    }

    private func column(for day: PeriodDay) -> some View {
        let isSelected = selectedDay.map {
            calendar.isDate($0, inSameDayAs: day.date)
        } ?? false
        let focus = focused(day)
        return Button { onPickDay(day.date) } label: {
            VStack(spacing: Tokens.Space.xs) {
                Text(focus > 0 ? Tokens.preciseDuration(focus) : "—")
                    .font(Tokens.Typography.metadata.weight(.semibold).monospacedDigit())
                    .foregroundStyle(focus > 0 ? .primary : .tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                GeometryReader { geometry in
                    ZStack(alignment: .bottom) {
                        // App use sits behind, so a day with heavy use but
                        // little focus still reads as a low bar.
                        if day.tracked > 0 {
                            RoundedRectangle(cornerRadius: Tokens.Radius.control, style: .continuous)
                                .fill(Tokens.Colour.focus.opacity(0.16))
                                .frame(height: height(day.tracked, in: geometry.size.height))
                        }
                        if focus > 0 {
                            RoundedRectangle(cornerRadius: Tokens.Radius.control, style: .continuous)
                                .fill(isSelected ? Tokens.Colour.focus
                                                 : Tokens.Colour.focus.opacity(0.72))
                                .frame(height: height(focus, in: geometry.size.height))
                        } else {
                            RoundedRectangle(cornerRadius: Tokens.Radius.control, style: .continuous)
                                .fill(Tokens.Colour.elevated)
                                .frame(height: 3)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .animation(Tokens.Motion.animation(Tokens.Motion.settle, reduceMotion: reduceMotion),
                               value: focus)
                }
                Text(Tokens.weekdayName(day.date).prefix(3).uppercased())
                    .font(Tokens.Typography.microLabel.weight(isSelected ? .bold : .semibold))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Tokens.Colour.focus)
                                                : AnyShapeStyle(.secondary))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(StoryPressStyle(hovers: true))
        .animation(Tokens.Motion.animation(Tokens.Motion.selection, reduceMotion: reduceMotion),
                   value: isSelected)
        .accessibilityLabel(label(for: day, focus: focus))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Show this day")
    }

    private func height(_ value: TimeInterval, in available: CGFloat) -> CGFloat {
        max(5, available * CGFloat(min(1, max(0, value / peak))))
    }

    private func label(for day: PeriodDay, focus: TimeInterval) -> String {
        guard focus > 0 || day.tracked > 0 else {
            return "\(Tokens.longDate(day.date)), nothing recorded"
        }
        var parts = [Tokens.longDate(day.date)]
        parts.append(focus > 0 ? "\(Tokens.spent(focus)) focused" : "no logged focus")
        if day.tracked > 0 { parts.append("\(Tokens.duration(day.tracked)) recorded app use") }
        return parts.joined(separator: ", ")
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
                        RoundedRectangle(cornerRadius: Tokens.Radius.bar, style: .continuous)
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
            .accessibilityLabel("Focus by category")
        }
    }
}
