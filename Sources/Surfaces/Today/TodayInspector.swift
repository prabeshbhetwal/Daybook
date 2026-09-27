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

