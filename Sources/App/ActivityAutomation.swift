import Foundation

protocol ActivityDeadlineCancellation: AnyObject { func cancel() }
protocol ActivityDeadlineScheduling {
    func schedule(at date: Date, _ action: @escaping () -> Void) -> ActivityDeadlineCancellation
}

private final class DispatchActivityDeadline: ActivityDeadlineCancellation {
    let item: DispatchWorkItem
    init(_ item: DispatchWorkItem) { self.item = item }
    func cancel() { item.cancel() }
}

struct MainActivityDeadlineScheduler: ActivityDeadlineScheduling {
    func schedule(at date: Date, _ action: @escaping () -> Void) -> ActivityDeadlineCancellation {
        let item = DispatchWorkItem(block: action)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, date.timeIntervalSinceNow),
                                      execute: item)
        return DispatchActivityDeadline(item)
    }
}

final class ActivityAutomation {
    private var detector = ActivityRuleDetector()
    private let scheduler: ActivityDeadlineScheduling
    private let inputProvider: () -> ActivityRuleInput
    private let applyResult: (ActivityRuleResult) -> Void
    private var cancellation: ActivityDeadlineCancellation?
    private var scheduledDeadline: ActivityQualifyingDeadline?
    private(set) var pendingChoice: ActivityQuietChoice?

    init(scheduler: ActivityDeadlineScheduling,
         input: @escaping () -> ActivityRuleInput,
         apply: @escaping (ActivityRuleResult) -> Void) {
        self.scheduler = scheduler
        self.inputProvider = input
        self.applyResult = apply
    }

    deinit { cancellation?.cancel() }

    func cancel() {
        cancellation?.cancel()
        cancellation = nil
        scheduledDeadline = nil
        pendingChoice = nil
        detector.reset()
    }

    func observe(_ input: ActivityRuleInput) {
        let result = detector.evaluate(input)
        switch result {
        case .deadline(let deadline):
            guard deadline != scheduledDeadline else { return }
            cancellation?.cancel()
            scheduledDeadline = deadline
            cancellation = scheduler.schedule(at: deadline.fireAt) { [weak self] in
                guard let self, self.scheduledDeadline == deadline else { return }
                self.cancellation = nil
                self.scheduledDeadline = nil
                self.consume(self.detector.evaluate(self.inputProvider()))
            }
        case .none:
            cancellation?.cancel()
            cancellation = nil
            scheduledDeadline = nil
        default:
            cancellation?.cancel()
            cancellation = nil
            scheduledDeadline = nil
            consume(result)
        }
    }

    private func consume(_ result: ActivityRuleResult) {
        if case .ambiguous(let choice) = result { pendingChoice = choice }
        if result != .none { applyResult(result) }
    }

    /// FocusContinuity's own foreground time is not evidence for either
    /// candidate. The already-observed external interval is frozen verbatim.
    func freezeChoiceForControls(at date: Date) -> ActivityQuietChoice? {
        guard let choice = pendingChoice else { return nil }
        cancellation?.cancel()
        cancellation = nil
        scheduledDeadline = nil
        let frozenEnd = min(date, choice.evidence.end)
        let frozen = ActivityQuietChoice(id: choice.id, candidates: choice.candidates,
            evidence: DateInterval(start: choice.evidence.start, end: frozenEnd),
            ruleVersion: choice.ruleVersion, generation: choice.generation,
            foregroundGeneration: choice.foregroundGeneration)
        pendingChoice = frozen
        return frozen
    }

    func choose(ruleID: UUID, using input: ActivityRuleInput) -> ActivityRuleResult? {
        guard let choice = pendingChoice,
              input.automationEnabled, input.trackingEnabled, input.presence == .present,
              !input.pendingManualState, input.ruleVersion == choice.ruleVersion,
              input.controlsAreForeground,
              input.foregroundGeneration == choice.foregroundGeneration,
              input.ownership == .none,
              choice.candidates.contains(where: { $0.ruleID == ruleID }),
              let rule = input.rules.first(where: { $0.id == ruleID && $0.isEnabled })
        else { return nil }
        let result = ActivityRuleResult.start(ActivityAutomaticAction(
            ruleID: rule.id, ruleName: rule.name, workType: rule.workType,
            evidence: choice.evidence,
            reason: "\(rule.name) chosen for the recorded application interval",
            ruleVersion: choice.ruleVersion, generation: choice.generation,
            expectedRecordID: nil))
        pendingChoice = nil
        applyResult(result)
        return result
    }
}
