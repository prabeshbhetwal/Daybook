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
            guard seen.insert(item.id).inserted, item.seconds > 0, item.seconds <= 24 * 3_600,
                  let required = item.target.requiredKind else { return false }
            return item.kind == required
        }
        return Array(kept.prefix(maximum))
    }

    /// Whether the editor may add `item` to `items`: valid on its own and
    /// within the cap, counting the goals it cannot read.
    static func canAdd(_ item: DailyGoalItem, to items: [DailyGoalItem]) -> Bool {
        items.count < maximum && usable([item]) == [item]
            && !items.contains { $0.id == item.id || $0.target == item.target }
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

    /// The goals a category's own goal field held before the list was used,
    /// in catalogue order, as target goals. A category that already has a goal
    /// in `existing` is left to it, so running this twice, or after a restore
    /// from a backup that predates the list, never doubles a goal.
    static func migrated(from definitions: [WorkTypeDefinition],
                         into existing: [DailyGoalItem]) -> [DailyGoalItem] {
        var items = existing
        for definition in definitions {
            guard let seconds = definition.dailyGoal, seconds > 0,
                  definition.workType.countsAsFocus,
                  !items.contains(where: { $0.target == .category(definition.id) }) else { continue }
            let item = DailyGoalItem(target: .category(definition.id), kind: .target, seconds: seconds)
            guard canAdd(item, to: items) else { break }
            items.append(item)
        }
        return items
    }

    /// Whether a category's own goal is still waiting to move: it has one, and
    /// the list holds no goal for it.
    static func hasUnmoved(_ definitions: [WorkTypeDefinition], in items: [DailyGoalItem]) -> Bool {
        definitions.contains { definition in
            (definition.dailyGoal ?? 0) > 0 && definition.workType.countsAsFocus
                && !items.contains { $0.target == .category(definition.id) }
        }
    }

    /// Each active category target by category id, for the catalogue.
    static func categorySeconds(_ items: [DailyGoalItem]) -> [String: TimeInterval] {
        var seconds: [String: TimeInterval] = [:]
        for item in active(items) {
            if case .category(let id) = item.target, item.kind == .target, seconds[id] == nil {
                seconds[id] = item.seconds
            }
        }
        return seconds
    }

    /// Where an app limit stands, in the minutes as they are printed, so "45m
    /// of 2h limit" and "1h 15m left" always add up. A limit is never "met":
    /// it is kept, or it is over.
    struct LimitStatus: Equatable {
        let used: Int
        let limit: Int
        var isOver: Bool { used > limit }
        var remaining: Int { max(0, limit - used) }
        var excess: Int { max(0, used - limit) }
        /// "45m of 2h limit".
        var figure: String { "\(Self.text(used)) of \(Self.text(limit)) limit" }
        /// "1h 15m left", or "15m over".
        var detail: String { isOver ? "\(Self.text(excess)) over" : "\(Self.text(remaining)) left" }

        private static func text(_ minutes: Int) -> String {
            minutes == 0 ? "0m" : DurationText.precise(TimeInterval(minutes * 60))
        }
    }

    static func limitStatus(used: TimeInterval, limit: TimeInterval) -> LimitStatus {
        let minutes = { (DurationText.wholeSeconds($0) ?? 0) / 60 }
        return LimitStatus(used: minutes(used), limit: minutes(limit))
    }

    /// How an app is named when nothing better is known: the last part of its
    /// bundle id. One rule for the card and for Settings, so they never differ.
    static func fallbackAppName(_ bundleID: String) -> String {
        bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }
}
