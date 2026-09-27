import SwiftUI
import Charts

extension PeriodChartPoint {
    /// Full spoken evidence for one chart point. The formatter follows the
    /// supplied calendar's locale and time zone so date and value cannot drift
    /// apart around local midnight.
    func accessibilitySummary(calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE d MMMM"
        return "\(formatter.string(from: date)), \(Self.spoken(seconds)) tracked"
    }

    private static func spoken(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        var parts: [String] = []
        if hours > 0 { parts.append(hours == 1 ? "1 hour" : "\(hours) hours") }
        if minutes > 0 { parts.append(minutes == 1 ? "1 minute" : "\(minutes) minutes") }
        if parts.isEmpty {
            parts.append(seconds == 1 ? "1 second" : "\(seconds) seconds")
        }
        return parts.joined(separator: " ")
    }
}

/// One headline figure with its context line and an optional tint for it.
struct StatFigure: Identifiable, Equatable {
    let label: String
    let value: String
    var detail: String?
    var tint: Color?
    /// One value per day for the card's sparkline; empty draws none.
    var spark: [Double] = []
    var sparkTint: Color?
    /// An SF Symbol beside the label, and a short qualifier pinned top-right —
    /// a compact status-grid anatomy: label · badge / value / chart /
    /// footer, so every card is read the same way.
    var symbol: String?
    var badge: String?
    var badgeTint: Color?
    var id: String { label }
}

/// One app's usage per day across the period, in that app's own colour so the
/// expanded panel and the row above it agree at a glance.
struct DailyStrip: View {
    let totals: [(day: Date, seconds: TimeInterval)]
    let colorIndex: Int

    static func accessibilitySummaries(
        _ totals: [(day: Date, seconds: TimeInterval)],
        calendar: Calendar = .current
    ) -> [String] {
        totals.map {
            PeriodChartPoint(date: $0.day, seconds: $0.seconds)
                .accessibilitySummary(calendar: calendar)
        }
    }

    var body: some View {
        let peak = max(1, totals.map(\.seconds).max() ?? 1)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(totals.enumerated()), id: \.offset) { _, entry in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(entry.seconds > 0
                              ? AnyShapeStyle(TimelinePalette.color(colorIndex))
                              : AnyShapeStyle(.quaternary))
                        .frame(height: max(2, 30 * entry.seconds / peak))
                    Text(Tokens.dayInitial(entry.day))
                        .font(Tokens.Typography.micro.weight(.regular))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .help(Tokens.dayLabel(entry.day) + ": "
                      + Tokens.preciseDuration(entry.seconds))
            }
        }
        .frame(height: 46, alignment: .bottom)
        .accessibilityRepresentation {
            VStack(alignment: .leading, spacing: 0) {
                Text("Daily usage across the period")
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(Self.accessibilitySummaries(totals).enumerated()),
                        id: \.offset) { _, summary in
                    Text(summary)
                }
            }
        }
    }
}

/// The app row's expansion affordance is a native Button, so keyboard and
/// VoiceOver users receive the same action as a pointer click. Its hit target,
/// literal measure and expanded state all live on the control itself.
struct PeriodAppRowButton: View {
    let group: LogAppGroup
    let rank: Int
    let expanded: Bool
    let onToggle: () -> Void
    @StateObject private var hover = HoverBox()

    var accessibilityLabelText: String {
        "\(group.appName), \(Tokens.spent(group.total)), "
            + "\(group.sessions.count) sessions, "
            + "\(Int((group.share * 100).rounded())) percent of tracked time"
    }

    var accessibilityValueText: String { expanded ? "Expanded" : "Collapsed" }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: Tokens.Space.m) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 10)
                AppSwatch(rank: min(rank, 6), bundleID: group.bundleID,
                          appName: group.appName, size: 18)
                Text(group.appName)
                    .font(Tokens.Typography.rowTitle)
                    .lineLimit(1)
                    .frame(width: 120, alignment: .leading)
                DataBar(share: group.share,
                        tint: Tokens.Palette.app(rank: min(rank, 6)))
                    .frame(minWidth: 80, idealWidth: 160, maxWidth: .infinity)
                Text(Tokens.preciseDuration(group.total))
                    .font(.callout.monospacedDigit())
                    .frame(width: 66, alignment: .trailing)
                Text("\(Int((group.share * 100).rounded()))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .trailing)
            }
            .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
            .contentShape(Rectangle())
            .background(hover.id == group.bundleID ? Tokens.Colour.hover : Color.clear,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.nested,
                                             style: .continuous))
        }
        .buttonStyle(StoryPressStyle())
        .onHover { hover.id = $0 ? group.bundleID : nil }
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityValue(accessibilityValueText)
        .accessibilityHint(expanded ? "Collapse daily and session details"
                                   : "Expand daily and session details")
        .accessibilityAddTraits(expanded ? .isSelected : [])
        .accessibilityAction(named: Text(expanded ? "Collapse details" : "Expand details"),
                             onToggle)
    }
}

