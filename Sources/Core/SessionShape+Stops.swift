import Foundation

/// Why a session's stretches stopped, for its "Along the way" sentence.
///
/// The tracker ends a stretch `.systemLock` at the lock screen, at sleep, when
/// the display goes dark and when Daybook quits, so the reason alone cannot
/// tell them apart. The machine event logged at that moment can. `Core` only.
extension SessionShape {

    /// Stretches that ended because input stopped or recording stopped. These
    /// are recorded reasons, not inferences about what you were doing. An
    /// event counts once, however many stops it explains. A stop from before
    /// the machine event log reads as a lock, as it always has; one since then
    /// that no event explains is not mentioned.
    static func awayClause(_ input: Input) -> String? {
        let idle = input.segments.filter { $0.endReason == .idle }.count
        var explained: [MachineEvent] = []
        var assumedLocks = 0
        for (index, stop) in input.segments.enumerated() where stop.endReason == .systemLock {
            switch stopCause(at: stop.end, resumed: resumed(after: index, input), input) {
            case .event(let event)?: if !explained.contains(event) { explained.append(event) }
            case .assumedLock?: assumedLocks += 1
            case nil: break
            }
        }
        var parts = idle > 0 ? ["input stopped \(times(idle))"] : []
        // Most telling first, one clause per subject: "the Mac slept 2 times
        // and locked once".
        var subjects: [String] = []
        var verbs: [String: [String]] = [:]
        for kind in MachineEvent.Kind.gapCauses.map(\.kind) {
            let count = explained.filter { $0.kind == kind }.count + (kind == .lock ? assumedLocks : 0)
            guard count > 0 else { continue }
            let phrase = stopPhrase(kind)
            if verbs[phrase.subject] == nil { subjects.append(phrase.subject) }
            verbs[phrase.subject, default: []].append("\(phrase.verb) \(times(count))")
        }
        parts += subjects.map { "\($0) \(listed(verbs[$0] ?? []))" }
        guard !parts.isEmpty else { return nil }
        return "Along the way \(listed(parts))."
    }

    private enum StopCause { case event(MachineEvent), assumedLock }

    /// The screen locking, or being left, after recording stopped for it.
    private static let lockKinds: Set<MachineEvent.Kind> = [.lock, .userSwitchedOut, .displaySleep]

    /// What explains a stop, from events seen live. One found only at the next
    /// launch — a crash, a power cut — is dated from the last heartbeat, which
    /// a lock just before it also set, so it never names a stop.
    /// 1. The most telling event within 2 s, the leeway
    ///    `StoryChronology.gapReason` gives: the monitor logs an event just
    ///    after the tracker stops, and a quit just before.
    /// 2. A lock after it, before recording began again. A screen saver or the
    ///    lock screen comes forward, and so stops recording, before macOS says
    ///    the screen locked, by however long the password delay is.
    /// 3. A run's ending before it, with no launch since. Once a log out,
    ///    restart or shut down is announced, Daybook can record a little more
    ///    before it quits, and the ending is dated at the announcement.
    ///
    /// Without any, a stop from before the log is taken as a lock. Since the
    /// log began a lock leaves its own event, so a stop without one was
    /// Spotlight, Control Centre or the Dock coming forward, recording turned
    /// off, or Step away: nil, and the sentence leaves it out.
    private static func stopCause(at end: Date, resumed: Date, _ input: Input) -> StopCause? {
        let live = input.machineEvents.filter { $0.latest == nil }
        func mostTelling(_ events: [MachineEvent]) -> MachineEvent? {
            MachineEvent.Kind.gapCauses.lazy.compactMap { cause in events.first { $0.kind == cause.kind } }.first
        }
        if let event = mostTelling(live.filter { abs($0.at.timeIntervalSince(end)) <= 2 })
            ?? mostTelling(live.filter { lockKinds.contains($0.kind) && $0.at > end && $0.at < resumed }) {
            return .event(event)
        }
        let lastRunEdge = live.filter {
            $0.at <= end && (MachineEvent.Kind.runEndings.contains($0.kind) || $0.kind == .daybookStarted)
        }.max { $0.at < $1.at }
        if let lastRunEdge, lastRunEdge.kind != .daybookStarted { return .event(lastRunEdge) }
        guard let loggedSince = input.eventLogStart, end >= loggedSince else { return .assumedLock }
        return nil
    }

    /// When recording began again after the stop at `index`: the session's
    /// next stretch, or for its last, just after its span ends.
    private static func resumed(after index: Int, _ input: Input) -> Date {
        let end = input.segments[index].end
        // In start order, so the first later stretch to start after the stop.
        if let next = input.segments[(index + 1)...].first(where: { $0.start >= end }) { return next.start }
        let span = input.activity.bounds.first { $0.start <= end && end <= $0.end }
        return (span?.end ?? end).addingTimeInterval(2)
    }

    /// Who stopped, and what they did. `stopCause` returns a lock, or an event
    /// of a kind named here.
    private static func stopPhrase(_ kind: MachineEvent.Kind) -> (subject: String, verb: String) {
        switch kind {
        case .systemSleep: return ("the Mac", "slept")
        case .displaySleep: return ("the display", "turned off")
        case .shutDown: return ("the Mac", "shut down")
        case .restart: return ("the Mac", "restarted")
        case .restartOrShutDown: return ("the Mac", "restarted or shut down")
        case .macOSUpdated: return ("the Mac", "updated macOS")
        case .powerOffUnknown: return ("the Mac", "powered off or logged out")
        case .logOut: return ("you", "logged out")
        case .userSwitchedOut: return ("you", "switched to another user")
        case .quit: return ("Daybook", "quit")
        case .quitByApp: return ("Daybook", "was quit by another app")
        case .logOutCancelled: return ("Daybook", "quit for a cancelled log out")
        case .restartCancelled: return ("Daybook", "quit for a cancelled restart")
        case .shutDownCancelled: return ("Daybook", "quit for a cancelled shut down")
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
