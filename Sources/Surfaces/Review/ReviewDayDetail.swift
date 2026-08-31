import SwiftUI

/// The inline explanation of one selected Review day. It composes a canonical
/// `ReviewDayDetail` and nothing else: no accounting, no archive access, and no
/// navigation of its own. Opening the day in Today is a named action the user
/// presses, never a side effect of selecting evidence.
struct ReviewDayDetailPanel: View {
    enum Presentation {
        case standalone
        case joined
    }

    let detail: ReviewDayDetail
    let onOpenInToday: () -> Void
    let onClose: () -> Void
    /// A History disclosure owns one shared surface: the selected row above it
    /// supplies the title and close action, while this lower section supplies
    /// the evidence. Elsewhere the panel remains independently titled.
    var presentation: Presentation = .standalone

    /// One row per app, not per visit. `AppUsageRow` colours by position, so a
    /// per-visit list showed the same app twice in two different identity
    /// colours — the one thing the stable app palette exists to prevent.
    private struct DayApp: Identifiable {
        let id: String
        let name: String
        let seconds: TimeInterval
    }

    private var dayApps: [DayApp] {
        var totals: [String: (name: String, seconds: TimeInterval)] = [:]
        for entry in detail.appEntries {
            let bundleID = entry.session.bundleID
            let running = totals[bundleID]?.seconds ?? 0
            totals[bundleID] = (entry.session.appName, running + entry.session.attended)
        }
        return totals
            .map { DayApp(id: $0.key, name: $0.value.name, seconds: $0.value.seconds) }
            .sorted { $0.seconds == $1.seconds ? $0.name < $1.name : $0.seconds > $1.seconds }
    }

    private var appRows: [DayApp] { Array(dayApps.prefix(5)) }

    private var focusRows: [ReviewFocusEntry] {
        Array(detail.focusEntries.sorted { $0.start < $1.start }.prefix(5))
    }

    var body: some View {
        switch presentation {
        case .joined:
            VStack(alignment: .leading, spacing: Tokens.Space.m) { content }
                .padding(.horizontal, Tokens.Space.l)
                .padding(.top, Tokens.Space.m)
                .padding(.bottom, Tokens.Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .standalone:
            SurfacePanel(showsHeader: false) { content }
        }
    }

    @ViewBuilder private var content: some View {
        if presentation == .standalone { header }
        metrics
        if appRows.isEmpty && focusRows.isEmpty {
            Text("No app or session evidence was recorded on this day.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            if !focusRows.isEmpty { focusEvidence }
            if !appRows.isEmpty { appEvidence }
        }
        actions
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Tokens.longDate(detail.day.date))
                    .font(Tokens.Typography.sectionTitle)
                Text("Selected day")
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Tokens.Space.m)
            IconButton(systemImage: "xmark", help: "Close the selected day",
                       action: onClose)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selected day, \(Tokens.longDate(detail.day.date))")
    }

    /// The same three canonical figures the History table states, in the same
    /// order, so a selected row and its detail can be read against each other.
    private var metrics: some View {
        HStack(alignment: .top, spacing: Tokens.Space.l) {
            detailMetric("Tracked", Tokens.duration(detail.day.tracked), note: "exact app usage")
            detailMetric("Focused", Tokens.duration(detail.day.focused),
                         note: detail.day.focused > 0 ? "focus sessions" : "no focus session")
            detailMetric("Sessions", "\(detail.day.sessions)",
                         note: detail.day.sessions == 1 ? "focus session" : "focus sessions")
        }
    }

    private func detailMetric(_ label: String, _ value: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text(label)
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
            Text(value)
                .font(Tokens.Typography.metricValue.monospacedDigit())
            Text(note)
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value), \(note)")
    }

    private var focusEvidence: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            SectionHeader(title: "Focus sessions", trailing: focusCountLabel)
            ForEach(Array(focusRows.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { Divider() }
                HStack(spacing: Tokens.Space.m) {
                    Image(systemName: entry.workType.symbolName)
                        .foregroundStyle(Tokens.Palette.workType(entry.workType))
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .font(Tokens.Typography.rowTitle)
                        Text(entry.workType.displayName + " · "
                             + Tokens.timeRange(entry.start, entry.end))
                            .font(Tokens.Typography.metadata)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: Tokens.Space.s)
                    Text(Tokens.preciseDuration(entry.seconds))
                        .font(.callout.monospacedDigit())
                }
                .padding(.vertical, Tokens.Space.xs)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var appEvidence: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            SectionHeader(title: "At the Mac", trailing: countLabel(dayApps.count,
                                                                    shown: appRows.count,
                                                                    noun: "app"))
            ForEach(Array(appRows.enumerated()), id: \.element.id) { index, app in
                if index > 0 { Divider() }
                AppUsageRow(appName: app.name,
                            bundleID: app.id,
                            rank: index,
                            seconds: app.seconds,
                            layout: .compact)
            }
        }
    }

    /// Work resumed after a break is one session in several stretches. The
    /// metric band counts sessions and this list shows stretches, so the label
    /// names both rather than leaving "Sessions 1" beside two visible rows.
    private var focusCountLabel: String {
        let stretches = detail.focusEntries.count
        let sessions = Set(detail.focusEntries.map(\.threadID)).count
        let sessionText = sessions == 1 ? "1 session" : "\(sessions) sessions"
        guard stretches != sessions || focusRows.count < stretches else { return sessionText }
        let stretchText = focusRows.count < stretches
            ? "\(focusRows.count) of \(stretches) stretches"
            : (stretches == 1 ? "1 stretch" : "\(stretches) stretches")
        return "\(sessionText) · \(stretchText)"
    }

    /// A bounded list must say what it is not showing.
    private func countLabel(_ total: Int, shown: Int, noun: String) -> String {
        let plural = total == 1 ? noun : noun + "s"
        return total > shown ? "\(shown) of \(total) \(plural)" : "\(total) \(plural)"
    }

    private var actions: some View {
        HStack {
            Button("Open this day's story", action: onOpenInToday)
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Opens the complete story for \(Tokens.longDate(detail.day.date))")
            Spacer()
        }
    }
}
