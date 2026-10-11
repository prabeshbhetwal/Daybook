import Foundation

/// Restarts, quits or crashes that sit back to back on the story, with no
/// session, rest or interval between them. A night of quick quits used to
/// read as a column of identical lines; together they are one card that
/// says what happened and how often. Newest first, as the story reads.
struct StoryMachineRun: Equatable {
    struct Pin: Equatable {
        let event: MachineEvent
        let resumed: Date?
    }

    let pins: [Pin]

    /// The run from the story's `.machine` moments; anything else is not a pin.
    init(moments: [StoryMoment]) {
        pins = moments.compactMap { moment in
            guard case .machine(let event, let resumed) = moment else { return nil }
            return Pin(event: event, resumed: resumed)
        }
    }

    var id: String {
        guard let newest = pins.first else { return "machines" }
        return "machines-" + StoryMoment.machine(newest.event, resumed: newest.resumed).id
    }

    var span: DateInterval? {
        guard let newest = pins.first, let oldest = pins.last else { return nil }
        return DateInterval(start: oldest.event.at, end: max(oldest.event.at, newest.event.end))
    }

    /// One event said the same way every time reads by its name and count;
    /// a mix is counted.
    var title: String {
        let titles = Set(pins.map(\.event.title))
        if titles.count == 1, let only = titles.first { return "\(only) · \(pins.count) times" }
        return "\(pins.count) Mac events"
    }

    /// The kind the rule shows: one that ended without saying so wins, as it
    /// is the one the rule flags; otherwise the newest.
    var ruleKind: MachineEvent.Kind? {
        (pins.first { GapAnatomy.found.contains($0.event.kind) } ?? pins.first)?.event.kind
    }

    /// Whether Daybook was back within the minute after every one of them.
    var allQuickReturns: Bool {
        pins.allSatisfy { pin in pin.resumed.map { pin.event.isQuickReturn(at: $0) } ?? false }
    }
}
