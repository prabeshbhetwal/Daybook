import SwiftUI

enum TodayInspectorKind: Equatable {
    case app
    case session
}

/// Lightweight presentation over the store's existing timeline and session
/// selections. It carries only canonical values already computed for the
/// selected day; no accounting is repeated here.
struct TodayInspectorData: Equatable {
    let kind: TodayInspectorKind
    let title: String
    let context: String
    let focused: TimeInterval?
    let tracked: TimeInterval?
    let appRanks: [AppRank]
    let stretches: [TimelineSegment]
    let bundleID: String?
    let colorIndex: Int
}

extension SessionStore {
    var todayInspector: TodayInspectorData? {
        if let session = selectedSession {
            let title = session.name.isEmpty ? session.workType.displayName : session.name
            return TodayInspectorData(
                kind: .session,
                title: title,
                context: "\(session.workType.displayName) · "
                    + Tokens.timeRange(session.start, session.end),
                focused: session.worked,
                tracked: sessionTracked,
                appRanks: sessionAppRanks,
                stretches: [],
                bundleID: nil,
                colorIndex: 0)
        }
        guard let segment = selectedSegment else { return nil }
        return TodayInspectorData(
            kind: .app,
            title: segment.appName,
            context: Tokens.timeRange(segment.start, segment.end),
            focused: nil,
            tracked: segment.seconds,
            appRanks: [],
            stretches: stretchesInSelectedHour,
            bundleID: segment.bundleID,
            colorIndex: segment.colorIndex)
    }

    /// Escape closes whichever Today inspection is active. The selected day is
    /// deliberately untouched: browsing scope and transient evidence are
    /// independent state.
    func clearTodaySelection() {
        clearTimelineSelection()
        clearSession()
        hoveredSegment = nil
        hoveredSession = nil
        highlightedBundleID = nil
    }

    /// The At the Mac row uses the same selection path as a direct ribbon
    /// click. It opens the most recent recorded stretch for that app without
    /// creating a second app-selection state.
    func selectTodayApp(_ bundleID: String) {
        if todayInspector?.kind == .app, todayInspector?.bundleID == bundleID {
            clearTimelineSelection()
            return
        }
        guard let segment = timelineSegments.last(where: { $0.bundleID == bundleID }),
              let layout = timelineLayout,
              let fraction = layout.fraction(for: segment.start.addingTimeInterval(
                min(1, max(0, segment.seconds / 2)))) else { return }
        clearSession()
        selectTimeline(at: fraction)
    }

    /// Today has one inspector at a time. Session selection therefore clears a
    /// prior app stretch before delegating to the established session API.
    func selectTodaySession(_ session: DaySession) {
        if selectedSession?.id == session.id {
            clearSession()
            return
        }
        clearTimelineSelection()
        selectSession(session)
    }

    /// Ribbon selection is the reverse of session selection: clear the session
    /// first, then preserve the established timeline toggle/hour-detail logic.
    func selectTodayTimeline(at fraction: Double) {
        clearSession()
        selectTimeline(at: fraction)
    }

}

/// The selected evidence beneath the ribbon. An app selection describes the
/// exact stretch and its hour; a session selection describes the declared work
/// and app-use intersection already computed by SessionStore.
struct TodayInspector: View {
    let data: TodayInspectorData
    var appSessions: [AppSession] = []
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            header
            if data.kind == .session { sessionBody } else { appBody }
        }
        .padding(Tokens.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Colour.elevated.opacity(0.72),
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.nested,
                                         style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous)
                .strokeBorder(Tokens.Colour.focus.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Tokens.Space.s) {
            if let bundleID = data.bundleID {
                AppSwatch(rank: data.colorIndex, bundleID: bundleID,
                          appName: data.title, size: 20)
            } else {
                Circle()
                    .fill(Tokens.Colour.focus)
                    .frame(width: 7, height: 7)
                    .padding(.top, 6)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(data.title)
                    .font(Tokens.Typography.rowTitle)
                Text(data.context)
                    .font(Tokens.Typography.metadata.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Tokens.Space.s)
            Button(action: onClose) {
                Label("Close inspector", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .frame(width: AccessibilityMetrics.minimumTargetSize,
                           height: AccessibilityMetrics.minimumTargetSize)
                    .background(Tokens.Colour.surface, in: Circle())
            }
            .buttonStyle(StoryPressStyle())
            .foregroundStyle(.secondary)
            .help("Close inspector (Esc)")
        }
    }

    private var sessionBody: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack(spacing: Tokens.Space.xxl) {
                inspectorMetric("Focused", data.focused)
                inspectorMetric("At the Mac", data.tracked)
                Spacer(minLength: 0)
            }
            if !data.appRanks.isEmpty {
                Divider()
                ForEach(Array(data.appRanks.prefix(4).enumerated()), id: \.element.id) {
                    index, app in
                    AppUsageRow(appName: app.appName, bundleID: app.bundleID,
                                rank: index, seconds: app.total, share: app.share,
                                layout: .compact)
                }
            }
        }
    }

    private var appBody: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            inspectorMetric("Selected stretch", data.tracked)
            if !data.stretches.isEmpty {
                Divider()
                ForEach(data.stretches.prefix(5)) { stretch in
                    HStack(spacing: Tokens.Space.s) {
                        Text(Tokens.timeRange(stretch.start, stretch.end))
                            .font(Tokens.Typography.metadata.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer(minLength: Tokens.Space.s)
                        Text(Tokens.preciseDuration(stretch.seconds))
                            .font(Tokens.Typography.metadata.monospacedDigit())
                    }
                }
            }
            if !appSessions.isEmpty {
                Divider()
                SectionHeader(
                    title: "Recent app sessions",
                    trailing: appSessions.count == 1 ? "1 newest session"
                        : "\(appSessions.count) newest sessions")
                ForEach(appSessions) { session in
                    HStack(spacing: Tokens.Space.s) {
                        Text(Tokens.timeRange(session.start, session.end))
                            .font(Tokens.Typography.metadata.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if session.visits > 1 {
                            Text("\(session.visits) visits")
                                .font(Tokens.Typography.metadata)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: Tokens.Space.s)
                        Text(Tokens.preciseDuration(session.attended))
                            .font(Tokens.Typography.metadata.monospacedDigit())
                    }
                    .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(Tokens.timeRange(session.start, session.end)), "
                                        + "\(Tokens.spent(session.attended)), "
                                        + "\(session.visits) visits")
                }
            }
        }
    }

    private func inspectorMetric(_ label: String, _ seconds: TimeInterval?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
            Text(seconds.map(Tokens.preciseDuration) ?? "—")
                .font(.callout.weight(.semibold).monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }
}
