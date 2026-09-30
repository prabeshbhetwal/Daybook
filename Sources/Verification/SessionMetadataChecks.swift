import Foundation
import SwiftUI
import AppKit
import IOKit.ps

/// Focused contracts for local record-scoped notes and observed power context.
/// Every fixture owns a complete isolated data directory; no check reads or
/// writes the live Application Support folder or samples the current Mac.
enum SessionMetadataChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Session metadata: note persists by exact stretch identity", notePersistsByRecordID),
        ("Session metadata: failed atomic note write preserves durable evidence", failedWriteIsNonMutating),
        ("Session metadata: complete data-directory copy and removal includes sidecar", directoryPortability),
        ("Session metadata: legacy record and active stretch identities are stable", stableStretchIdentity),
        ("Session metadata: legacy pending snapshots reuse their predecessor identity", pendingIdentityMigration),
        ("Session metadata: note drafts survive failed saves and guarded dismissal", draftFailureAndDismissal),
        ("Session metadata: short End removes orphan metadata while archived notes survive Undo", retentionAndCorrectionCoexistence),
        ("Session metadata: injected power monitor records boundaries and events only", injectedPowerMonitor),
        ("Session metadata: grouped notes and power retain exact stretch scope", groupedMetadataConsumers),
        ("Session metadata: Command-Return targets only the focused note editor", focusedEditorCommand),
        ("Session metadata: legacy identity ignores rename and open drafts retain evidence", identityAndDraftRetentionHardening),
        ("Session metadata: grouped power qualifies partial coverage without losing source", groupedPowerCoverageHardening),
        ("Session metadata: unique entries and equal-time observations load deterministically", duplicateMetadataHardening),
        ("Session metadata: public IOPS descriptions parse without live sampling", powerDescriptionParser),
        ("Session metadata: hardware samples use observation time without backfill", factualBoundarySampling),
        ("Session metadata: Away answer atomically reassigns post-return observations", awayObservationReassignment),
        ("Session metadata: power between sessions is kept by date and read by span", ambientPowerBetweenSessions),
        ("Resuming a pause the monitor sampled through claims no coverage gap", pauseResumeCoverage),
        ("A power tick is a sample; only a changed source or charging state is a boundary", tickBoundaryTagging),
        ("Session metadata: ambiguous duplicate sidecars fail closed byte-for-byte", duplicateSidecarsFailClosed),
        ("Session metadata: failed power transfer retries exact ownership before boundaries", failedPowerTransferRecovery),
        ("Session metadata: pending power transfers complete in identity order", orderedPowerTransferRecovery),
        ("Session metadata: cold launch restores engine before durable transfer replay", coldLaunchTransferRecovery),
        ("Session metadata: failed ordinary power writes replay exact queued evidence", failedOrdinaryPowerWriteRecovery),
        ("Session metadata: same-record observation conflicts block queue replay", sameRecordObservationConflictRecovery),
        ("Session metadata: literal battery and charging sequences stay factual", powerSummaries),
        ("Session metadata: mixed, partial and invalid power evidence stays qualified", partialPowerEvidence),
        ("Session metadata: old sessions never acquire current power", oldSessionHasNoPowerFallback)
    ]

    static func directory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("fc-session-metadata-\(UUID().uuidString)", isDirectory: true)
    }

    static func engine(at date: Date, directory: URL, suite: String) -> SessionEngine? {
        guard let defaults = UserDefaults(suiteName: suite) else { return nil }
        defaults.removePersistentDomain(forName: suite)
        return SessionEngine(store: PersistenceStore(defaults: defaults),
            archive: SessionArchive(directory: directory, now: { date }),
            ownBundleID: "com.example.metadata", schedulesDwell: false, now: { date })
    }

    final class FakePowerMonitor: PowerSourceMonitoring {
        var sample: PowerObservation
        var starts = 0
        var stops = 0
        var handler: ((PowerObservation) -> Void)?
        init(sample: PowerObservation) { self.sample = sample }
        func observation(at timestamp: Date,
                         boundary: PowerCoverageBoundary?) -> PowerObservation {
            PowerObservation(timestamp: timestamp, source: sample.source,
                percentage: sample.percentage, charging: sample.charging, boundary: boundary)
        }
        func start(_ handler: @escaping (PowerObservation) -> Void) {
            starts += 1; self.handler = handler
        }
        func stop() { stops += 1 }
    }

    static func makePowerFixture(_ clock: TestClock, folder: URL, suite: String,
                                         sample: PowerObservation) -> (SessionStore, SessionEngine,
                                            SessionMetadataArchive, FakePowerMonitor) {
        let archive = SessionArchive(directory: folder, now: { clock.value })
        let engine = SessionEngine(store: PersistenceStore(defaults: UserDefaults(suiteName: suite)!),
            archive: archive, ownBundleID: "com.example.metadata.boundary", schedulesDwell: false,
            now: { clock.value })
        let metadata = SessionMetadataArchive(directory: folder)
        let monitor = FakePowerMonitor(sample: sample)
        let store = SessionStore(engine: engine, schedulesTicker: false,
            metadataArchive: metadata, powerMonitor: monitor, now: { clock.value })
        return (store, engine, metadata, monitor)
    }
}
