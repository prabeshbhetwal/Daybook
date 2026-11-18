import SwiftUI

/// Everything the report says about one session, gathered once so the view
/// reads from plain values and the numbers can be checked without a window.
struct SessionReport {
    struct Stretch: Identifiable {
        let id: UUID
        let start: Date
        let end: Date
        let worked: TimeInterval
        let note: String?
    }

    let session: DaySession
    let detail: StorySessionDetail
    let stretches: [Stretch]
    let power: PowerContextSummary?
    /// Each visit's power reading, by interval id, only where it changed.
    let powerChanges: [String: PowerReading]
    /// Why each listed gap is there, by interval id.
    var gapReasons: [String: StoryGapReason] = [:]
    /// The category the person usually files this kind of session under, when it can be offered.
    var suggestion: WorkType? = nil
    /// How the session began, for the mark under the figures.
    var origin: OriginText? = nil
    /// "Mostly media: 34 of 48 minutes", when the label the person or a rule chose and the time part ways.
    var contradiction: String? = nil

    var title: String { session.workType.sessionTitle(named: session.name) }
    var apps: [AppRank] { detail.apps }
    /// Every recorded visit and every gap, in order.
    var intervals: [RecordedActivity.Interval] { detail.activity.intervals }
    var visitCount: Int { intervals.filter { !$0.isGap }.count }

    /// When the session ran, with its day, for the header: a report opened
    /// from History is for a past day, and clock times alone do not say which.
    /// A session across midnight names both days.
    var whenText: String { when(joiner: "–") }
    /// The same line for VoiceOver, which would read the dash as a symbol.
    var whenSpoken: String { when(joiner: "to") }

    private func when(joiner: String) -> String {
        guard session.isRunning else {
            return DateFormats.datedClockRange(session.start, session.end, joiner: joiner)
        }
        // A session is clipped to its day; its stretches are not, and the
        // earliest says when it really began.
        let began = min(session.start, stretches.map(\.start).min() ?? session.start)
        return "Running since \(DateFormats.datedClockTime(began))"
    }

    /// A stretch's times. They carry their day when the stretch crosses
    /// midnight or lies on another day than the one the header gives, since
    /// the session is clipped to its day and its stretches are not.
    func stretchWhen(_ stretch: Stretch, joiner: String = "–") -> String {
        let calendar = Calendar.current
        return calendar.isDate(stretch.start, inSameDayAs: stretch.end)
            && calendar.isDate(stretch.start, inSameDayAs: session.start)
            ? "\(DateFormats.clockTime(stretch.start)) \(joiner) \(DateFormats.clockTime(stretch.end))"
            : DateFormats.datedClockRange(stretch.start, stretch.end, joiner: joiner)
    }

    /// The power state a visit ended on, when it differs from the visit
    /// before. Nil for a gap, an unchanged reading, or before any reading.
    func power(for interval: RecordedActivity.Interval) -> PowerReading? {
        powerChanges[interval.id]
    }

    static func make(for session: DaySession, store: SessionStore) -> SessionReport {
        // The session's own day, not whichever day the Story happens to be
        // on: a report opened from Insights or History is for a past day.
        let detail = store.storySessionDetail(session, on: session.start)
        let ids = Set(session.recordIDs)
        let stretches = store.engine.archive.records
            .filter { ids.contains($0.id) }
            .sorted { $0.start < $1.start }
            .map { record in
                Stretch(id: record.id, start: record.start, end: record.end, worked: record.workSeconds,
                        note: store.sessionMetadata(for: record.id)?.note)
            }
        let interval = DateInterval(start: session.start, end: max(session.start, session.end))
        let power = session.recordIDs.isEmpty ? nil
            : store.powerSummary(for: session.recordIDs, interval: interval)
        return SessionReport(session: session, detail: detail, stretches: stretches,
                             power: power,
                             powerChanges: PowerReading.changes(
                                 across: detail.activity.intervals,
                                 in: store.powerObservations(for: session.recordIDs)),
                             gapReasons: gapReasons(listing(detail.activity.intervals), store: store,
                                                    day: session.start),
                             suggestion: store.correctionSuggestion(for: session),
                             origin: store.originText(for: session),
                             contradiction: store.provenance(of: session).flatMap {
                                 ContradictionLine.text(category: session.workType, source: $0.categorySource,
                                                        credited: detail.phases?.credited ?? [:])
                             })
    }
}
