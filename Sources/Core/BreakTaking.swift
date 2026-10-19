import Foundation

/// Where a rest on record came from. Breaks the person started are told apart
/// from rests the app wrote down about an absence, so a later view can say
/// which was a decision and which was an observation.
enum BreakOrigin: String, Codable, Equatable {
    /// A break begun with Start break or Take a break, including pressing
    /// Start on a break prompt.
    case started
    /// A rest taken by leaving after a break prompt, without pressing Start.
    case prompted
    /// An absence the person answered "It was a break".
    case answered
    /// A declared away that lasted past the break threshold.
    case away
    /// A stretch behind a film or video.
    case watching
}

/// A break the person started and has not yet ended. Held by the engine and
/// saved with its snapshot, so a relaunch finds the same break with the same
/// start and planned end.
struct ActiveBreak: Codable, Equatable {
    /// Also the id of the record the break becomes, so a break that is written
    /// down twice (a relaunch between the write and the save of the state)
    /// is still one record.
    let id: UUID
    let start: Date
    var plannedEnd: Date
    var label: String?
    /// The session thread this break paused. Nil when no session was running.
    let threadID: UUID?
    /// The break-over prompt has been shown, so it is not shown again until
    /// the break is extended.
    var overNoticed: Bool

    init(id: UUID = UUID(), start: Date, plannedEnd: Date, label: String? = nil,
         threadID: UUID?, overNoticed: Bool = false) {
        self.id = id
        self.start = start
        self.plannedEnd = plannedEnd
        self.label = label
        self.threadID = threadID
        self.overNoticed = overNoticed
    }

    var plannedLength: TimeInterval { plannedEnd.timeIntervalSince(start) }

    /// Time left; negative once the planned time is up.
    func remaining(at moment: Date) -> TimeInterval { plannedEnd.timeIntervalSince(moment) }

    /// The latest a break with nobody back is recorded to: the planned end
    /// plus the same cap that ends a session nobody returns to.
    func capEnd(longAwayCap: TimeInterval) -> Date { plannedEnd.addingTimeInterval(longAwayCap) }
}

/// The break that ended last, however it ended: by the person, by input after
/// its planned end, by its cap, or by the session it paused being discarded.
/// The engine ends breaks in several places and the store hears of each from
/// this, so a rest is credited once per break and never missed.
struct EndedBreak: Equatable {
    let id: UUID
    let start: Date
    let end: Date
}

enum BreakLength {
    static let standard: TimeInterval = 300
    static let choices: [TimeInterval] = [300, 600, 900, 1_800]
    /// What "+5 min" adds.
    static let extra: TimeInterval = 300
    /// The longest a break can be planned for, however it was asked for or
    /// extended. A day is longer than any break; an unbounded length reaches
    /// infinity, which no snapshot can store.
    static let maximum: TimeInterval = 86_400
}

/// Tells work that resumed after a break from a glance at the screen. Fed one
/// call per second that had input, once the planned end has passed.
struct SustainedActivity: Equatable {
    static let window: TimeInterval = 90
    static let required = 60

    /// Whole-second marks of active seconds still inside the window, oldest first.
    private var marks: [Date] = []

    /// Returns the first active second of a window holding `required` active
    /// seconds, which is where a break's end is backdated to. Repeat calls within
    /// the same whole second count once.
    mutating func record(activeAt moment: Date) -> Date? {
        let second = Date(timeIntervalSinceReferenceDate: moment.timeIntervalSinceReferenceDate.rounded(.down))
        if !marks.contains(second) {
            marks.append(second)
        }
        let cutoff = second.addingTimeInterval(-Self.window)
        marks.removeAll { $0 < cutoff }
        guard marks.count >= Self.required else { return nil }
        return marks.first
    }

    mutating func reset() {
        marks.removeAll()
    }
}
