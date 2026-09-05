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

/// The stat cards and, on the day view, the ring beside them.
struct StatBand: View {
    let figures: [StatFigure]
    var goal: GoalProgress?

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Space.s) {
            ForEach(figures) { figure in
                StatCard(label: figure.label, value: figure.value,
                         context: figure.detail, contextTint: figure.tint)
            }
            if let goal {
                VStack(spacing: Tokens.Space.xs) {
                    GoalRing(progress: goal.share, diameter: 56, lineWidth: 6,
                             label: Tokens.duration(goal.achieved), isMet: goal.isMet)
                    Text("of \(Tokens.duration(goal.goal))")
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 96)
                .frame(maxHeight: .infinity)
                .card(padding: Tokens.Space.s)
                .accessibilityElement(children: .combine)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Daily tracked-time bars with a dashed average line. The average is what turns a
/// bar chart into a judgement — without it, bars are just bars.
/// The day under the pointer, for the period chart's hover label. `@State`
/// is unavailable on this toolchain.
private final class DayBox: ObservableObject {
    @Published var day: Date?
}

struct PeriodChart: View {
    let days: [PeriodDay]
    let average: TimeInterval
    var height: CGFloat = 150
    /// The day being inspected, so the bar that produced the open detail is
    /// visibly the selected one. Selection never changes a bar's height.
    var selectedDay: Date?
    /// A bar clicked: that day, so the surface can inspect it.
    var onPickDay: ((Date) -> Void)?
    @StateObject private var hovered = DayBox()

    /// The bars and their hit targets share this exact canonical tracked
    /// series. A selected chart value therefore routes the literal date that
    /// produced the visible bar rather than rebuilding a parallel date list.
    private var trackedPoints: [PeriodChartPoint] {
        PeriodChartData.tracked(days)
    }

    /// The day nearest the pointer's x, in plot coordinates.
    private func dayAt(_ point: CGPoint, _ proxy: ChartProxy, _ geo: GeometryProxy) -> Date? {
        let x = point.x - geo[proxy.plotAreaFrame].origin.x
        guard let date: Date = proxy.value(atX: x) else { return nil }
        return trackedPoints.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }?.date
    }

    private var hoverLabel: String? {
        guard let day = hovered.day,
              let entry = days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: day) })
        else { return nil }
        let focused = entry.byWorkType.filter { $0.workType.countsAsFocus }.reduce(0) { $0 + $1.seconds }
        var text = "\(Tokens.dayLabel(day)) · \(Tokens.duration(entry.tracked)) at the Mac"
        if focused > 0 { text += " · \(Tokens.duration(focused)) focused" }
        return text + (onPickDay == nil ? "" : " · click to open")
    }

    var body: some View {
        Group {
            if days.allSatisfy({ $0.tracked == 0 }) {
                Text("Nothing tracked in this period yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(height: height, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    chartLegend
                    Chart {
                        ForEach(trackedPoints) { point in
                            BarMark(x: .value("Day", point.date, unit: .day),
                                    y: .value("Minutes", point.seconds / 60))
                                .foregroundStyle(barStyle(for: point.date))
                                .cornerRadius(Tokens.Radius.bar)
                        }
                        if average > 0 {
                            RuleMark(y: .value("Average", average / 60))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .foregroundStyle(.secondary)
                                // Leading, over the reserved padding column: the
                                // trailing edge is where the final bar lives.
                                .annotation(position: .top, alignment: .leading, spacing: 2) {
                                    Text("avg \(Tokens.preciseDuration(average))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                        }
                    }
                    // Without an explicit domain the axis spans only the days that have
                    // bars, so a month with one busy week reads as a busy month.
                    .chartXScale(domain: PeriodChartLayout.domain(for: trackedPoints))
                    .chartYScale(domain: 0...PeriodChartLayout.yMaximumMinutes(
                        for: trackedPoints, average: average))
                    .chartLegend(.hidden)
                    .chartYAxis {
                        AxisMarks(position: .leading) {
                            AxisGridLine().foregroundStyle(Tokens.Colour.line)
                            AxisTick().foregroundStyle(Tokens.Colour.line)
                            AxisValueLabel().foregroundStyle(.secondary)
                        }
                    }
                    .chartYAxisLabel("minutes", position: .leading)
                    // Hover names the day under the pointer; a click opens it.
                    .chartOverlay { proxy in
                        GeometryReader { geo in
                            Rectangle().fill(Color.clear).contentShape(Rectangle())
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(let point): hovered.day = dayAt(point, proxy, geo)
                                    case .ended: hovered.day = nil
                                    }
                                }
                                .onTapGesture { location in
                                    if let day = dayAt(location, proxy, geo) { onPickDay?(day) }
                                }
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if let label = hoverLabel {
                            Text(label)
                                .font(Tokens.Typography.metadata)
                                .padding(.horizontal, Tokens.Space.s)
                                .padding(.vertical, 4)
                                .background(.regularMaterial, in: Capsule())
                                .padding(Tokens.Space.xs)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(height: height)
                }
            }
        }
        .accessibilityRepresentation { accessibilitySummary }
    }

    /// Selection is a restrained colour change, never a height change: the bar
    /// keeps encoding exact tracked time. Unselected bars step back only while
    /// something is actually selected.
    private func barStyle(for date: Date) -> Color {
        guard let selectedDay else { return Tokens.Palette.app(rank: 0) }
        return Calendar.current.isDate(date, inSameDayAs: selectedDay)
            ? Tokens.Colour.focus
            : Tokens.Palette.app(rank: 0).opacity(0.45)
    }

    private var chartLegend: some View {
        HStack(spacing: Tokens.Space.l) {
            Label("Bars: tracked time", systemImage: "chart.bar.fill")
            if average > 0 {
                Label("Dashed line: active-day average", systemImage: "minus")
            }
        }
        .font(Tokens.Typography.metadata)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private var accessibilitySummary: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Tracked time by day")
                .accessibilityAddTraits(.isHeader)
            ForEach(trackedPoints) { point in
                let isSelected = selectedDay.map {
                    Calendar.current.isDate(point.date, inSameDayAs: $0)
                } ?? false
                let summary = point.accessibilitySummary() + (isSelected ? ", selected" : "")
                if let onPickDay {
                    Button(summary) { onPickDay(point.date) }
                        .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                } else {
                    Text(summary)
                }
            }
            if average > 0 {
                Text("Active-day average, \(Tokens.spent(average)) tracked")
            }
        }
    }

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

/// Sessions in reverse chronological order, grouped by day with the day's total
/// in its header. Rows, hairline separators, no cards.
struct SessionLogList: View {
    let entries: [LogEntry]
    let dayTotals: [Date: TimeInterval]
    var groups: [LogAppGroup] = []
    var grouping: LogGrouping = .byTime
    /// Nil in the gallery, where there is no store to expand rows against.
    var store: SessionStore?
    /// The hourly strip only means anything for a single day; across a week it
    /// would be summing 24 buckets over seven days and calling it an hour.
    var showsHourly = false
    /// Bounds of the period, so an expanded app can chart its own days —
    /// including the ones it was not used at all.
    var periodBounds: (start: Date, end: Date)?
    /// Passed as a VALUE, never read back through `store`. A plain stored
    /// reference does not subscribe to the object, and every other input here is
    /// unchanged when only the expansion set mutates — so SwiftUI's structural
    /// comparison skipped this view's body and the chevron did not move until
    /// something else forced a rebuild.
    var expandedApps: Set<String> = []
    /// Same reasoning as `expandedApps`.
    var showsMinorApps = false

    private var showsMinor: Bool { showsMinorApps }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            SectionHeader(title: "App usage",
                          trailing: entries.isEmpty ? nil
                              : grouping == .byApp
                                  ? (groups.count == 1 ? "1 app" : "\(groups.count) apps")
                                  : entries.count == 1 ? "1 app session"
                                                       : "\(entries.count) app sessions")
            if entries.isEmpty {
                Text("No sessions in this period yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if grouping == .byApp {
                // Column headers, so the rows read as the table they are.
                HStack(spacing: Tokens.Space.m) {
                    Text("App")
                        .frame(width: 182, alignment: .leading)
                    Text("Share of tracked")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Time")
                        .frame(width: 66, alignment: .trailing)
                    Text("%")
                        .frame(width: 38, alignment: .trailing)
                }
                .font(Tokens.Typography.tabLabel)
                .kerning(0.5)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, Tokens.Space.s)
                .padding(.top, Tokens.Space.xs)
                let split = PeriodStats.splitMinor(groups)
                ForEach(Array(split.major.enumerated()), id: \.element.id) { index, group in
                    Divider()
                    appRow(group, rank: index)
                }
                if !split.minor.isEmpty {
                    Divider()
                    Button {
                        store?.toggleMinorApps()
                    } label: {
                        HStack(spacing: Tokens.Space.xs) {
                            Image(systemName: showsMinor ? "chevron.down" : "chevron.right")
                                .font(.caption2)
                            Text(showsMinor
                                 ? "Hide \(split.minor.count) apps under 30s"
                                 : "\(split.minor.count) more apps under 30s")
                            Spacer()
                            Text(Tokens.preciseDuration(
                                split.minor.reduce(0) { $0 + $1.total }))
                                .monospacedDigit()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(StoryPressStyle())
                    .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
                    if showsMinor {
                        ForEach(Array(split.minor.enumerated()), id: \.element.id) { i, group in
                            Divider()
                            appRow(group, rank: split.major.count + i)
                        }
                    }
                }
            } else {
                ForEach(groupedDays, id: \.self) { day in
                    HStack {
                        Text(Tokens.dayLabel(day))
                            .font(.callout.weight(.medium))
                        Spacer()
                        Text(Tokens.preciseDuration(dayTotals[day] ?? 0))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, Tokens.Space.s)
                    ForEach(entries.filter { $0.day == day }) { entry in
                        Divider()
                        row(entry)
                    }
                }
            }
        }
    }

    private var groupedDays: [Date] {
        var seen: [Date] = []
        for entry in entries where !seen.contains(entry.day) { seen.append(entry.day) }
        return seen
    }

    /// One line per app, expanding to that app's own chronology. Ten scattered
    /// Claude rows told you nothing without scrolling and adding up; this says
    /// the total first and keeps the detail one click away.
    @ViewBuilder private func appRow(_ group: LogAppGroup, rank: Int) -> some View {
        let expanded = expandedApps.contains(group.bundleID)
        VStack(alignment: .leading, spacing: 4) {
            PeriodAppRowButton(group: group, rank: rank, expanded: expanded) {
                store?.toggleExpanded(group.bundleID)
            }
            HStack(spacing: Tokens.Space.xs) {
                Text(Tokens.timeRange(group.firstStart, group.lastEnd))
                Text("·")
                Text(group.sessions.count == 1 ? "1 session"
                                               : "\(group.sessions.count) sessions")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.leading, 56)
            if expanded {
                HStack(spacing: Tokens.Space.l) {
                    detail("Longest", Tokens.preciseDuration(group.longest))
                    detail("Average", Tokens.preciseDuration(group.averageSession))
                    detail("Visits", "\(group.visits)")
                    detail("Sessions", "\(group.sessions.count)")
                }
                .padding(.leading, 56)
                .padding(.top, 4)

                if showsHourly, let store {
                    HourlyStrip(buckets: store.hourlyBuckets(for: group.bundleID),
                                colorIndex: min(rank, 6))
                        .padding(.leading, 56)
                        .padding(.top, 2)
                } else if let bounds = periodBounds {
                    DailyStrip(totals: group.dailyTotals(from: bounds.start, to: bounds.end),
                               colorIndex: min(rank, 6))
                        .padding(.leading, 56)
                        .padding(.top, 2)
                }
                ForEach(group.sessions) { entry in
                    HStack(spacing: Tokens.Space.m) {
                        Text(Tokens.timeRange(entry.session.start, entry.session.end))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 150, alignment: .leading)
                        if entry.session.visits > 1 {
                            Text("\(entry.session.visits) visits")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text(Tokens.preciseDuration(entry.session.attended))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 56)
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
    }

    /// A labelled figure inside the expanded panel. Small, but the label is the
    /// point: a bare "6m" beside a bare "45m" says nothing about which is which.
    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased())
                .font(Tokens.Typography.micro)
                .tracking(0.4)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption.monospacedDigit())
        }
    }

    private func row(_ entry: LogEntry) -> some View {
        HStack(spacing: Tokens.Space.m) {
            Text(Tokens.timeRange(entry.session.start, entry.session.end))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
            AppIcon(bundleID: entry.session.bundleID, size: 16,
                    appName: entry.session.appName)
            Text(entry.session.appName)
                .font(.callout)
                .lineLimit(1)
            if entry.session.visits > 1 {
                // Where the session grouping becomes visible to the reader.
                Text("· \(entry.session.visits) visits")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(Tokens.preciseDuration(entry.session.attended))
                .font(.callout.monospacedDigit())
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}
