import Foundation

struct StorySessionDetail {
    let apps: [AppRank]
    let text: String?
    let caption: String
    let bins: [SessionShape.Bin]
}

/// Presentation items keep confirmations in the chronology without inserting
/// artificial sessions into the evidence archive.
enum StoryTimelineItem: Identifiable {
    case moment(StoryMoment)
    case pending(DateInterval)
    case decision(AwayDecisionReceipt, DateInterval)
    case correction(String, DateInterval)

    var id: String {
        switch self {
        case .moment(let moment): return moment.id
        case .pending(let range): return "pending-\(range.start.timeIntervalSince1970)"
        case .decision(let receipt, _): return "decision-\(receipt.id.uuidString)"
        case .correction(_, let range): return "correction-\(range.start.timeIntervalSince1970)"
        }
    }

    var start: Date {
        switch self {
        case .moment(let moment): return moment.start
        case .pending(let range), .decision(_, let range), .correction(_, let range): return range.start
        }
    }

    var isLive: Bool {
        if case .moment(.entry(.session(let session))) = self { return session.isRunning }
        return false
    }
}

extension SessionStore {
    func storySessionDetail(_ session: DaySession) -> StorySessionDetail {
        let apps = appRanks(within: session.spans)
        var segments: [TimelineSegment] = []
        if let usage {
            let timeline = DashboardStats(sessions: engine.archive, usage: usage,
                usageSnapshot: effectiveUsageSnapshot).timeline(for: selectedDay)
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
        let text = SessionShape.paragraph(.init(segments: segments, workType: session.workType,
                                                stretches: session.stretches, worked: session.worked))
        let bins = session.end > session.start ? SessionShape.bins(segments: segments,
            in: DateInterval(start: session.start, end: session.end)) : []
        let coverage = bins.reduce(0) { $0 + $1.recordedSeconds }
        let missing = max(0, session.worked - coverage)
        var caption = coverage > 0 ? "\(Tokens.preciseDuration(coverage)) of recorded app-use coverage."
            : "No app-use data was recorded for this stretch."
        if missing >= 60, coverage > 0 {
            caption += " \(Tokens.duration(missing)) of logged work has no app recording."
        }
        return StorySessionDetail(apps: apps, text: text, caption: caption, bins: bins)
    }

    var storyTimelineItems: [StoryTimelineItem] {
        guard let day = Calendar.current.dateInterval(of: .day, for: selectedDay) else { return [] }
        func clipped(_ range: DateInterval) -> DateInterval? {
            let start = max(day.start, range.start), end = min(day.end, range.end)
            return end > start ? DateInterval(start: start, end: end) : nil
        }
        var moments = storyMoments
        var notices: [StoryTimelineItem] = []
        if let receipt = engine.lastAwayDecision, let range = clipped(receipt.range) {
            // The receipt is the representation of its classified interval;
            // do not repeat the same break below the green confirmation row.
            moments.removeAll {
                if case .entry(let entry) = $0 { return entry.id == receipt.insertedRecord?.id }
                return false
            }
            moments = moments.flatMap { moment -> [StoryMoment] in
                guard case .unrecorded(let gap) = moment,
                      gap.end > range.start, gap.start < range.end else { return [moment] }
                var fragments: [StoryMoment] = []
                if gap.start < range.start { fragments.append(.unrecorded(DateInterval(start: gap.start, end: range.start))) }
                if gap.end > range.end { fragments.append(.unrecorded(DateInterval(start: range.end, end: gap.end))) }
                return fragments
            }
            notices.append(.decision(receipt, range))
        } else if let correction = lastCorrection {
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
                case .workType(.breakTime): title = "Recorded as a break"
                case .workType(let type): title = "Changed to \(type.displayName)"
                }
                notices.append(.correction(title, DateInterval(start: entry.start, end: max(entry.start, end))))
                if case .rest = entry { moments.removeAll { $0.id == match.id } }
            }
        }
        if isToday, let range = pendingAwayRange,
           let visible = clipped(DateInterval(start: range.start, end: max(range.start, range.end))) {
            notices.append(.pending(visible))
        }
        return (moments.map(StoryTimelineItem.moment) + notices).sorted { lhs, rhs in
            if lhs.isLive != rhs.isLive { return lhs.isLive }
            return lhs.start == rhs.start ? lhs.id < rhs.id : lhs.start > rhs.start
        }
    }
}
