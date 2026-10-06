import SwiftUI
import AppKit
import Combine

extension SessionStore {
    /// The sole read model for live and historical consumers. Pending tracker
    /// records replace durable records by stable UUID in memory; the archive's
    /// bytes and accuracy epoch remain unchanged until a write succeeds.
    ///
    /// Built at most once a second, not once per read. It used to be rebuilt
    /// on every access — a copy and a re-hash of every usage session in the
    /// archive — and one projection of one day reads it several times, while
    /// History read it for every day it showed, every second.
    ///
    /// The archive and the tracker each count their changes, and that pair is
    /// most of the key. It cannot be all of it: the tracker's open segment is
    /// live, its end is the clock, and it grows without any revision moving.
    /// So the clock is in the key too, to the second — the finest grain any
    /// figure in the app is shown at — which keeps a live tail honest while
    /// still collapsing forty reads in one tick into one build. A new second
    /// with unchanged revisions patches the live records into the previous
    /// build rather than copying the whole archive again.
    var effectiveUsageSnapshot: AppUsageSnapshot? {
        guard let usage else { return nil }
        let revision = usage.revision &* 1_000_003 &+ (tracker?.overlayRevision ?? 0)
        let second = Int(now().timeIntervalSinceReferenceDate.rounded(.down))
        if var cached = usageSnapshotCache, cached.revision == revision,
           cached.usageID == ObjectIdentifier(usage) {
            if cached.second == second { return cached.snapshot }
            // Same records, a later second: only the live tail has moved.
            // Released from the cache first so the patch is in place.
            usageSnapshotCache = nil
            if cached.snapshot.replaceOverlay(with: tracker?.usageOverlaySessions() ?? []) {
                cached.second = second
                usageSnapshotCache = cached
                return cached.snapshot
            }
        }
        let snapshot = AppUsageSnapshot(archive: usage, tracker: tracker)
        usageSnapshotCache = (ObjectIdentifier(usage), revision, second, snapshot)
        usageSnapshotComputeCount &+= 1
        return snapshot
    }

    func focusedActiveSeconds(on day: Date,
                              usageSnapshot: AppUsageSnapshot? = nil) -> TimeInterval {
        guard let snapshot = usageSnapshot ?? effectiveUsageSnapshot else { return 0 }
        let calendar = Calendar.current
        let includesRunning = engine.state != .idle
            && calendar.isDate(day, inSameDayAs: now())
        return FocusedActiveTime.seconds(
            on: day, records: engine.archive.records, usage: snapshot.sessions,
            running: includesRunning ? engine.runningSpan : nil,
            runningWork: includesRunning ? engine.elapsedToday() : nil,
            runningPaused: includesRunning ? engine.runningPausedSpans : nil,
            calendar: calendar)
    }

    /// Attaches the background usage tracker. Optional: the focus loop works
    /// fully without it, and the gallery drives the store without one.
    func attach(tracker: AppUsageTracker, usage: AppUsageArchive) {
        self.usage?.onDidChange = nil
        self.tracker?.onDidTransition = nil
        self.tracker = tracker
        self.usage = usage
        usage.onDidChange = { [weak self, weak tracker] in
            guard let self else { return }
            if tracker?.isTransitioning == true {
                self.glanceArchiveRefreshPending = true
                self.dashboardArchiveRefreshPending = true
                self.insightsRefreshPending = true
                self.reviewLiveTailRefreshPending = true
            } else {
                self.archiveUsageDidChange()
            }
        }
        tracker.onDidTransition = { [weak self] in self?.trackerDidTransition() }
        self.isTrackingEnabled = tracker.isEnabled
        refresh()
    }

    /// Consume synchronous archive callbacks only after the tracker has reached
    /// its final lifecycle state. This keeps Running Now, the live figures and
    /// the ticker on one post-transition frame.
    private func trackerDidTransition() {
        withRefreshTransaction {
            // Set before the minute refresh: if that path rebuilds visible
            // Insights it clears this flag, avoiding a second rebuild when the
            // transaction is consumed. Same-minute mutations remain pending.
            insightsRefreshPending = true
            updateTimeDrivenFigures()
            updateTicker()
            glanceArchiveRefreshPending = true
            dashboardArchiveRefreshPending = true
            // App use alone patches the days it touched; a session change
            // already pending keeps its full rebuild.
            if reviewVisible {
                refreshReview(rebuildingHistory: reviewRefreshPending)
            } else { reviewLiveTailRefreshPending = true }
        }
    }
}
