import SwiftUI

// Rows with hairline separators, never per-row cards: the native list idiom, and
// it lets icon, bar and number align on a real grid.

/// One line per session, precomputed so the type checker stays inside budget.
private func sessionLine(_ session: AppSession) -> String {
    let range = Tokens.timeRange(session.start, session.end)
    let attended = Tokens.preciseDuration(session.attended)
    guard session.visits > 1 else { return "\(range)  ·  \(attended)" }
    return "\(range)  ·  \(attended) over \(session.visits) visits"
}

/// Minutes per hour for one app, in that app's own timeline colour so the strip
/// and the band above it agree at a glance.
struct HourlyStrip: View {
    let buckets: [HourBucket]
    let colorIndex: Int

    var body: some View {
        let peak = max(1, buckets.map(\.seconds).max() ?? 1)
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(buckets) { bucket in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(bucket.seconds > 0
                              ? AnyShapeStyle(TimelinePalette.color(colorIndex))
                              : AnyShapeStyle(.quaternary))
                        .frame(height: max(2, 26 * bucket.seconds / peak))
                    Text(DayTimelineView.hourLabel(bucket.hour))
                        .font(.system(size: 7))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .help(DayTimelineView.hourLabel(bucket.hour) + ": "
                      + Tokens.preciseDuration(bucket.seconds))
            }
        }
        .frame(height: 42, alignment: .bottom)
        .accessibilityLabel("Hourly usage")
    }
}

/// Apps used today that are not running now, each grouped into sittings.
struct EarlierTodayList: View {
    let apps: [AppDayHistory]
    var store: SessionStore?
    /// `Earlier today` on today, `Earlier that day` when the dashboard browses
    /// history. The section used to say "today" about yesterday.
    var title: String = "Earlier today"
    /// Passed as a VALUE, never read back through `store`; see `TopAppsList`.
    var expandedApps: Set<String> = []

    var body: some View {
        if !apps.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                SectionHeader(title: title,
                          trailing: apps.count == 1 ? "1 app" : "\(apps.count) apps")
                ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                    if index > 0 { Divider() }
                    row(app)
                }
            }
        }
    }

    private func row(_ app: AppDayHistory) -> some View {
        let expanded = expandedApps.contains(app.bundleID)
        let visible = expanded ? app.sessions.count : min(4, app.sessions.count)
        let hidden = app.sessions.count - visible

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Tokens.Space.s) {
                AppSwatch(rank: app.colorIndex, bundleID: app.bundleID,
                          appName: app.appName, size: 16)
                Text(app.appName).font(Tokens.Typography.rowTitle).lineLimit(1)
                Spacer()
                Text(Tokens.preciseDuration(app.total))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ForEach(app.sessions.prefix(visible)) { session in
                Text(sessionLine(session))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            if hidden > 0 {
                Button("+\(hidden) more") { store?.toggleExpanded(app.bundleID) }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(.tint)
            } else if expanded && app.sessions.count > 4 {
                Button("Show less") { store?.toggleExpanded(app.bundleID) }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, Tokens.Space.xs)
        .accessibilityElement(children: .combine)
    }
}

struct TopAppsList: View {
    let apps: [AppRank]
    let sessionsToday: Int
    /// Nil in the gallery, where there is no store to expand rows against.
    var store: SessionStore?
    /// The 320pt popover cannot afford the dashboard's fixed columns: a 120pt
    /// name plus 66pt and 38pt numbers leaves the bar no width and it collapses
    /// to a sliver.
    var compact: Bool = false
    /// This section is always the selected day, even when the log above it shows
    /// a week. Naming the day is what keeps the two from being read as one scope.
    var dayScopeLabel: String?
    /// The dashboard's card calls this "App share" and trails the app count;
    /// the popover keeps "Top apps" and the session count.
    var title: String = "Top apps"
    var trailingOverride: String?
    /// Passed as a VALUE, never read back through `store`. A plain stored
    /// reference does not subscribe to the object, and every other input here is
    /// unchanged when only the expansion set mutates — so SwiftUI's structural
    /// comparison skipped this view's body and the chevron did not move until
    /// something else forced a rebuild.
    var expandedApps: Set<String> = []
    @StateObject private var hover = HoverBox()

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            SectionHeader(title: dayScopeLabel.map { "\(title) · \($0)" } ?? title,
                          trailing: trailingOverride
                              ?? (sessionsToday == 1 ? "1 focus session today"
                                                     : "\(sessionsToday) focus sessions today"))
            if apps.isEmpty {
                Text("Tracking starts when you switch apps.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(apps.prefix(8).enumerated()), id: \.element.id) { index, app in
                    if index > 0 { Divider() }
                    expandableRow(app, rank: index)
                }
            }
        }
    }

    /// Collapsed: name, bar, total, and the day span beneath. Expanded: adds the
    /// hourly strip in the app's own colour, then its sittings.
    @ViewBuilder
    private func expandableRow(_ app: AppRank, rank: Int) -> some View {
        let isExpanded = expandedApps.contains(app.bundleID)
        VStack(alignment: .leading, spacing: 2) {
            row(app, rank: rank)
            if let store {
                if let span = store.span(for: app.bundleID) {
                    Text(Tokens.timeRange(span.start, span.end))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 32)
                }
                if isExpanded {
                    HourlyStrip(buckets: store.hourlyBuckets(for: app.bundleID),
                                colorIndex: min(rank, 6))
                        .padding(.leading, 32)
                        .padding(.top, 4)
                    ForEach(store.sessions(for: app.bundleID)) { session in
                        Text(sessionLine(session))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 32)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .background(hover.id == app.bundleID ? Tokens.Colour.hover : Color.clear,
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
        .onHover { inside in
            hover.id = inside ? app.bundleID : nil
            store?.highlightApp(inside ? app.bundleID : nil)
        }
        .onTapGesture { store?.toggleExpanded(app.bundleID) }
    }

    private func row(_ app: AppRank, rank: Int) -> some View {
        HStack(spacing: compact ? Tokens.Space.s : Tokens.Space.m) {
            AppSwatch(rank: min(rank, 6), bundleID: app.bundleID, appName: app.appName,
                      size: compact ? 16 : 20)
            Text(app.appName)
                .font(compact ? .caption : Tokens.Typography.rowTitle)
                .lineLimit(1)
                .frame(width: compact ? 72 : 120, alignment: .leading)
            DataBar(share: app.share, tint: Tokens.Palette.app(rank: min(rank, 6)))
                .frame(minWidth: compact ? 48 : 80, idealWidth: 120, maxWidth: .infinity)
            Text(Tokens.preciseDuration(app.total))
                .font((compact ? Font.caption : Tokens.Typography.rowTitle).monospacedDigit())
                .frame(width: compact ? 50 : 66, alignment: .trailing)
            Text("\(Int((app.share * 100).rounded()))%")
                .font(Tokens.Typography.metadata.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: compact ? 30 : 38, alignment: .trailing)
        }
        .padding(.vertical, Tokens.Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(app.appName), \(Tokens.spent(app.total)), "
                            + "\(Int((app.share * 100).rounded()))% of tracked time")
    }
}

/// Today-specific ranked app rows. Each row retains the stable app palette,
/// exact day total, share and full last-used range; selection routes back
/// through the ribbon so there is only one inspector state.
struct TodayAppsList: View {
    let apps: [AppRank]
    @ObservedObject var store: SessionStore
    var selectedBundleID: String?
    @StateObject private var hover = HoverBox()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "At the Mac",
                          trailing: apps.isEmpty ? nil
                            : (apps.count == 1 ? "1 app" : "\(apps.count) apps"))
                .padding(.bottom, Tokens.Space.xs)
            if apps.isEmpty {
                Text("No app activity recorded for this day.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, Tokens.Space.s)
            } else {
                ForEach(Array(apps.prefix(8).enumerated()), id: \.element.id) { index, app in
                    if index > 0 { Divider() }
                    row(app, rank: index)
                }
            }
        }
    }

    private func row(_ app: AppRank, rank: Int) -> some View {
        let selected = selectedBundleID == app.bundleID
        let span = store.span(for: app.bundleID)
        return Button { store.selectTodayApp(app.bundleID) } label: {
            HStack(spacing: Tokens.Space.s) {
                AppSwatch(rank: min(rank, 6), bundleID: app.bundleID,
                          appName: app.appName, size: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.appName)
                        .font(Tokens.Typography.rowTitle)
                        .lineLimit(1)
                    Text(span.map { Tokens.timeRange($0.start, $0.end) }
                         ?? "No recorded range")
                        .font(Tokens.Typography.metadata.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Tokens.Space.s)
                DataBar(share: app.share, tint: Tokens.Palette.app(rank: min(rank, 6)))
                    .frame(width: 72)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Tokens.preciseDuration(app.total))
                        .font(Tokens.Typography.rowTitle.monospacedDigit())
                    Text("\(Int((app.share * 100).rounded()))%")
                        .font(Tokens.Typography.metadata.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(width: 58, alignment: .trailing)
            }
            .padding(.horizontal, Tokens.Space.s)
            .frame(minHeight: Tokens.Density.compactRowHeight)
            .background(selected ? Tokens.Colour.focus.opacity(0.10)
                        : hover.id == app.bundleID ? Tokens.Colour.hover : Color.clear,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.nested,
                                             style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous)
                    .strokeBorder(Tokens.Colour.focus.opacity(selected ? 0.45 : 0), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hover.id = inside ? app.bundleID : nil
            store.highlightApp(inside ? app.bundleID : nil)
        }
        .help(selected ? "Close the app inspector" : "Inspect this app on the time ribbon")
        .accessibilityLabel("\(app.appName), \(Tokens.spent(app.total)), "
                            + "\(Int((app.share * 100).rounded()))% of At the Mac time")
    }
}

struct RunningNowList: View {
    let apps: [RunningApp]

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            SectionHeader(title: "Running now",
                          trailing: apps.count == 1 ? "1 app" : "\(apps.count) apps")
            if apps.isEmpty {
                Text("No apps detected.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                    if index > 0 { Divider() }
                    HStack(alignment: .top, spacing: Tokens.Space.s) {
                        AppIcon(bundleID: app.bundleID, size: 18, appName: app.appName)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.appName)
                                .font(Tokens.Typography.rowTitle)
                                .lineLimit(1)
                            // Apps with no launch date are filtered out upstream,
                            // so this always has a real time.
                            Text(app.launched.map { Tokens.timeOfDay($0) } ?? "")
                                .font(Tokens.Typography.metadata)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        if let openFor = app.openFor {
                            Text(Tokens.preciseDuration(openFor))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, Tokens.Space.xs)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

struct InsightsList: View {
    let insights: [Insight]

    var body: some View {
        // An empty array renders nothing at all — no placeholder cards.
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Space.m) {
                SectionHeader(title: "Insights")
                ForEach(insights) { insight in
                    HStack(alignment: .top, spacing: Tokens.Space.s) {
                        Image(systemName: insight.symbolName)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.tint)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(insight.headline)
                                .font(Tokens.Typography.rowTitle)
                                // The right column is 260pt and these headlines
                                // are sentences. Without this one read
                                // "10% of tracked time was in a focu…".
                                .fixedSize(horizontal: false, vertical: true)
                            Text(insight.detail)
                                .font(Tokens.Typography.metadata)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

struct FocusQualityBar: View {
    let quality: FocusQuality
    /// Day-scoped like `TopAppsList`; see the note there.
    var dayScopeLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            SectionHeader(title: dayScopeLabel.map { "Focus quality · \($0)" }
                            ?? "Focus quality")
            if quality.sessionCount == 0 {
                Text("No sessions yet today.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                GeometryReader { geometry in
                    HStack(spacing: 2) {
                        ForEach(quality.byWorkType) { share in
                            RoundedRectangle(cornerRadius: Tokens.Radius.bar)
                                .fill(Tokens.Palette.workType(share.workType))
                                .frame(width: max(4, geometry.size.width * share.share))
                        }
                    }
                }
                .frame(height: 8)
                HStack(spacing: Tokens.Space.m) {
                    ForEach(quality.byWorkType) { share in
                        HStack(spacing: Tokens.Space.xs) {
                            Circle().fill(Tokens.Palette.workType(share.workType))
                                .frame(width: 6, height: 6)
                            Text("\(share.workType.displayName) "
                                 + "\(Int((share.share * 100).rounded()))%")
                        }
                    }
                }
                .font(Tokens.Typography.metadata)
                HStack(spacing: Tokens.Space.xl) {
                    Text("\(Int((quality.insideSessionShare * 100).rounded()))% of tracked time in a session")
                    Text(String(format: "%.1f app switches per session", quality.switchesPerSession))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}
