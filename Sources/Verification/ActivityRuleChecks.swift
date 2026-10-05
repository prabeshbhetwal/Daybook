import Foundation
import SwiftUI
import AppKit

/// Behavioural checks for the activity-rule model, pure detector and the
/// one-shot automation consumer. These fixtures contain invented bundle IDs;
/// installed applications on the build Mac are never enumerated.
enum ActivityRuleChecks {
    static let tests: [(String, () -> [String])] = [
        ("Activity rules normalise identity and validate dwell choices", modelValidation),
        ("Shared applications remain one ambiguous qualifying run", sharedAmbiguity),
        ("Candidate intersections retain exclusive context but never relabel ambiguity", membershipIntersection),
        ("Each supported dwell fires at its literal boundary", dwellBoundaries),
        ("Established and manual activity ownership wins shared support apps", ownershipPrecedence),
        ("A running automatic session is never switched by another rule", noAutomaticSwitch),
        ("Rule deadlines fire once without another app activation", oneShotDeadline),
        ("Rule callbacks fail closed after edits, absence and tracking changes", staleDeadlineSafety),
        ("A Stop mid-dwell never re-credits archived time to a new start", stopMidDwell),
        ("An automatic start refuses evidence that overlaps archived work", overlapRefusal),
        ("Quiet choices freeze external evidence and reject stale selection", quietChoiceSafety),
        ("Activity rule preferences preserve legacy, opt-in and all-off modes", preferenceModes),
        ("Automatic actions retain exact reason and identity-bound Undo", exactActionIdentity),
        ("Session consumer persists exact automatic start provenance", consumerStartAndReload),
        ("Session consumer switches atomically without duplicate time", consumerSwitchAccounting),
        ("A rule switching back continues its own thread, never an adopted or stale one", switchBackContinuesThread),
        ("Automatic switch interruption restores one authoritative owner", switchInterruptionRecovery),
        ("Failed automatic switch preserves the established owner", switchFailureSafety),
        ("Stale Undo, cooldown and manual correction preserve newer work", undoCooldownAndCorrection),
        ("All-off activation records context without starting focus", allOffActivationGate),
        ("Quiet choice renders in both compact control surfaces", quietChoiceConsumers),
        ("Rule editor validates custom dwell and owns a scrollable injected picker", editorConsumer),
        ("Installed-app discovery deduplicates injected local sources", catalogDiscovery),
        ("Run-loop discovery turns the worker's loop rather than blocking it",
         catalogRunLoopWait),
        ("Installed-app picker renders a row per published application", pickerRows)
    ]

    static let t0 = Date(timeIntervalSince1970: 2_000_000_000)
    static let codingID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    static let researchID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
    static let recordID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!

    static func rule(_ id: UUID, _ name: String, _ seconds: TimeInterval,
                             _ apps: Set<String>) -> ActivityRule {
        ActivityRule(id: id, name: name, workType: .deepWork,
                     bundleIDs: apps, isEnabled: true, startAfter: seconds)
    }

    static var rules: [ActivityRule] {
        [rule(codingID, " Coding ", 60, ["com.example.code", "com.example.shared"]),
         rule(researchID, "Research", 180, ["com.example.research", "com.example.shared"])]
    }

    static func input(at seconds: TimeInterval,
                              app: String? = "com.example.shared",
                              foreground: Bool = true,
                              presence: ActivityPresence = .present,
                              tracking: Bool = true,
                              version: UInt64 = 1,
                              ownership: ActivityOwnership = .none,
                              pending: Bool = false,
                              coverageStart: TimeInterval = 0,
                              customRules: [ActivityRule]? = nil,
                              foregroundGeneration: UInt64 = 0,
                              controlsAreForeground: Bool? = nil) -> ActivityRuleInput {
        ActivityRuleInput(timestamp: t0.addingTimeInterval(seconds),
                          foregroundBundleID: app,
                          foregroundIsActive: foreground,
                          controlsAreForeground: controlsAreForeground
                            ?? (app == FocusConstants.bundleIdentifier),
                          foregroundGeneration: foregroundGeneration,
                          presence: presence,
                          trackingEnabled: tracking,
                          automationEnabled: true,
                          ruleVersion: version,
                          rules: customRules ?? Self.rules,
                          ownership: ownership,
                          pendingManualState: pending,
                          recordingCoverage: DateInterval(
                            start: t0.addingTimeInterval(coverageStart),
                            end: t0.addingTimeInterval(seconds)))
    }

    final class TestDeadline: ActivityDeadlineCancellation {
        var isCancelled = false
        func cancel() { isCancelled = true }
    }

    final class TestScheduler: ActivityDeadlineScheduling {
        var scheduled: [(Date, TestDeadline, () -> Void)] = []
        func schedule(at date: Date, _ action: @escaping () -> Void) -> ActivityDeadlineCancellation {
            let token = TestDeadline(); scheduled.append((date, token, action)); return token
        }
        func fireLatest() { scheduled.last?.2() }
    }

    struct ConsumerContext {
        let directory: URL
        let defaults: UserDefaults
        let suiteName: String
        let persistence: PersistenceStore
        let archive: SessionArchive
        let engine: SessionEngine
        let store: SessionStore
        let clock: TestClock
    }

    static func makeConsumer(now: Date,
                                     archiveFailure: (([SessionRecord]) -> String?)? = nil,
                                     correctionFailure: (() -> String?)? = nil) -> ConsumerContext {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fc-rule-consumer-\(UUID().uuidString)", isDirectory: true)
        let suite = "com.prabesh.daybook.rule-consumer.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let persistence = PersistenceStore(defaults: defaults)
        persistence.removeAll()
        persistence.activityRules = rules
        persistence.activityRuleAutomationEnabled = true
        let clock = TestClock(now)
        let archive = SessionArchive(directory: directory, now: { clock.value },
                                     writeOverride: archiveFailure)
        let engine = SessionEngine(store: persistence, archive: archive,
            ownBundleID: "com.example.self", schedulesDwell: false,
            correctionWriteOverride: correctionFailure, now: { clock.value })
        let store = SessionStore(engine: engine, schedulesTicker: false, now: { clock.value })
        return ConsumerContext(directory: directory, defaults: defaults, suiteName: suite,
            persistence: persistence, archive: archive, engine: engine, store: store, clock: clock)
    }

    static func clean(_ context: ConsumerContext) {
        try? FileManager.default.removeItem(at: context.directory)
        context.defaults.removePersistentDomain(forName: context.suiteName)
    }

    static func action(rule ruleID: UUID, name: String, type: WorkType,
                               start: Date, end: Date, version: UInt64,
                               generation: UInt64, expected: UUID? = nil) -> ActivityAutomaticAction {
        ActivityAutomaticAction(ruleID: ruleID, ruleName: name, workType: type,
            evidence: DateInterval(start: start, end: end),
            reason: "\(name) from exact foreground evidence", ruleVersion: version,
            generation: generation, expectedRecordID: expected)
    }
}
