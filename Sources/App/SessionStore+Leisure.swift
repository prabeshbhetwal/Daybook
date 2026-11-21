import Foundation

/// Leisure blocks (plan Phase B Task 7): with automatic mode on and no session running, a finished run of
/// watching or listening outside every session is written once to `leisure.json`, and shown on the day's
/// timeline. Nothing that totals focus, goals, streaks or breaks reads it.
extension SessionStore {
    /// How far back the heartbeat looks for a run that has just finished. shortcut: a run longer than this is
    /// kept from its last six hours; read further back if anything ever outlasts it.
    private static let leisureLookback: TimeInterval = 6 * 3_600

    var leisureStore: LeisureStore {
        if let made = activityEvidence.leisure { return made }
        let made = LeisureStore(directory: engine.archive.dataDirectoryURL, now: now())
        activityEvidence.leisure = made
        return made
    }

    /// From the heartbeat, after the beats it reads have closed.
    func recordLeisure() {
        guard activityEvidence.enabled, engine.state == .idle, engine.store.autoSessionsEnabled,
              !engine.archive.isReadOnly else { return }
        let moment = now()
        let kept = leisureStore
        // A store that cannot write is not asked every minute. A block from a clock since set back is no floor.
        guard kept.failure == nil else { return }
        let latest = kept.blocks.last { $0.end <= moment }?.end ?? .distantPast
        let from = max(latest, moment.addingTimeInterval(-Self.leisureLookback))
        guard moment > from else { return }
        let sessions = engine.archive.records.filter { $0.end > from }.map { DateInterval(start: $0.start, end: $0.end) }
        let found = LeisureFinder.blocks(beats: activityEvidence.archive.beats(in: DateInterval(start: from, end: moment)),
                                         sessions: sessions, autoModeOn: true, after: from, now: moment,
                                         purposeOverrides: engine.store.purposeOverrides)
        if let why = kept.add(found) { Diagnostics.log("Leisure: \(why)") }
    }

    /// The blocks to draw on `day`, cut to the day and clear of every session there.
    func leisureBlocks(on day: DateInterval) -> [LeisureBlock] {
        let blocks = leisureStore.blocks.filter { $0.end > day.start && $0.start < day.end }.map {
            LeisureBlock(id: $0.id, start: max($0.start, day.start), end: min($0.end, day.end), bundleID: $0.bundleID,
                         activity: $0.activity)
        }
        guard !blocks.isEmpty else { return [] }
        var sessions = engine.archive.records.filter { $0.end > day.start && $0.start < day.end }
            .map { DateInterval(start: $0.start, end: $0.end) }
        if engine.state != .idle { sessions.append(DateInterval(start: engine.sessionStartDate, end: max(engine.sessionStartDate, now()))) }
        return LeisureFinder.visible(blocks, beside: sessions)
    }

    /// The name of the app that held `block`, from the day's app use.
    func appName(of block: LeisureBlock) -> String? {
        appRanks(within: [block.interval]).first { $0.bundleID == block.bundleID }?.appName
    }
}
