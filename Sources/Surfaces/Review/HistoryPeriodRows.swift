import SwiftUI

/// The filtered days folded into the span History is showing. A day row is
/// its own strip; a week or a month row is its days side by side.
struct HistoryPeriodGroup: Identifiable {
    let scope: InsightRange
    let start: Date
    let end: Date
    /// Newest first, as History lists them.
    let days: [HistoryDay]
    /// A span picked by hand has no calendar name of its own.
    var customTitle: String? = nil

    var id: Date { start }
    var focused: TimeInterval { days.reduce(0) { $0 + $1.focused } }
    var tracked: TimeInterval { days.reduce(0) { $0 + $1.tracked } }
    var sessions: Int { days.reduce(0) { $0 + $1.sessions } }
    var focusedDays: Int { days.filter { $0.focused > 0 }.count }

    var title: String {
        if let customTitle { return customTitle }
        let calendar = Calendar.current
        switch scope {
        case .day: return Tokens.longDate(start)
        case .year: return String(calendar.component(.year, from: start))
        case .week:
            let last = calendar.date(byAdding: .day, value: -1, to: end) ?? start
            return Tokens.dateRange(start, last)
        case .month:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_AU")
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: start)
        }
    }

    /// Every day slot of the period, oldest first, with the day that fell in
    /// it or nil: the row's cells keep the calendar's positions.
    var slots: [HistoryDay?] {
        let calendar = Calendar.current
        var result: [HistoryDay?] = []
        var cursor = start
        var visited = 0
        while cursor < end && visited < 31 {
            visited += 1
            result.append(days.first { calendar.isDate($0.date, inSameDayAs: cursor) })
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    static func group(_ days: [HistoryDay], scope: InsightRange,
                      calendar: Calendar = .current) -> [HistoryPeriodGroup] {
        let component: Calendar.Component = scope == .week ? .weekOfYear : scope == .year ? .year : .month
        var groups: [HistoryPeriodGroup] = []
        var current: [HistoryDay] = []
        var bounds: DateInterval?
        for day in days {
            let interval = scope == .day ? calendar.dateInterval(of: .day, for: day.date)
                                         : calendar.dateInterval(of: component, for: day.date)
            guard let interval else { continue }
            if let open = bounds, open.start != interval.start {
                groups.append(HistoryPeriodGroup(scope: scope, start: open.start, end: open.end, days: current))
                current = []
            }
            bounds = interval
            current.append(day)
        }
        if let open = bounds, !current.isEmpty {
            groups.append(HistoryPeriodGroup(scope: scope, start: open.start, end: open.end, days: current))
        }
        return groups
    }
}

/// The picked week or month in the rail: its figures, its days, and the way
/// into its story.
struct HistoryPeriodPreview: View {
    @ObservedObject var store: SessionStore
    let period: HistoryPeriodGroup
    var zoomTitle: String? = nil
    var onZoom: (() -> Void)? = nil
    let onOpen: () -> Void

    private var projections: [StoryDayProjection] {
        period.days.map { store.storyDayProjection(on: $0.date) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            StoryTile(title: period.title, trailing: nil) {
                Text(Tokens.preciseDuration(period.focused))
                    .font(Tokens.Typography.metricValue.monospacedDigit())
                    .foregroundStyle(period.focused > 0 ? AnyShapeStyle(Tokens.Colour.focus)
                                                        : AnyShapeStyle(.secondary))
                Text(note)
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Tokens.Space.l) {
                    if let zoomTitle, let onZoom {
                        Button(action: onZoom) {
                            Text("\(zoomTitle) ›")
                                .font(Tokens.Typography.metadata.weight(.semibold))
                                .foregroundStyle(StoryStyle.action)
                                .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
                        }
                        .buttonStyle(StoryPressStyle())
                    }
                    Button(action: onOpen) {
                        Text("Open as a story ›")
                            .font(Tokens.Typography.metadata.weight(.semibold))
                            .foregroundStyle(StoryStyle.action)
                            .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
                    }
                    .buttonStyle(StoryPressStyle())
                    .accessibilityLabel("Open \(period.title) as a story")
                }
            }
            StoryTile(title: "Days", trailing: period.days.count == 1 ? "1 recorded" : "\(period.days.count) recorded") {
                ForEach(period.days.prefix(14)) { day in
                    HStack(spacing: Tokens.Space.s) {
                        Text(Tokens.dayLabel(day.date))
                            .font(Tokens.Typography.metadata)
                            .lineLimit(1)
                        Spacer(minLength: Tokens.Space.xs)
                        Text(day.focused > 0 ? Tokens.duration(day.focused) : "—")
                            .font(Tokens.Typography.metadata.weight(.semibold).monospacedDigit())
                            .foregroundStyle(day.focused > 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if !apps.isEmpty {
                let limit = store.engine.store.menuAppCount
                StoryTile(title: apps.count > limit ? "Top \(limit) apps" : "Apps",
                          trailing: apps.count == 1 ? "1 recorded" : "\(apps.count) recorded") {
                    ForEach(Array(apps.prefix(limit).enumerated()), id: \.element.id) { index, app in
                        StoryAppRow(app: app, rank: index)
                    }
                }
            }
        }
    }

    private var note: String {
        var parts = [period.focusedDays == 1 ? "1 focused day" : "\(period.focusedDays) focused days"]
        if period.sessions > 0 { parts.append(period.sessions == 1 ? "1 session" : "\(period.sessions) sessions") }
        if period.tracked > 0 { parts.append("\(Tokens.duration(period.tracked)) recorded app use") }
        return parts.joined(separator: " · ")
    }

    private var apps: [AppRank] {
        var totals: [String: (name: String, total: TimeInterval, longest: TimeInterval)] = [:]
        for app in projections.flatMap(\.apps) {
            let existing = totals[app.bundleID]
            totals[app.bundleID] = (app.appName, (existing?.total ?? 0) + app.total,
                                    max(existing?.longest ?? 0, app.longest))
        }
        var sum: TimeInterval = 0
        for value in totals.values { sum += value.total }
        var ranks: [AppRank] = []
        for (key, value) in totals {
            let share: Double = sum > 0 ? value.total / sum : 0
            ranks.append(AppRank(bundleID: key, appName: value.name, total: value.total,
                                 share: share, longest: value.longest))
        }
        ranks.sort { (a: AppRank, b: AppRank) -> Bool in a.total > b.total }
        return ranks
    }
}

/// The category chip a session card wears, for rows that name a session.
struct WorkTypeChip: View {
    let workType: WorkType

    var body: some View {
        Text(workType.displayName)
            .font(Tokens.Typography.microLabel)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Tokens.Palette.workType(workType).opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(StoryStyle.workTypeInk(workType))
            .accessibilityHidden(true)
    }
}
