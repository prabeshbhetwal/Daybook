import Foundation

/// The running session as the app's story last saw it, to the minute.
struct HistoryLensRunning: Equatable {
    let thread: UUID
    let start: Date
    let minute: Int
}

/// An app's story holds while the app, the evidence and the running
/// session stay the same.
struct HistoryLensKey: Equatable {
    let bundleID: String
    let revision: SessionStore.EvidenceRevision
    let running: HistoryLensRunning?
    /// Days are midnights in the zone the lens was built in; a lens from
    /// another zone files its sessions under days the page no longer draws.
    let timeZone: TimeZone
}

extension SessionStore {
    /// App use sorted by start, built once per evidence revision.
    func historySortedUsage() -> SortedUsage {
        let revision = evidenceRevision
        if let cached = historySortedUsageCache, cached.revision == revision { return cached.usage }
        let usage = SortedUsage(effectiveUsageSnapshot?.sessions ?? [])
        historySortedUsageCache = (revision, usage)
        return usage
    }

    /// The app picked in History's app menu, when it is the only thing
    /// narrowing the page: words or a category describe sessions, and the
    /// app's use outside every session would not answer them.
    func historyAppLens() -> HistoryAppLens? {
        let filter = historyFilter
        guard let bundleID = filter.appBundleID, filter.workType == nil,
              filter.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        // The running stretch is not in the archive yet; without it, the app's
        // use in the session you are in read as use outside every session.
        var records = engine.archive.records
        var running: HistoryLensRunning?
        if let span = engine.runningSpan, engine.activeWorkType.countsAsFocus {
            running = HistoryLensRunning(thread: engine.activeThreadID, start: span.start,
                                         minute: Int(span.end.timeIntervalSinceReferenceDate / 60))
            records.append(SessionRecord(name: "", workType: engine.activeWorkType, start: span.start,
                                         end: span.end, workSeconds: span.end.timeIntervalSince(span.start),
                                         threadID: engine.activeThreadID))
        }
        let calendar = Calendar.current
        let key = HistoryLensKey(bundleID: bundleID, revision: evidenceRevision, running: running,
                                 timeZone: calendar.timeZone)
        if let cached = historyAppLensCache, cached.key == key { return cached.lens }
        let lens = HistoryAppLens.build(bundleID: bundleID, records: records,
                                        usage: historySortedUsage(), calendar: calendar,
                                        accurateFrom: effectiveUsageSnapshot?.accurateFrom)
        historyAppLensCache = (key, lens)
        return lens
    }

    /// Every app in front during the sessions a search matched, busiest
    /// first; shares are of all app use in them.
    func historySearchApps() -> [AppRank] {
        let key = SearchJournalKey(filter: historyFilter, evidence: evidenceRevision,
                                   indexGeneration: historyIndexGeneration)
        if let cached = historySearchAppsCache, cached.key == key { return cached.apps }
        let apps = searchApps()
        historySearchAppsCache = (key, apps)
        return apps
    }

    private func searchApps() -> [AppRank] {
        let ids = Set(historySearchHits(limit: .max).flatMap(\.recordIDs))
        let spans = engine.archive.records.filter { ids.contains($0.id) && $0.workType.countsAsFocus }
            .map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }
        // Each second once, as the app's own story counts it.
        let totals = historySortedUsage().uniqueUse(within: spans)
        let overall = totals.values.reduce(0) { $0 + $1.total }
        var ranks: [AppRank] = []
        for (bundleID, entry) in totals {
            ranks.append(AppRank(bundleID: bundleID, appName: entry.name, total: entry.total,
                                 share: overall > 0 ? entry.total / overall : 0, longest: entry.longest))
        }
        return ranks.sorted { $0.total == $1.total ? $0.bundleID < $1.bundleID : $0.total > $1.total }
    }
}
