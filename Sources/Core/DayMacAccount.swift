import Foundation

/// What the Mac did across a day, told the way a gap card tells a hole: a
/// lock and its unlock are one stretch, a quit and the launch after it are
/// one, and the time the Mac was simply in use is left out. It replaces a
/// raw list where every lock came twice (screen and display) and every quit
/// came with its own "Daybook opened".
struct DayMacAccount: Equatable {
    let span: DateInterval
    let anatomy: GapAnatomy
    private let events: [MachineEvent]

    /// `span` is the day, or the day so far on today.
    init(span: DateInterval, events: [MachineEvent]) {
        self.span = span
        self.events = events.filter { $0.falls(in: span) }
        anatomy = GapAnatomy.of(span, events: events)
    }

    /// Time away from the desk, newest first as the story reads. Across a
    /// whole day, a stretch no event explains is the Mac in use.
    var rows: [GapAnatomy.Stretch] {
        anatomy.stretches.filter { $0.state != .unexplained }.reversed()
    }

    /// What the folded card says: how long the Mac was locked and asleep,
    /// then how often Daybook quit, the Mac went off, or Daybook stopped
    /// without saying so.
    var summary: String {
        var parts: [String] = []
        for (state, name) in [(GapAnatomy.State.locked, "Locked"), (.asleep, "Asleep")] {
            let seconds = rows.filter { $0.state == state }.reduce(0) { $0 + $1.span.duration }
            if seconds >= 60 { parts.append("\(name) \(DurationText.compact(seconds))") }
        }
        parts += [
            Self.phrase(events.filter { Self.quits.contains($0.kind) }, mixed: "Daybook quit"),
            Self.phrase(events.filter { Self.powerOffs.contains($0.kind) }, mixed: "Mac off"),
            Self.phrase(events.filter { GapAnatomy.found.contains($0.kind) }, mixed: "Daybook stopped unexpectedly"),
        ].compactMap { $0 }
        return parts.joined(separator: " · ")
    }

    private static let quits: Set<MachineEvent.Kind> = [
        .quit, .quitByApp, .updateRelaunch, .logOutCancelled, .restartCancelled, .shutDownCancelled,
    ]
    private static let powerOffs: Set<MachineEvent.Kind> = [
        .logOut, .restart, .shutDown, .restartOrShutDown, .powerOffUnknown,
    ]

    /// One event by its own name; several by their shared name, or `mixed`.
    private static func phrase(_ events: [MachineEvent], mixed: String) -> String? {
        guard let first = events.first else { return nil }
        guard events.count > 1 else { return first.title }
        let name = Set(events.map(\.title)).count == 1 ? first.title : mixed
        return "\(name) \(events.count) times"
    }
}
