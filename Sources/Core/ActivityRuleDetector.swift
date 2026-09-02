import Foundation

enum ActivityPresence: Equatable { case present, locked, sleeping, away }

enum ActivityOwnership: Equatable {
    case none
    case manual(activityName: String, workType: WorkType)
    case automatic(ruleID: UUID, recordID: UUID)
}

struct ActivityRecordingCoverage: Equatable {
    let interval: DateInterval
}

struct ActivityRuleInput: Equatable {
    let timestamp: Date
    let foregroundBundleID: String?
    let foregroundIsActive: Bool
    let controlsAreForeground: Bool
    let foregroundGeneration: UInt64
    let presence: ActivityPresence
    let trackingEnabled: Bool
    let automationEnabled: Bool
    let ruleVersion: UInt64
    let rules: [ActivityRule]
    let ownership: ActivityOwnership
    let pendingManualState: Bool
    let recordingCoverage: DateInterval?

    static let disabled = ActivityRuleInput(timestamp: .distantPast,
        foregroundBundleID: nil, foregroundIsActive: false,
        controlsAreForeground: false, foregroundGeneration: 0, presence: .away,
        trackingEnabled: false, automationEnabled: false, ruleVersion: 0,
        rules: [], ownership: .none, pendingManualState: true,
        recordingCoverage: nil)

    func replacing(ruleVersion: UInt64? = nil,
                   presence: ActivityPresence? = nil,
                   trackingEnabled: Bool? = nil,
                   automationEnabled: Bool? = nil,
                   foregroundIsActive: Bool? = nil,
                   controlsAreForeground: Bool? = nil,
                   foregroundGeneration: UInt64? = nil,
                   pendingManualState: Bool? = nil) -> ActivityRuleInput {
        ActivityRuleInput(timestamp: timestamp, foregroundBundleID: foregroundBundleID,
            foregroundIsActive: foregroundIsActive ?? self.foregroundIsActive,
            controlsAreForeground: controlsAreForeground ?? self.controlsAreForeground,
            foregroundGeneration: foregroundGeneration ?? self.foregroundGeneration,
            presence: presence ?? self.presence,
            trackingEnabled: trackingEnabled ?? self.trackingEnabled,
            automationEnabled: automationEnabled ?? self.automationEnabled,
            ruleVersion: ruleVersion ?? self.ruleVersion,
            rules: rules, ownership: ownership,
            pendingManualState: pendingManualState ?? self.pendingManualState,
            recordingCoverage: recordingCoverage)
    }
}

struct ActivityCandidate: Equatable {
    let ruleID: UUID
    let name: String
    let workType: WorkType
}

struct ActivityQualifyingDeadline: Equatable {
    let fireAt: Date
    let qualifyingStart: Date
    let generation: UInt64
    let ruleVersion: UInt64
}

struct ActivityQuietChoice: Equatable {
    let id: UUID
    let candidates: [ActivityCandidate]
    let evidence: DateInterval
    let ruleVersion: UInt64
    let generation: UInt64
    let foregroundGeneration: UInt64
}

enum ActivityRuleResult: Equatable {
    case none
    case deadline(ActivityQualifyingDeadline)
    case start(ActivityAutomaticAction)
    case switchActivity(ActivityAutomaticAction)
    case ambiguous(ActivityQuietChoice)

    var deadline: ActivityQualifyingDeadline? {
        if case .deadline(let value) = self { return value }
        return nil
    }
    var isMutation: Bool {
        if case .start = self { return true }
        if case .switchActivity = self { return true }
        return false
    }
}

struct ActivityRuleDetector {
    private struct Run: Equatable {
        var startedAt: Date
        var candidateIDs: [UUID]
        var ruleVersion: UInt64
        var generation: UInt64
        var choiceID: UUID
        var delivered: Bool
    }

    private var run: Run?
    private var nextGeneration: UInt64 = 0
    /// The ownership the current run began under. A run's evidence is only
    /// valid for the session context it was observed in: when that context
    /// ends or changes — a Stop, a manual start, an automatic switch — the time
    /// before the change already belongs to a record, so the run must begin
    /// again rather than carry an interval into a new start.
    private var ownerKey: OwnerKey?

    private enum OwnerKey: Equatable {
        case none
        case manual
        case automatic(UUID)

        init(_ ownership: ActivityOwnership) {
            switch ownership {
            case .none: self = .none
            case .manual: self = .manual
            case .automatic(_, let recordID): self = .automatic(recordID)
            }
        }
    }

    mutating func reset() {
        if run != nil { nextGeneration &+= 1 }
        run = nil
    }

    mutating func evaluate(_ input: ActivityRuleInput) -> ActivityRuleResult {
        guard input.automationEnabled, input.trackingEnabled,
              input.foregroundIsActive, input.presence == .present,
              !input.pendingManualState,
              let bundleID = input.foregroundBundleID.flatMap(ActivityRule.normalisedBundleID),
              bundleID != ActivityRule.normalisedBundleID(FocusConstants.bundleIdentifier)
        else { reset(); return .none }

        let enabled = input.rules.filter {
            $0.isEnabled && !$0.name.isEmpty && $0.workType.countsAsFocus
                && ActivityRule.isValidStartAfter($0.startAfter)
        }
        let matches = enabled.filter { $0.bundleIDs.contains(bundleID) }
            .sorted { $0.id.uuidString < $1.id.uuidString }

        let key = OwnerKey(input.ownership)
        if let previous = ownerKey, previous != key { reset() }
        ownerKey = key

        switch input.ownership {
        case .manual:
            reset()
            return .none
        case .automatic(let ownerID, _):
            if matches.contains(where: { $0.id == ownerID }) {
                reset()
                return .none
            }
        case .none:
            break
        }

        guard !matches.isEmpty else { reset(); return .none }
        let matchedIDs = matches.map(\.id)
        var candidateIDs = matchedIDs
        var beginsNewRun = run == nil || run?.ruleVersion != input.ruleVersion
        if let existing = run, existing.ruleVersion == input.ruleVersion {
            let intersection = existing.candidateIDs.filter(Set(matchedIDs).contains)
            if existing.candidateIDs.count > 1 && matchedIDs.count == 1 {
                // Ambiguity cannot be labelled retroactively by a later unique
                // app. The exclusive boundary begins new evidence.
                beginsNewRun = true
            } else if !intersection.isEmpty {
                // Exclusive Coding followed by a shared support app retains the
                // established possibility and its original boundary.
                candidateIDs = intersection
                if candidateIDs != existing.candidateIDs {
                    run?.candidateIDs = candidateIDs
                }
            } else {
                beginsNewRun = true
            }
        }
        if beginsNewRun {
            nextGeneration &+= 1
            run = Run(startedAt: input.timestamp, candidateIDs: candidateIDs,
                      ruleVersion: input.ruleVersion, generation: nextGeneration,
                      choiceID: UUID(), delivered: false)
        }
        guard var current = run else { return .none }
        guard !current.delivered else { return .none }
        let runRules = enabled.filter { current.candidateIDs.contains($0.id) }
            .sorted { $0.id.uuidString < $1.id.uuidString }

        // A conflict qualifies only when every possible activity has reached
        // its dwell. A shorter threshold is never an implicit priority rule.
        let dwell = runRules.map(\.startAfter).max() ?? ActivityRule.defaultStartAfter
        let fireAt = current.startedAt.addingTimeInterval(dwell)
        guard input.timestamp >= fireAt else {
            return .deadline(ActivityQualifyingDeadline(
                fireAt: fireAt, qualifyingStart: current.startedAt,
                generation: current.generation, ruleVersion: current.ruleVersion))
        }

        guard let coverage = input.recordingCoverage,
              coverage.start <= current.startedAt, coverage.end >= input.timestamp else {
            reset()
            return .none
        }
        let evidence = DateInterval(start: current.startedAt, end: input.timestamp)
        current.delivered = true
        run = current
        if runRules.count > 1 {
            return .ambiguous(ActivityQuietChoice(
                id: current.choiceID,
                candidates: runRules.map { ActivityCandidate(ruleID: $0.id, name: $0.name,
                                                              workType: $0.workType) },
                evidence: evidence, ruleVersion: current.ruleVersion,
                generation: current.generation,
                foregroundGeneration: input.foregroundGeneration))
        }

        guard let rule = runRules.first else { reset(); return .none }
        let expectedRecord: UUID?
        let result: (ActivityAutomaticAction) -> ActivityRuleResult
        switch input.ownership {
        case .automatic(_, let recordID):
            expectedRecord = recordID
            result = ActivityRuleResult.switchActivity
        case .none:
            expectedRecord = nil
            result = ActivityRuleResult.start
        case .manual:
            return .none
        }
        let seconds = Int(rule.startAfter)
        let reason = "\(rule.name) after \(seconds) seconds in the assigned application"
        return result(ActivityAutomaticAction(
            ruleID: rule.id, ruleName: rule.name, workType: rule.workType,
            evidence: evidence, reason: reason, ruleVersion: current.ruleVersion,
            generation: current.generation, expectedRecordID: expectedRecord))
    }
}
