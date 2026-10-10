import Foundation

/// Why a session's stretches stopped, for its "Along the way" sentence.
///
/// The tracker ends a stretch `.systemLock` at the lock screen, at sleep, when
/// the display goes dark and when Daybook quits, so the reason alone cannot
/// tell them apart. The machine event logged at that moment can. `Core` only.
extension SessionShape {

    /// Stretches that ended because input stopped or recording stopped. These
    /// are recorded reasons, not inferences about what you were doing. A stop
    /// no event explains — every one from before the machine event log —
    /// reads as a lock, as it always has.
    static func awayClause(_ input: Input) -> String? {
        let idle = input.segments.filter { $0.endReason == .idle }.count
        let stops = input.segments.filter { $0.endReason == .systemLock }
            .map { stopCause(at: $0.end, in: input.machineEvents) }
        var parts = idle > 0 ? ["input stopped \(times(idle))"] : []
        // Most telling first, one clause per subject: "the Mac slept 2 times
        // and locked once".
        var subjects: [String] = []
        var verbs: [String: [String]] = [:]
        for kind in MachineEvent.Kind.gapCauses.map(\.kind) {
            let count = stops.filter { $0 == kind }.count
            guard count > 0 else { continue }
            let phrase = stopPhrase(kind)
            if verbs[phrase.subject] == nil { subjects.append(phrase.subject) }
            verbs[phrase.subject, default: []].append("\(phrase.verb) \(times(count))")
        }
        parts += subjects.map { "\($0) \(listed(verbs[$0] ?? []))" }
        guard !parts.isEmpty else { return nil }
        return "Along the way \(listed(parts))."
    }

    /// The most telling event seen live within 2 s of the stop, the leeway
    /// `StoryChronology.gapReason` gives: the monitor logs an event just after
    /// the tracker stops, and a quit just before. One found only at the next
    /// launch — a crash, a power cut — is dated from the last heartbeat, which
    /// a lock just before it also set, so it never names a stop.
    private static func stopCause(at end: Date, in events: [MachineEvent]) -> MachineEvent.Kind {
        let near = events.filter { $0.latest == nil && abs($0.at.timeIntervalSince(end)) <= 2 }.map(\.kind)
        return MachineEvent.Kind.gapCauses.first { near.contains($0.kind) }?.kind ?? .lock
    }

    /// Who stopped, and what they did. `stopCause` returns a lock, or a kind
    /// named here.
    private static func stopPhrase(_ kind: MachineEvent.Kind) -> (subject: String, verb: String) {
        switch kind {
        case .systemSleep: return ("the Mac", "slept")
        case .displaySleep: return ("the display", "turned off")
        case .shutDown: return ("the Mac", "shut down")
        case .restart: return ("the Mac", "restarted")
        case .powerOffUnknown: return ("the Mac", "powered off or logged out")
        case .logOut: return ("you", "logged out")
        case .userSwitchedOut: return ("you", "switched to another user")
        case .quit: return ("Daybook", "quit")
        case .updateRelaunch: return ("Daybook", "quit to update")
        default: return ("the Mac", "locked")
        }
    }

    private static func times(_ count: Int) -> String {
        count == 1 ? "once" : "\(count) times"
    }

    /// "a", "a and b", "a, b and c". Not `ListFormatter`, whose words and
    /// commas follow the reader's region; the rest of the sentence is English.
    private static func listed(_ items: [String]) -> String {
        guard let last = items.last, items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + last
    }
}
