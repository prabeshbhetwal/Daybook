import Foundation

/// A run of one app's stretches that the user experienced as one sitting.
struct AppSession: Identifiable, Equatable {
    let bundleID: String
    let appName: String
    let start: Date
    let end: Date
    /// Sum of the stretches. Gap time is never counted as usage.
    let attended: TimeInterval
    /// How many separate stretches make up the session.
    let visits: Int

    var id: String { "\(bundleID)-\(start.timeIntervalSinceReferenceDate)" }
    /// Wall time from first start to last end, gaps included.
    var span: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

/// Groups raw stretches into sessions. Pure, so the rule can be tested exactly
/// and retuned without re-recording history.
///
/// The rule is deliberately hybrid: a tunable gap handles the common case, and
/// knowing *why* a stretch ended handles the cases a fixed gap gets wrong —
/// a locked screen is a real boundary however brief, and stepping away without
/// touching anything else is not a context switch however long.
enum AppSessionGrouper {

    static func group(_ stretches: [TimelineSegment],
                      others: [TimelineSegment],
                      sessionGap: TimeInterval = AppUsageConstants.sessionGap,
                      awayBridge: TimeInterval = AppUsageConstants.awayBridge) -> [AppSession] {
        let ordered = stretches.sorted { $0.start < $1.start }
        guard !ordered.isEmpty else { return [] }

        var sessions: [AppSession] = []
        var current: [TimelineSegment] = [ordered[0]]

        for segment in ordered.dropFirst() {
            guard let previous = current.last else { continue }
            if joins(previous: previous,
                     next: segment,
                     others: others,
                     sessionGap: sessionGap,
                     awayBridge: awayBridge) {
                current.append(segment)
            } else {
                sessions.append(make(current))
                current = [segment]
            }
        }
        sessions.append(make(current))
        return sessions
    }

    private static func joins(previous: TimelineSegment,
                              next: TimelineSegment,
                              others: [TimelineSegment],
                              sessionGap: TimeInterval,
                              awayBridge: TimeInterval) -> Bool {
        // A locked screen ends the sitting, however short the gap.
        if previous.endReason == .systemLock { return false }

        let gap = next.start.timeIntervalSince(previous.end)
        guard gap > 0 else { return true }

        // Real work elsewhere is a context switch, not a detour.
        var elsewhere: TimeInterval = 0
        for other in others where other.start < next.start && other.end > previous.end {
            let start = max(other.start, previous.end)
            let end = min(other.end, next.start)
            elsewhere += max(0, end.timeIntervalSince(start))
        }
        if elsewhere >= sessionGap { return false }

        // Stepped away without using anything else: bridge the longer gap.
        if previous.endReason == .idle { return gap < awayBridge }
        return gap < sessionGap
    }

    private static func make(_ stretches: [TimelineSegment]) -> AppSession {
        let first = stretches[0]
        return AppSession(bundleID: first.bundleID,
                          appName: first.appName,
                          start: first.start,
                          end: stretches.map(\.end).max() ?? first.end,
                          attended: stretches.reduce(0) { $0 + $1.seconds },
                          visits: stretches.count)
    }
}

/// One hour's worth of an app's usage, for the drill-down strip.
struct HourBucket: Identifiable, Equatable {
    let hour: Date
    let seconds: TimeInterval
    var id: Date { hour }
}
