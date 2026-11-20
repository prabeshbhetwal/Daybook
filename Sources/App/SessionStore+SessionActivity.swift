import Foundation

/// What a derivation rested on: the same key gives the same shape, so a session is worked out again
/// only when its bounds, its counted time, the beats in it, the rules or the settings they read move.
/// A beat in another session does not.
struct SessionActivityKey: Equatable {
    let bounds: DateInterval
    let counted: [DateInterval]
    let beats: Int
    let algorithmVersion: Int
    let isRunning: Bool
    let countsWhileWatching: Bool
    let overridesDigest: String
    /// The signals its beats carry: a shape worked out without one is not the shape with it.
    let signals: Set<SignalKind>
}

struct SessionActivityMemo {
    let key: SessionActivityKey
    var shape: SessionActivityShape
}

/// One row of a session: a session over midnight is a row on each day, with one id.
struct SessionActivityMemoKey: Hashable {
    let session: UUID
    let rowStart: Date
    init(_ session: DaySession) { self.session = session.id; rowStart = session.start }
}

/// A record the sweep looked at and had nothing to write for, as it stood: no beats cover it, or its
/// summary is current, or the sidecar refused the write. A refusal is remembered against the sidecar's
/// revision, which moves only when the sidecar next saves something, so a sidecar that cannot be
/// written is not tried for every record on every heartbeat.
struct SettledRecord {
    let record: SessionRecord
    let sidecar: Int?
    /// The purpose overrides it was looked at under; its category's watching setting is read afresh.
    let overridesDigest: String
    let countsWhileWatching: Bool
}

/// Phases for a session row, and the summary a record keeps once its beats expire. Both record and
/// show: nothing here reads back into the engine, so no session counts, is named or is sorted
/// differently because of them.
extension SessionStore {
    private static let activityMemoLimit = 200
    /// Records written per sweep; the rest wait for the next heartbeat.
    private static let activitySnapshotsPerSweep = 20

    /// The session's phases from its beats while any lie in it; else the summary its records kept; else
    /// its app use alone. A running session is read from the beats that have closed, so its strip trails
    /// by at most one beat. Beats serve only a session they can cover whole: one that began before the
    /// oldest day file kept reads its summary, so expiry never swaps a complete summary for part of the
    /// evidence. `apps` is the session's app use when the caller has it.
    /// A row that is not running is read again only when its stamp moves, so an open card redrawn
    /// every second reads no beat file in between (`SessionActivityStamp`).
    func sessionActivity(for session: DaySession, apps: RecordedActivity? = nil) -> SessionActivityShape? {
        let bounds = DateInterval(start: session.start, end: max(session.start, session.end))
        guard bounds.duration > 0 else { return nil }
        let row = SessionActivityMemoKey(session)
        let stamp = session.isRunning ? nil : SessionActivityStamp(
            end: session.end, recordIDs: session.recordIDs, beats: activityEvidence.archive.revision,
            evidence: evidenceRevision, overridesDigest: SessionActivityShape.digest(engine.store.purposeOverrides),
            countsWhileWatching: session.workType.countsWhileWatching)
        if let stamp, let read = activityEvidence.stamped[row], read.stamp == stamp { return read.shape }
        let shape = readActivity(for: session, bounds: bounds, apps: apps)
        if let stamp {
            if activityEvidence.stamped.count >= Self.activityMemoLimit { activityEvidence.stamped.removeAll() }
            activityEvidence.stamped[row] = (stamp, shape)
        }
        return shape
    }

    private func readActivity(for session: DaySession, bounds: DateInterval, apps: RecordedActivity?) -> SessionActivityShape? {
        let evidence = activityEvidence
        let moment = now()
        let records = countedRecords(of: session, in: bounds, at: moment)
        // Beats over only part of the counted time pass over the kept summary too: an edit that added counted
        // time leaves it stale, and the app use covers the session whole.
        var partlyRecorded = false
        if evidence.archive.covers(from: bounds.start) {
            let beats = evidence.archive.beats(in: bounds)
            if !beats.isEmpty {
                if let shape = derivedActivity(for: session, bounds: bounds, records: records, beats: beats, at: moment) {
                    return shape
                }
                partlyRecorded = true
            }
        }
        let kept = session.recordIDs.compactMap { metadataArchive.metadata(for: $0)?.activityShape }
        if !partlyRecorded, !kept.isEmpty, kept.count == session.recordIDs.count, let joined = SessionActivityShape.joined(kept) {
            return joined.clipped(to: bounds)
        }
        let recorded = apps ?? RecordedActivity(segments: timelineSegments(of: session, on: session.start),
                                                spans: session.spans)
        // Its trusted pauses are not counted: app use goes on through a manual pause. With none of its records
        // found, its spans count whole.
        return ActivityDerivation.appsOnly(recorded, bounds: bounds, purposeOverrides: engine.store.purposeOverrides,
                                           counted: records.isEmpty ? nil : CountedTime.spans(records: records, beats: []))
    }

    /// Nil when the beats leave part of the counted time unrecorded (app use switched on partway): the row
    /// then reads its summary or apps rather than lend a neighbour's purpose to time nothing recorded.
    private func derivedActivity(for session: DaySession, bounds: DateInterval,
                                 records: [(bounds: DateInterval, paused: [DateInterval]?)], beats: [Beat],
                                 at moment: Date) -> SessionActivityShape? {
        let counted = CountedTime.spans(records: records, beats: beats)
        // A running row's counted time runs to now while its last beat is still open: it is tested to the last
        // closed beat, or the open seconds would tip it between its two readings as each beat closes.
        let reach = session.isRunning ? beats.map(\.end).max() ?? moment : moment
        let tested = session.isRunning ? counted.compactMap { span in
            span.start < reach ? DateInterval(start: span.start, end: min(span.end, reach)) : nil
        } : counted
        guard ActivityDerivation.recordsWhole(tested, beats: beats) else { return nil }
        let overrides = engine.store.purposeOverrides, watching = session.workType.countsWhileWatching
        let signals = SignalKind.carried(by: beats)
        let key = SessionActivityKey(bounds: bounds, counted: counted, beats: beats.count,
                                     algorithmVersion: ActivityConstants.algorithmVersion, isRunning: session.isRunning,
                                     countsWhileWatching: watching, overridesDigest: SessionActivityShape.digest(overrides),
                                     signals: signals)
        let row = SessionActivityMemoKey(session)
        if let memo = activityEvidence.memo[row], memo.key == key { return memo.shape }
        let shape = ActivityDerivation.derive(DerivationInput(
            credit: CreditInput(beats: beats, counted: counted, signals: signals, purposeOverrides: overrides),
            bounds: bounds, countsWhileWatching: watching,
            isRunning: session.isRunning, now: moment))
        if activityEvidence.memo.count >= Self.activityMemoLimit { activityEvidence.memo.removeAll() }
        activityEvidence.memo[row] = SessionActivityMemo(key: key, shape: shape)
        return shape
    }

    /// Each record's own pauses, the running one's from the engine, cut to `bounds`; nothing is read from
    /// the beats' presence.
    private func countedRecords(of session: DaySession, in bounds: DateInterval,
                                at moment: Date) -> [(bounds: DateInterval, paused: [DateInterval]?)] {
        session.recordIDs.compactMap { id -> (bounds: DateInterval, paused: [DateInterval]?)? in
            let record: (start: Date, end: Date, paused: [DateInterval]?)
            if engine.state != .idle, id == engine.activeRecordID {
                record = (engine.sessionStartDate, moment, engine.pausedSpansSoFar(until: moment))
            } else if let found = engine.archive.records.first(where: { $0.id == id }) {
                // The record's pauses only when they add up to its work, as everywhere else: an undone Away answer
                // lowers the work and leaves the pauses, and the beats then say what was paused.
                record = (found.start, found.end, found.exactPausedSpans)
            } else {
                return nil
            }
            let start = max(record.start, bounds.start), end = min(record.end, bounds.end)
            return end > start ? (DateInterval(start: start, end: end), record.paused) : nil
        }
    }

    /// An open card's detail: the day's projection leaves phases out, so they are added here, for this
    /// row alone. Without a projection the detail is worked out whole.
    func openSessionDetail(_ session: DaySession, in projection: StoryDayProjection?) -> StorySessionDetail {
        guard var detail = projection?.sessionDetails[session.id] else {
            return storySessionDetail(session, on: projection?.date ?? selectedDay)
        }
        detail.phases = sessionActivity(for: session, apps: detail.activity)
        return detail
    }

    /// The foreground-app segments inside the session's stretches.
    func timelineSegments(of session: DaySession, on day: Date) -> [TimelineSegment] {
        guard let usage else { return [] }
        var segments: [TimelineSegment] = []
        // The day's records only: this runs once per session in the day,
        // and the timeline clips to the day anyway.
        let timeline = DashboardStats(sessions: engine.archive, usage: usage,
            usageSnapshot: effectiveUsageSnapshot?.restricted(to: day)).timeline(for: day)
        for segment in timeline {
            for span in session.spans {
                let start = max(segment.start, span.start), end = min(segment.end, span.end)
                guard end > start else { continue }
                segments.append(TimelineSegment(id: segment.id, bundleID: segment.bundleID,
                    appName: segment.appName, start: start, end: end,
                    endReason: end == segment.end ? segment.endReason : .appSwitch))
            }
        }
        return segments
    }

    // MARK: - The summary a record keeps

    /// Called by `refresh()`: the first one with the engine idle and the archive changed since (a session
    /// just ended) writes the summaries, so it does not wait for a heartbeat an idle ticker may never send.
    /// While recording goes on the beat holding the record's last seconds may still be open, even when
    /// the record ended long ago (archived on wake): the heartbeat, which runs after the tick that closes
    /// it, writes the summary instead.
    func writeActivitySnapshotsAfterStop() {
        guard engine.state == .idle, !activityEvidence.recording,
              activityEvidence.sweptRevision != engine.archive.revision else { return }
        activityEvidence.sweptRevision = engine.archive.revision
        writeActivitySnapshots()
    }

    /// Writes a summary for each ended record, newest first, whose kept one is missing or stale: its
    /// bounds, counted time, the rules' version or the settings they read moved (an undone Away answer
    /// moves counted time). At most `activitySnapshotsPerSweep` written a call, and as many beat day files
    /// read: after a relaunch nothing is settled, and every record would read its days at once. Only
    /// records the beats still cover whole, and have beats; the rest keep what they have. A record already
    /// looked at and unchanged costs nothing (`settled`).
    func writeActivitySnapshots() {
        guard activityEvidence.enabled else { return }
        splitFinishedAutomaticSessions()
        let moment = now()
        let keepFrom = periodCalendar.date(byAdding: .day, value: -ActivityConstants.defaultBeatRetentionDays,
                                           to: moment) ?? .distantPast
        let recent = engine.archive.records.filter {
            $0.workType != .breakTime && $0.end > $0.start && $0.end > keepFrom
        }.sorted { $0.end > $1.end }
        if activityEvidence.settled.count > recent.count {
            let live = Set(recent.map(\.id))
            activityEvidence.settled = activityEvidence.settled.filter { live.contains($0.key) }
        }
        let overrides = engine.store.purposeOverrides, digest = SessionActivityShape.digest(overrides)
        let reads = activityEvidence.archive.dayFileReads
        var written = 0
        for record in recent {
            guard written < Self.activitySnapshotsPerSweep,
                  activityEvidence.archive.dayFileReads - reads < Self.activitySnapshotsPerSweep else { break }
            if writeActivitySnapshot(for: record, at: moment, overrides: (overrides, digest)) { written += 1 }
        }
        noteEndedRecordsForAssistant()
    }

    /// True when a write was tried, which counts against the sweep's limit.
    private func writeActivitySnapshot(for record: SessionRecord, at moment: Date,
                                       overrides: (all: [String: String], digest: String)) -> Bool {
        let evidence = activityEvidence
        let watching = record.workType.countsWhileWatching
        if let settled = evidence.settled[record.id], settled.record == record,
           settled.overridesDigest == overrides.digest, settled.countsWhileWatching == watching,
           settled.sidecar.map({ $0 == metadataArchive.revision }) ?? true { return false }
        // The beat holding the record's last seconds is still open while recording goes on: written now, the
        // summary would stay without them, as nothing below reads beats again once it matches. Next heartbeat.
        if evidence.recording, record.end > moment.addingTimeInterval(-ActivityConstants.beatLength) { return false }
        func settle(sidecar: Int? = nil) -> Bool {
            evidence.settled[record.id] = SettledRecord(record: record, sidecar: sidecar,
                                                        overridesDigest: overrides.digest, countsWhileWatching: watching)
            return false
        }
        let bounds = DateInterval(start: record.start, end: record.end)
        let kept = metadataArchive.metadata(for: record.id)?.activityShape
        // `signals` is nil until the beats are read: ended beats do not change, so a summary made from them
        // already lists what they carry, and one with known pauses needs no beat read to tell.
        func isCurrent(_ counted: [DateInterval], signals: Set<SignalKind>? = nil) -> Bool {
            guard let kept else { return false }
            return kept.bounds == bounds && kept.algorithmVersion == ActivityConstants.algorithmVersion
                && abs(kept.countedSeconds - counted.reduce(0) { $0 + $1.duration }) < 0.5
                && kept.countsWhileWatching == watching && kept.overridesDigest == overrides.digest
                && signals.map { Set(kept.signals) == $0 } ?? true
        }
        // With pauses that add up to its work the counted time needs no beat; without, it is read from the beats.
        let known = record.exactPausedSpans.map { CountedTime.spans(records: [(bounds: bounds, paused: $0)], beats: []) }
        if let known, isCurrent(known) { return settle() }
        guard evidence.archive.covers(from: bounds.start) else { return settle() }
        let beats = evidence.archive.beats(in: bounds)
        guard !beats.isEmpty else { return settle() }
        let counted = known ?? CountedTime.spans(records: [(bounds: bounds, paused: nil)], beats: beats)
        // Beats over only part of its counted time leave nothing to keep: the row reads its apps instead.
        guard ActivityDerivation.recordsWhole(counted, beats: beats) else { return settle() }
        let signals = SignalKind.carried(by: beats)
        if known == nil, isCurrent(counted, signals: signals) { return settle() }
        let shape = ActivityDerivation.derive(DerivationInput(
            credit: CreditInput(beats: beats, counted: counted, signals: signals, purposeOverrides: overrides.all),
            bounds: bounds, countsWhileWatching: watching,
            isRunning: false, now: moment))
        // Evidence never raises an alert: a refused write is quietly left until the sidecar next saves something.
        let saved = metadataArchive.saveActivityShape(shape, for: record.id) == .saved
        _ = saved ? settle() : settle(sidecar: metadataArchive.revision)
        return true
    }
}
