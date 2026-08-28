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

    private var lastConfirmedActive: Date?
    private var suppressingWakeReset = false
    private var lastPostWakeIdle: TimeInterval?

    mutating func noteMachineWake() {
        suppressingWakeReset = true
        lastPostWakeIdle = nil
    }

    mutating func confirm(at moment: Date) {
        lastConfirmedActive = moment
        suppressingWakeReset = false
        lastPostWakeIdle = nil
    }

    mutating func observe(rawIdleSeconds raw: TimeInterval,
                          at moment: Date,
                          displayAwake: Bool,
                          screenLocked: Bool) -> PresenceObservation {
        let idle = max(0, raw)

        guard displayAwake, !screenLocked else {
            return .quiet(seconds: quietSeconds(raw: idle, at: moment))
        }

        if suppressingWakeReset {
            guard let previous = lastPostWakeIdle else {
                lastPostWakeIdle = idle
                return .quiet(seconds: quietSeconds(raw: idle, at: moment))
            }
            guard idle < previous else {
                lastPostWakeIdle = idle
                return .quiet(seconds: quietSeconds(raw: idle, at: moment))
            }
            let since = moment.addingTimeInterval(-idle)
            confirm(at: moment)
            return .active(since: since)
        }

        guard idle < Self.activeThreshold else {
            return .quiet(seconds: quietSeconds(raw: idle, at: moment))
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
