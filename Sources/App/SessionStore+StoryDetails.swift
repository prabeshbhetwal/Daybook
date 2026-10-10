import Foundation

struct StorySessionDetail {
    let apps: [AppRank]
    let text: String?
    /// The card's line under its figures; nil when there is nothing to add.
    let caption: String?
    /// The report's line under its figures, which already include recorded
    /// app use and the time range.
    let reportNote: String?
    /// Canonical app/gap timeline. The old bins remain during the chart
    /// migration, but ranks, captions and prose all use this same evidence.
    let activity: RecordedActivity
    let bins: [SessionShape.Bin]
}

/// Presentation items keep confirmations in the chronology without inserting
/// artificial sessions into the evidence archive.
/// One row of the story: an item shown in full, or a collapsed run of quiet
/// ones the reader can open.
enum StoryTimelineRow: Identifiable {
    case item(StoryTimelineItem)
    case quiet(StoryQuietRun)

    var id: String {
        switch self {
        case .item(let item): return item.id
        case .quiet(let run): return "quiet-" + run.id
        }
    }
}

extension StoryTimelineItem {
    /// The quiet moment this row carries, if it is one.
    var quietMoment: StoryMoment? {
        guard case .moment(let moment) = self,
              StoryQuietGrouping.isQuiet(moment) else { return nil }
        return moment
    }
}

extension Array where Element == StoryTimelineItem {
    /// Groups runs of `minimumRun` or more consecutive quiet rows. A shorter
    /// run stays expanded: hiding one interval behind a disclosure costs the
    /// reader a click and saves them nothing.
    func groupingQuietRuns(minimumRun: Int = 3) -> [StoryTimelineRow] {
        var rows: [StoryTimelineRow] = []
        var pending: [StoryTimelineItem] = []

        func flush() {
            guard !pending.isEmpty else { return }
            if pending.count >= minimumRun {
                rows.append(.quiet(StoryQuietGrouping.run(from: pending.compactMap(\.quietMoment))))
            } else {
                rows.append(contentsOf: pending.map(StoryTimelineRow.item))
            }
            pending = []
        }

        for item in self {
            if item.quietMoment != nil {
                pending.append(item)
            } else {
                flush()
                rows.append(.item(item))
            }
        }
        flush()
        return rows
    }
}

enum StoryTimelineItem: Identifiable {
    case moment(StoryMoment)
    case pending(DateInterval)
    case decision(AwayDecisionReceipt, DateInterval)
    case correction(UUID, String, DateInterval)

    var id: String {
        switch self {
        case .moment(let moment): return moment.id
        case .pending(let range): return "pending-\(range.start.timeIntervalSince1970)"
        case .decision(let receipt, _): return "decision-\(receipt.id.uuidString)"
        case .correction(let id, _, _): return "correction-\(id)"
        }
    }

    var start: Date {
        switch self {
        case .moment(let moment): return moment.start
        case .pending(let range), .decision(_, let range), .correction(_, _, let range): return range.start
        }
    }

    var isLive: Bool {
        if case .moment(.entry(.session(let session))) = self { return session.isRunning }
        return false
    }
}

extension SessionStore {
    func storySessionDetail(_ session: DaySession) -> StorySessionDetail {
        storySessionDetail(session, on: selectedDay)
    }

    /// The explicit day keeps historical projections independent of whichever
    /// Story date happens to be selected by another workspace.
    func storySessionDetail(_ session: DaySession, on day: Date) -> StorySessionDetail {
        var segments: [TimelineSegment] = []
        if let usage {
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
                        colorIndex: segment.colorIndex,
                        endReason: end == segment.end ? segment.endReason : .appSwitch))
                }
            }
        }
        let activity = RecordedActivity(segments: segments, spans: session.spans)
        let apps = activity.appRanks
        let text = SessionShape.storyProse(.init(segments: segments, activity: activity,
                                                 workType: session.workType,
                                                 stretches: session.stretches, worked: session.worked,
                                                 machineEvents: machineEvents(on: day)))
        let bounds = session.end > session.start ? DateInterval(start: session.start, end: session.end) : nil
        let bins = bounds.map { SessionShape.bins(activity: activity, in: $0) } ?? []
        let notes = Self.sessionEvidenceNotes(
            coverage: activity.coverage,
            elapsed: max(0, session.end.timeIntervalSince(session.start)),
            gap: activity.gapDuration,
            isRunning: session.isRunning,
            isTrackingEnabled: isTrackingEnabled,
            conflicting: activity.hasConflictingForegroundEvidence)
        return StorySessionDetail(apps: apps, text: text, caption: notes.card, reportNote: notes.report,
                                  activity: activity, bins: bins)
    }

    /// What a session's recording says beyond the figures beside it. The card
    /// already shows logged focus as its clock, so its caption leaves that out.
    /// The report also shows recorded app use and the time range, so its note
    /// keeps only the recording gap. A running session with recording off says
    /// nothing on the card, because the day's banner already says it.
    static func sessionEvidenceNotes(coverage: TimeInterval, elapsed: TimeInterval,
                                     gap: TimeInterval, isRunning: Bool,
                                     isTrackingEnabled: Bool,
                                     conflicting: Bool) -> (card: String?, report: String?) {
        var card: String?
        var report: String?
        if coverage > 0 {
            let gapNote = gap >= 1
                ? "\(Tokens.preciseDuration(gap)) of the session span has no app recording." : nil
            card = "Recorded app use: \(Tokens.preciseDuration(coverage)) across "
                + "\(Tokens.preciseDuration(elapsed)) elapsed." + (gapNote.map { " " + $0 } ?? "")
            report = gapNote
        } else if isRunning {
            card = isTrackingEnabled ? "No app use recorded yet." : nil
            report = isTrackingEnabled ? "No app use recorded yet."
                                       : "App recording is off, so no app use is being recorded."
        } else {
            card = "No app recording was available for this session."
                + (isTrackingEnabled ? "" : " App recording is off.")
            report = card
        }
        if conflicting {
            let note = "Overlapping source app records were resolved to one foreground strip."
            card = card.map { $0 + " " + note } ?? note
            report = report.map { $0 + " " + note } ?? note
        }
        return (card, report)
    }

    var storyTimelineItems: [StoryTimelineItem] {
        storyTimelineItems(on: selectedDay)
    }

    func storyTimelineItems(on selectedDate: Date) -> [StoryTimelineItem] {
        guard let day = Calendar.current.dateInterval(of: .day, for: selectedDate) else { return [] }
        func clipped(_ range: DateInterval) -> DateInterval? {
            let start = max(day.start, range.start), end = min(day.end, range.end)
            return end > start ? DateInterval(start: start, end: end) : nil
        }
        var moments = storyMoments(on: selectedDate)
        var notices: [StoryTimelineItem] = []
        for receipt in engine.awayDecisions {
            guard let range = clipped(receipt.range) else { continue }
            // The receipt is the representation of its classified interval;
            // do not repeat the same break below the green confirmation row.
            moments.removeAll {
                if case .entry(let entry) = $0 { return entry.id == receipt.insertedRecord?.id }
                return false
            }
            moments = moments.flatMap { moment -> [StoryMoment] in
                guard case .unrecorded(let gap, let reason) = moment,
                      gap.end > range.start, gap.start < range.end else { return [moment] }
                var fragments: [StoryMoment] = []
                if gap.start < range.start { fragments.append(.unrecorded(DateInterval(start: gap.start, end: range.start), reason: reason)) }
                if gap.end > range.end { fragments.append(.unrecorded(DateInterval(start: range.end, end: gap.end), reason: reason)) }
                return fragments
            }
            notices.append(.decision(receipt, range))
        }
        var presentedThreads = Set<UUID>()
        for correction in corrections.reversed() where presentedThreads.insert(correction.threadID).inserted {
            if correction.correction == .removed {
                // Nothing of the session is left to attach the notice to; the
                // journal remembers its span.
                if let range = correction.removedRange.flatMap(clipped) {
                    notices.append(.correction(correction.id, "Session removed", range))
                }
                continue
            }
            let ids = Set(engine.archive.records.filter { $0.threadID == correction.threadID }.map(\.id))
            if let match = moments.first(where: { moment in
                switch moment {
                case .entry(.session(let session)): return session.threadID == correction.threadID
                case .entry(.rest(let rest)): return ids.contains(rest.id) || rest.id == correction.threadID
                default: return false
                }
            }), case .entry(let entry) = match {
                let end: Date
                switch entry {
                case .session(let session): end = session.end
                case .rest(let rest): end = rest.end
                }
                let title: String
                switch correction.correction {
                case .rename: title = "Session renamed"
                case .workType(.breakTime):
                    // The row replaces the break's own entry, so it carries the name.
                    if case .rest(let rest) = entry, !rest.name.isEmpty, rest.name != "Break" {
                        title = "\(rest.name) · recorded as a break"
                    } else {
                        title = "Recorded as a break"
                    }
                case .workType(let type): title = "Changed to \(type.displayName)"
                case .removed: title = "Session removed"
                }
                notices.append(.correction(correction.id, title, DateInterval(start: entry.start, end: max(entry.start, end))))
                if case .rest = entry { moments.removeAll { $0.id == match.id } }
            }
        }
        if Calendar.current.isDate(selectedDate, inSameDayAs: now()), let range = pendingAwayRange,
           let visible = clipped(DateInterval(start: range.start, end: max(range.start, range.end))) {
            notices.append(.pending(visible))
        }
        return (moments.map(StoryTimelineItem.moment) + notices).sorted { lhs, rhs in
            if lhs.isLive != rhs.isLive { return lhs.isLive }
            return lhs.start == rhs.start ? lhs.id < rhs.id : lhs.start > rhs.start
        }
    }
}
