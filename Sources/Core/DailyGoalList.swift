import Foundation

/// What a goal measures. A category or a kept activity label is something to
/// do; an app or a website is something to keep within. A target from a newer
/// version of the app that this one cannot read is kept as `.unknown`, so a
/// file moving between versions never loses a goal.
enum DailyGoalTarget: Codable, Hashable {
    case category(String)
    case activity(String)
    case app(String)
    case site(String)
    case unknown(kind: String, value: String)

    private enum CodingKeys: String, CodingKey { case kind, value }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        let value = try container.decode(String.self, forKey: .value)
        switch kind {
        case "category": self = .category(value)
        case "activity": self = .activity(value)
        case "app": self = .app(value)
        case "site": self = .site(value)
        default: self = .unknown(kind: kind, value: value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let (kind, value) = parts
        try container.encode(kind, forKey: .kind)
        try container.encode(value, forKey: .value)
    }

    private var parts: (String, String) {
        switch self {
        case .category(let value): return ("category", value)
        case .activity(let value): return ("activity", value)
        case .app(let value): return ("app", value)
        case .site(let value): return ("site", value)
        case .unknown(let kind, let value): return (kind, value)
        }
    }

    /// The one kind of goal this target can have: focus targets are aimed at,
    /// apps and sites are kept under. Nil for a target this version cannot read.
    var requiredKind: DailyGoalKind? {
        switch self {
        case .category, .activity: return .target
        case .app, .site: return .limit
        case .unknown: return nil
        }
    }
}

enum DailyGoalKind: Codable, Hashable {
    /// "At least": counts focus filed under the target.
    case target
    /// "At most": counts all recorded use of the target.
    case limit
    /// A kind a newer version adds: kept and written back, never counted.
    case unknown(String)

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "target": self = .target
        case "limit": self = .limit
        default: self = .unknown(raw)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .target: try container.encode("target")
        case .limit: try container.encode("limit")
        case .unknown(let raw): try container.encode(raw)
        }
    }
}

struct DailyGoalItem: Codable, Hashable, Identifiable {
    let id: UUID
    var target: DailyGoalTarget
    var kind: DailyGoalKind
    var seconds: TimeInterval
    var isPaused: Bool

    init(id: UUID = UUID(), target: DailyGoalTarget, kind: DailyGoalKind,
         seconds: TimeInterval, isPaused: Bool = false) {
        self.id = id
        self.target = target
        self.kind = kind
        self.seconds = seconds
        self.isPaused = isPaused
    }
}

/// What one goal came to on one day, written with the day so a later edit or a
/// deleted goal never changes what the day showed.
struct DailyGoalResult: Codable, Hashable {
    let goalID: UUID
    let target: DailyGoalTarget
    let kind: DailyGoalKind
    let amount: TimeInterval
    let counted: TimeInterval
    let met: Bool
}

/// The rules for the list of goals, apart from where it is kept.
///
/// What is stored is never trimmed by these rules: a read then a write must
/// give back every goal that was there, including ones this version cannot use
/// (a newer target or kind, a ninth goal). The rules decide what is used and
/// what may be added.
enum DailyGoalList {
    static let maximum = 8

    /// The goals this version may use: a goal of the wrong kind for its
    /// target, a repeated id or a nonsensical amount is left out, a goal it
    /// cannot read is left out of use but not of storage, and at most
    /// `maximum` remain.
    static func usable(_ items: [DailyGoalItem]) -> [DailyGoalItem] {
        var seen = Set<UUID>()
        let kept = items.filter { item in
            guard seen.insert(item.id).inserted, item.seconds > 0, item.seconds.isFinite,
                  let required = item.target.requiredKind else { return false }
            return item.kind == required
        }
        return Array(kept.prefix(maximum))
    }

    /// Whether the editor may add `item` to `items`: valid on its own and
    /// within the cap, counting the goals it cannot read.
    static func canAdd(_ item: DailyGoalItem, to items: [DailyGoalItem]) -> Bool {
        items.count < maximum && usable([item]) == [item] && !items.contains { $0.id == item.id }
    }

    /// The goals that count today: usable and not paused.
    static func active(_ items: [DailyGoalItem]) -> [DailyGoalItem] {
        usable(items).filter { !$0.isPaused }
    }

    /// A day's key in the results record, in the calendar the archive uses.
    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
