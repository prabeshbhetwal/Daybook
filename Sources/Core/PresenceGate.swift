import Foundation

/// A pure interpretation of the HID idle counter. macOS resets that counter
/// when the machine wakes, so a low value immediately after wake is not, by
/// itself, evidence that a person returned.
enum PresenceObservation {
    case active(since: Date)
    case quiet(seconds: TimeInterval)
}

struct PresenceGate {
    private static let activeThreshold: TimeInterval = 5
    /// After this much quiet, an idle timer that drops with no counted input
    /// behind it is not a person: the quiet is carried across the reset until
    /// the counters move. On 20 November 2026 the timer reset at 11:10:26 with
    /// no key, click or pointer move, hours into an absence, and was taken for
    /// a return. Short, so a timer reset every minute or so is caught too.
    private static let resetNeedsInputAfter: TimeInterval = 10

    private var lastConfirmedActive: Date?
    private var suppressingWakeReset = false
    private var lastPostWakeIdle: TimeInterval?
    /// A drop after a wake with no counted input yet: input landing between the
    /// two reads is counted on the next sample, and that confirms it.
    private var wakeDropAwaitingCount = false
    private var lastInputCount: UInt64?
    private var lastRawIdle: TimeInterval = 0
    /// Quiet carried across idle resets nobody made; nil once input is counted.
    private var carriedQuiet: TimeInterval?

    /// True between a machine wake and independent evidence that a person
    /// returned. Workspace activation notifications obey the same gate as HID
    /// resets; macOS may activate an app while nobody is present.
    var isAwaitingConfirmation: Bool { suppressingWakeReset }

    /// The quiet the latest sample reported; 0 after a person.
    private var latestQuiet: TimeInterval = 0
    /// Counted input is being read and none has come since the quiet began.
    /// An app can bring itself to the front with nobody there (an assistant
    /// finishing its task); such an activation is not a return.
    var isQuietWithoutInput: Bool { lastInputCount != nil && latestQuiet >= Self.activeThreshold }

    mutating func noteMachineWake() {
        suppressingWakeReset = true
        lastPostWakeIdle = nil
        wakeDropAwaitingCount = false
    }

    mutating func confirm(at moment: Date) {
        lastConfirmedActive = moment
        suppressingWakeReset = false
        lastPostWakeIdle = nil
        wakeDropAwaitingCount = false
        carriedQuiet = nil
        // A confirmed return starts the quiet afresh; the idle reading from
        // before it must not be carried again by the next uncounted reset.
        lastRawIdle = 0
        latestQuiet = 0
    }

    mutating func observe(rawIdleSeconds raw: TimeInterval,
                          at moment: Date,
                          displayAwake: Bool,
                          screenLocked: Bool,
                          inputCount: UInt64? = nil) -> PresenceObservation {
        let observation = read(rawIdleSeconds: raw, at: moment, displayAwake: displayAwake,
                               screenLocked: screenLocked, inputCount: inputCount)
        if case .quiet(let seconds) = observation { latestQuiet = seconds } else { latestQuiet = 0 }
        return observation
    }

    private mutating func read(rawIdleSeconds raw: TimeInterval,
                               at moment: Date,
                               displayAwake: Bool,
                               screenLocked: Bool,
                               inputCount: UInt64?) -> PresenceObservation {
        let idle = max(0, raw)
        let previousCount = lastInputCount
        if let inputCount { lastInputCount = inputCount }
        let inputMoved = inputCount == nil || previousCount == nil || inputCount != previousCount
        let before = (carriedQuiet ?? 0) + lastRawIdle
        lastRawIdle = idle
        if inputMoved {
            carriedQuiet = nil
        } else if idle + 1 < before - (carriedQuiet ?? 0), before >= Self.resetNeedsInputAfter {
            carriedQuiet = before
        }
        let quiet = (carriedQuiet ?? 0) + idle

        guard displayAwake, !screenLocked else {
            return .quiet(seconds: quietSeconds(raw: quiet, at: moment))
        }

        if suppressingWakeReset {
            guard let previous = lastPostWakeIdle else {
                lastPostWakeIdle = idle
                return .quiet(seconds: quietSeconds(raw: quiet, at: moment))
            }
            // A second drop is a person only with input behind it: a display
            // wake or an app declaring activity resets the timer with none.
            // The count may arrive one sample after the drop it explains.
            let dropped = idle < previous
            if dropped, !inputMoved { wakeDropAwaitingCount = true }
            guard inputMoved, dropped || wakeDropAwaitingCount else {
                lastPostWakeIdle = idle
                return .quiet(seconds: quietSeconds(raw: quiet, at: moment))
            }
            let since = moment.addingTimeInterval(-idle)
            confirm(at: moment)
            return .active(since: since)
        }

        guard quiet < Self.activeThreshold else {
            return .quiet(seconds: quietSeconds(raw: quiet, at: moment))
        }
        let since = moment.addingTimeInterval(-idle)
        confirm(at: moment)
        return .active(since: since)
    }

    private func quietSeconds(raw: TimeInterval, at moment: Date) -> TimeInterval {
        if let lastConfirmedActive {
            return max(raw, moment.timeIntervalSince(lastConfirmedActive))
        }
        // Without any confirmed baseline, a wake-suppressed or locked sample
        // must still stay outside the engine's under-five-second return branch.
        return max(raw, Self.activeThreshold)
    }
}
