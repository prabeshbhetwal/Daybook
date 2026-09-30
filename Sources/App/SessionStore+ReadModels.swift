import SwiftUI
import AppKit
import Combine

extension SessionStore {
    var timelineWindow: (start: Date, end: Date)? { cachedWindow }
    var corrections: [SessionStoreCorrectionState] { engine.fieldCorrections }
    var lastCorrection: SessionStoreCorrectionState? { corrections.last }

    func publishCorrectionError(_ error: String?) { correctionError = error }
    func publishCanUndoCorrection(_ available: Bool) { canUndoCorrection = available }

    var logGrouping: LogGrouping {
        get { engine.store.logGrouping }
        set {
            engine.store.logGrouping = newValue
            objectWillChange.send()
        }
    }
    /// The first day with anything recorded, kept per evidence revision. It
    /// bounds day stepping, the date picker and History's journal, which can all
    /// be reached while the dashboard is hidden and not rebuilding, so it is
    /// derived on demand rather than left to that rebuild.
    var earliestDay: Date? {
        get {
            let revision = evidenceRevision
            if let cached = earliestDayCache, cached.revision == revision { return cached.day }
            guard let usage else { return earliestDayCache?.day }
            let day = DashboardStats(sessions: engine.archive, usage: usage,
                                     usageSnapshot: effectiveUsageSnapshot, now: now)
                .earliestRecordedDay()
            earliestDayCache = (revision, day)
            return day
        }
        set { earliestDayCache = (evidenceRevision, newValue) }
    }
    struct EvidenceRevision: Hashable {
        let day: Date
        let sessions: Int
        let usageID: ObjectIdentifier?
        let usage: Int
        let overlay: Int
        let metadata: Int

        /// True when only app use moved: the live overlay, or a checkpoint
        /// the usage archive can name the days of. Sessions, corrections
        /// and midnight change any day, so those still rebuild.
        func sameArchive(as other: EvidenceRevision) -> Bool {
            day == other.day && sessions == other.sessions && usageID == other.usageID
                && metadata == other.metadata
        }
    }
    var evidenceRevision: EvidenceRevision {
        EvidenceRevision(day: Calendar.current.startOfDay(for: now()),
                         sessions: engine.archive.revision,
                         usageID: usage.map { ObjectIdentifier($0) },
                         usage: usage?.revision ?? -1, overlay: tracker?.overlayRevision ?? -1,
                         metadata: metadataArchive.revision)
    }
    func noteDashboardReadModelRebuild(full: Bool = true) {
        dashboardReadModelGeneration &+= 1
        if full { dashboardArchiveReadModelGeneration &+= 1 }
    }
    func noteReviewReadModelRebuild() { reviewReadModelGeneration &+= 1 }
    func noteHistoryIndexRebuild() { historyIndexGeneration &+= 1 }
}
