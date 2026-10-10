import Foundation

/// What happened inside a hole in the day's recording, told by the Mac's
/// events: stretches that cover the hole end to end, oldest first, and the
/// moments a reader can place on it.
///
/// A lock and its unlock are one stretch, not two rows, and the deepest state
/// wins where they overlap: a locked Mac that then sleeps reads as asleep.
/// Only events inside the hole count. Recording before it shows the Mac was
/// awake and unlocked then, so a lock seen hours earlier with no unlock after
/// it says nothing here.
struct GapAnatomy: Equatable {
    /// Lighter to darker on the track: further from the desk each step.
    enum State: Int, Equatable, Comparable {
        /// No event explains it.
        case unexplained
        /// Screen locked, display off, or another user signed in.
        case locked
        case asleep
        /// Shut down, restarted, logged out, or Daybook not running.
        case off
        /// A crash, force quit, power cut or panic found at the next launch
        /// happened somewhere in here.
        case uncertain

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    struct Stretch: Equatable {
        let state: State
        var span: DateInterval
        /// The event that put the Mac in this state; nil when unexplained.
        let cause: MachineEvent.Kind?
        /// The display's own dark time, inside a stretch locked for another
        /// reason.
        var displayOff: DateInterval?
        /// When Daybook opened and found what happened, for an uncertain one.
        var foundAt: Date?
        /// The causing event's own detail: which app quit Daybook.
        var detail: String?

        var title: String {
            guard let cause else { return "Nothing recorded" }
            if cause == .quitByApp, let detail { return "Daybook quit by \(detail)" }
            // After a crash, force quit, power cut or panic, the one thing
            // known until the next launch is that Daybook was not running:
            // the Mac may have started again long before.
            if state == .off, GapAnatomy.found.contains(cause) { return "Daybook not running" }
            return StoryGapReason.machine(cause).title
        }
    }

    let stretches: [Stretch]
    /// When the Mac or Daybook started inside the hole.
    let starts: [MachineEvent]
    /// Where one stretch gives way to the next, and each start.
    let marks: [Date]

    /// Something inside the hole is worth unfolding.
    var isExplained: Bool { stretches.contains { $0.state != .unexplained } }

    private struct Run {
        let state: State
        let cause: MachineEvent.Kind
        let span: DateInterval
        var foundAt: Date?
        var detail: String?
    }

    /// The order a locked stretch is named by when its reasons overlap.
    private static let lockNames: [MachineEvent.Kind] = [.lock, .userSwitchedOut, .displaySleep]
    private static let closers: [MachineEvent.Kind: MachineEvent.Kind] = [
        .lock: .unlock, .userSwitchedOut: .userSwitchedIn, .displaySleep: .displayWake, .systemSleep: .wake,
    ]
    static let found: Set<MachineEvent.Kind> = [.crashed, .forceQuit, .powerLost, .kernelPanic]
    /// A run's end said at the time: off until Daybook opens again.
    private static let ended = MachineEvent.Kind.runEndings.subtracting(found)
    /// The Mac or Daybook coming up inside a hole. A new macOS is dated at
    /// the boot it came back on.
    private static let startKinds: Set<MachineEvent.Kind> = [.macStarted, .daybookStarted, .macOSUpdated]

    /// The anatomy of the hole `piece` from any events; it picks the ones
    /// that fall in the hole. An away answer can split a hole: pass the whole
    /// one as `hole` so a piece after the answer still carries what came
    /// before it.
    static func of(_ piece: DateInterval, in hole: DateInterval? = nil,
                   events: [MachineEvent]) -> GapAnatomy {
        let gap = hole.map { DateInterval(start: min($0.start, piece.start), end: max($0.end, piece.end)) }
            ?? piece
        let inside = events.filter { $0.falls(in: gap) }.sorted { $0.at < $1.at }
        let runs = runs(inside, in: gap, all: events)
        var cuts = Set([gap.start, gap.end])
        for run in runs {
            cuts.insert(min(gap.end, max(gap.start, run.span.start)))
            cuts.insert(max(gap.start, min(gap.end, run.span.end)))
        }
        let sortedCuts = cuts.sorted()
        var pieces: [Stretch] = []
        for (start, end) in zip(sortedCuts, sortedCuts.dropFirst()) where end > start {
            let middle = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
            let covering = runs.filter { $0.span.start <= middle && $0.span.end > middle }
            let deepest = covering.map(\.state).max() ?? .unexplained
            let run = deepest == .locked
                ? lockNames.lazy.compactMap { kind in covering.first { $0.cause == kind } }.first
                : covering.first { $0.state == deepest }
            pieces.append(Stretch(state: deepest, span: DateInterval(start: start, end: end),
                                  cause: run?.cause, foundAt: run?.foundAt, detail: run?.detail))
        }
        var stretches = absorbingSlivers(pieces)
        for index in stretches.indices
        where stretches[index].state == .locked && stretches[index].cause != .displaySleep {
            let span = stretches[index].span
            let dark = runs.filter { $0.cause == .displaySleep && $0.span.intersects(span) }
            if let start = dark.map({ max($0.span.start, span.start) }).min(),
               let end = dark.map({ min($0.span.end, span.end) }).max(), end > start {
                stretches[index].displayOff = DateInterval(start: start, end: end)
            }
        }
        stretches = clipped(stretches, to: piece)
        let starts = inside.filter { startKinds.contains($0.kind) && $0.at > piece.start && $0.at < piece.end }
        let marks = (stretches.dropFirst().map(\.span.start) + starts.map(\.at)).sorted()
        let distinct = marks.enumerated().filter { index, mark in
            index == 0 || mark.timeIntervalSince(marks[index - 1]) >= 1
        }.map(\.element)
        return GapAnatomy(stretches: stretches, starts: starts, marks: distinct)
    }

    /// Recording resumes a few seconds after an unlock or a wake and stops a
    /// few seconds before a lock, and a lid closes a moment before the Mac
    /// sleeps. The story leaves a hole under a minute unsaid, so a stretch of
    /// nothing, or of a lock, that short joins a neighbour at least as deep,
    /// the deeper one first. A neighbour grows by at most a minute at each
    /// end, and an off stretch or a crash window never grows: each claims
    /// only its data.
    private static func absorbingSlivers(_ pieces: [Stretch]) -> [Stretch] {
        func foldable(_ stretch: Stretch) -> Bool {
            (stretch.state == .unexplained || stretch.state == .locked) && stretch.span.duration < 60
        }
        var result = merged(pieces)
        var grownStart = Array(repeating: 0.0, count: result.count)
        var grownEnd = grownStart
        var index = 0
        while index < result.count {
            let sliver = result[index]
            let length = sliver.span.duration
            func takes(_ host: Int, atEnd: Bool) -> Bool {
                guard host >= 0, host < result.count, !foldable(result[host]),
                      result[host].state != .off, result[host].state != .uncertain,
                      result[host].state >= sliver.state else { return false }
                return (atEnd ? grownEnd[host] : grownStart[host]) + length <= 60
            }
            let before = takes(index - 1, atEnd: true) ? index - 1 : nil
            let after = takes(index + 1, atEnd: false) ? index + 1 : nil
            guard foldable(sliver), let host = [before, after].compactMap({ $0 })
                .max(by: { result[$0].state < result[$1].state }) else { index += 1; continue }
            if host < index {
                result[host].span = DateInterval(start: result[host].span.start, end: sliver.span.end)
                grownEnd[host] += length
            } else {
                result[host].span = DateInterval(start: sliver.span.start, end: result[host].span.end)
                grownStart[host] += length
            }
            result.remove(at: index)
            grownStart.remove(at: index)
            grownEnd.remove(at: index)
            index = 0
        }
        return merged(result)
    }

    /// Neighbours that say the same thing are one stretch.
    private static func merged(_ stretches: [Stretch]) -> [Stretch] {
        var result: [Stretch] = []
        for stretch in stretches {
            if let last = result.last, last.state == stretch.state, last.cause == stretch.cause,
               last.foundAt == stretch.foundAt, last.detail == stretch.detail {
                result[result.count - 1].span = DateInterval(start: last.span.start, end: stretch.span.end)
            } else {
                result.append(stretch)
            }
        }
        return result
    }

    /// The stretches inside `piece`, each cut to it.
    private static func clipped(_ stretches: [Stretch], to piece: DateInterval) -> [Stretch] {
        func cut(_ span: DateInterval) -> DateInterval? {
            let start = max(span.start, piece.start), end = min(span.end, piece.end)
            return end > start ? DateInterval(start: start, end: end) : nil
        }
        return stretches.compactMap { stretch in
            guard let span = cut(stretch.span) else { return nil }
            var kept = stretch
            kept.span = span
            kept.displayOff = stretch.displayOff.flatMap(cut)
            return kept
        }
    }

    /// Each state an event puts the Mac in, from that event to whatever ends
    /// it. A Mac that shuts down, restarts or starts Daybook again is no
    /// longer locked or asleep. A closer with no opener inside the hole was
    /// opened before it: the state held from the hole's start, or from the
    /// last start inside it.
    private static func runs(_ inside: [MachineEvent], in gap: DateInterval,
                             all events: [MachineEvent]) -> [Run] {
        let boundaries = ended.union(found).union(startKinds)
        var open: [MachineEvent.Kind: Date] = [:]
        var lastBoundary = gap.start
        var runs: [Run] = []
        func close(_ opener: MachineEvent.Kind, at end: Date) {
            let start = open.removeValue(forKey: opener) ?? lastBoundary
            guard end > start else { return }
            runs.append(Run(state: opener == .systemSleep ? .asleep : .locked, cause: opener,
                            span: DateInterval(start: start, end: end)))
        }
        // A launch at the very moment a found event is known by is the one
        // that found it, so the search includes that moment.
        func resumed(from date: Date) -> Date {
            min(gap.end, inside.first { $0.kind == .daybookStarted && $0.at >= date }?.at ?? gap.end)
        }
        for event in inside {
            if closers[event.kind] != nil {
                if open[event.kind] == nil { open[event.kind] = max(gap.start, event.at) }
            } else if let opener = closers.first(where: { $0.value == event.kind })?.key {
                close(opener, at: event.at)
            }
            if boundaries.contains(event.kind) {
                for opener in Array(open.keys) { close(opener, at: event.at) }
                lastBoundary = max(gap.start, event.end)
            }
            if ended.contains(event.kind) {
                let end = resumed(from: event.at)
                if end > event.at { runs.append(Run(state: .off, cause: event.kind,
                                                    span: DateInterval(start: event.at, end: end),
                                                    detail: event.detail)) }
            }
            if found.contains(event.kind) {
                let foundAt = events.first { $0.kind == .daybookStarted && $0.at >= event.end }?.at
                if event.end > event.at {
                    runs.append(Run(state: .uncertain, cause: event.kind,
                                    span: DateInterval(start: event.at, end: event.end), foundAt: foundAt))
                }
                let end = resumed(from: event.end)
                if end > event.end { runs.append(Run(state: .off, cause: event.kind,
                                                     span: DateInterval(start: event.end, end: end))) }
            }
        }
        for opener in Array(open.keys) { close(opener, at: gap.end) }
        return runs
    }
}
