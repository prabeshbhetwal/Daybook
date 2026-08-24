import Foundation

/// What the automatic mode wants to do about the current session, decided
/// from a stream of `FocusScore`s. Never acted on directly — the caller owns
/// the real `SessionEngine` transition and can always refuse.
enum AutoDecision: Equatable {
    case none
    case start(workType: WorkType, name: String, backdatedTo: Date, because: String)
    case pause(because: String)
    case resume
    case end(at: Date, because: String)
}

/// Turns a stream of `FocusScore`s into start/pause/resume/end decisions.
///
/// `evaluate` fires at event boundaries — app switches, lock, unlock, wake —
/// never on a fixed tick, so nothing here may assume a regular interval
/// between calls or read the clock itself; every timestamp comes from
/// `moment`. This is deliberately the only file that decides when automatic
/// mode acts, so the flapping problem (macOS Focus turning on, then off
/// again seconds later) has exactly one place to be solved: asymmetric
/// thresholds plus minimum dwell times, both encoded in `FocusConstants`.
struct AutoSessionDetector {

    var breakLength: TimeInterval
    /// Set per evaluation from `PurposeLearner`, so the app can be slower to
    /// start for an app whose sessions the user keeps rejecting. Defaults to the
    /// shared constant until enough answers exist to move it.
    var startThreshold = FocusConstants.autoStartThreshold

    /// When the current qualifying run toward auto-start began. Any
    /// evaluation below `autoStartThreshold` clears this — the run must be
    /// unbroken, not merely frequent.
    private var qualifyingRunStart: Date?

    /// The real moment the session we auto-started actually began, i.e. when
    /// `.start` was returned — not the backdated time credited in the
    /// decision. `autoMinRunDwell` is measured from here: a session backdated
    /// five minutes into the past must still survive its first three minutes
    /// of *real* time before it can be paused, or the backdating would let a
    /// single bad evaluation undo a session that only just appeared.
    private var autoStartedAt: Date?

    /// Whether the session we auto-started is currently in our own pause,
    /// as opposed to genuinely ended.
    private var isPaused = false

    /// When the current pause began. `.end` reports this moment, not `now`,
    /// so the idle tail sitting inside the break allowance is never counted
    /// as work.
    private var pauseStartedAt: Date?

    /// No automatic start before this moment. Set when the user rejects one:
    /// the conditions that justified it are still true a second later, so
    /// without this the same session reappears and the "no" means nothing.
    private var suppressedUntil: Date?

    init(breakLength: TimeInterval) {
        self.breakLength = breakLength
    }

    mutating func reset() {
        qualifyingRunStart = nil
        suppressedUntil = nil
        clearRunningState()
    }

    /// Refuses to start anything until `moment`. Used when the user undoes an
    /// automatic session.
    mutating func suppressStarts(until moment: Date) {
        suppressedUntil = moment
        qualifyingRunStart = nil
    }

    mutating func evaluate(score: FocusScore, at moment: Date,
                           sessionRunning: Bool,
                           sessionWasAutoStarted: Bool,
                           enginePaused: Bool) -> AutoDecision {
        guard sessionRunning else {
            // Nothing open right now, so any pause/end bookkeeping left over
            // from a prior auto session is stale — the engine already
            // considers that session over.
            clearRunningState()
            return evaluateForStart(score: score, at: moment)
        }

        // Rule 1: the app may guess about its own guesses, never about a
        // deliberate act. A hand-started session is never paused or ended.
        guard sessionWasAutoStarted else {
            // Clearing the qualifying run matters as much as the rest: a run
            // that began before the user pressed Start would otherwise survive
            // the whole manual session and fire the instant it ends, backdated
            // across work already archived.
            qualifyingRunStart = nil
            clearRunningState()
            return .none
        }

        // The engine can leave a pause by routes this type never sees — a work
        // app activated, an override applied, the Resume button. Believing a
        // pause the engine has already left would end the session at a moment
        // work was still being done.
        if isPaused && !enginePaused {
            isPaused = false
            pauseStartedAt = nil
        }

        // A session is in progress, so the start-dwell tracker has nothing
        // to do until this one ends.
        qualifyingRunStart = nil

        guard let startedAt = autoStartedAt else {
            // We believe this session is ours but never recorded when it
            // began — state was likely reset mid-session. Anchor here so the
            // minimum-dwell rule still has something to measure from, without
            // emitting a decision this call.
            autoStartedAt = moment
            return .none
        }

        if isPaused {
            return evaluateWhilePaused(score: score, at: moment)
        }
        return evaluateWhileRunning(score: score, at: moment, startedAt: startedAt)
    }

    // MARK: - Not running: watching for a start

    private mutating func evaluateForStart(score: FocusScore, at moment: Date) -> AutoDecision {
        if let suppressedUntil {
            guard moment >= suppressedUntil else {
                qualifyingRunStart = nil
                return .none
            }
            self.suppressedUntil = nil
        }
        guard score.value >= startThreshold else {
            qualifyingRunStart = nil
            return .none
        }

        let runStart = qualifyingRunStart ?? moment
        qualifyingRunStart = runStart

        guard moment.timeIntervalSince(runStart) >= FocusConstants.autoStartDwell else {
            return .none
        }

        // The dwell qualified. Credit the session from when the run actually
        // began, not from now — the wait is banked, not thrown away.
        qualifyingRunStart = nil
        autoStartedAt = moment
        return .start(workType: Self.workType(for: score.signals.dominantPurpose),
                      name: Self.sessionName(forApp: score.signals.dominantApp,
                                             purpose: score.signals.dominantPurpose),
                      backdatedTo: runStart, because: score.explanation)
    }

    // MARK: - Running: watching for a pause

    private mutating func evaluateWhileRunning(score: FocusScore, at moment: Date,
                                               startedAt: Date) -> AutoDecision {
        // Rule 4: one trip to Slack must not undo a session that only just
        // started.
        guard moment.timeIntervalSince(startedAt) >= FocusConstants.autoMinRunDwell else {
            return .none
        }
        guard score.value <= FocusConstants.autoStopThreshold else {
            // Includes the whole hysteresis band between the two thresholds —
            // drifting through it must never read as a stop.
            return .none
        }
        isPaused = true
        pauseStartedAt = moment
        return .pause(because: score.explanation)
    }

    // MARK: - Paused: watching for a resume or a timeout into end

    private mutating func evaluateWhilePaused(score: FocusScore, at moment: Date) -> AutoDecision {
        if score.value >= startThreshold {
            isPaused = false
            pauseStartedAt = nil
            return .resume
        }

        guard let pausedAt = pauseStartedAt else {
            pauseStartedAt = moment
            return .none
        }

        guard moment.timeIntervalSince(pausedAt) > breakLength else {
            return .none
        }

        let endedAt = pausedAt
        clearRunningState()
        return .end(at: endedAt, because: score.explanation)
    }

    private mutating func clearRunningState() {
        isPaused = false
        pauseStartedAt = nil
        autoStartedAt = nil
    }

    /// `.coding`/`.design`/`.writingAI` are all forms of making something, so
    /// they collapse to the same work type; everything else maps to its
    /// closest analogue, with deep work as the fallback for purposes that
    /// don't otherwise imply a session kind.
    /// What an automatic session is called, from what the user is doing. In a
    /// browser or an AI client the tool says nothing, so the act does:
    /// "Browsing". Elsewhere the purpose names it; a purpose with nothing to
    /// say leaves the name empty and the UI shows its usual placeholder.
    static func sessionName(forApp bundleID: String?, purpose: AppPurpose) -> String {
        if PurposeMap.isAmbiguous(bundleID) { return "Browsing" }
        switch purpose {
        case .coding: return "Coding"
        case .writingAI: return "Writing & AI"
        case .design: return "Design"
        case .research: return "Reading"
        case .communication: return "Catching up"
        case .media, .utility: return ""
        }
    }

    private static func workType(for purpose: AppPurpose) -> WorkType {
        switch purpose {
        case .coding, .design, .writingAI: return .deepWork
        case .communication: return .meetings
        case .research: return .learning
        case .media, .utility: return .deepWork
        }
    }
}
