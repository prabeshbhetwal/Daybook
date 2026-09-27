import Foundation

/// The tiles the rail can show, in their shipped order. Identity is stable and
/// stored, so a saved arrangement survives a release that adds or removes a
/// tile: unknown names are dropped and missing ones are appended.
enum StoryTileKind: String, CaseIterable, Codable {
    case focus, mac, apps, rhythm, streak

    var title: String {
        switch self {
        case .focus: return "Daily goal"
        case .mac: return "On this Mac"
        case .apps: return "Apps"
        case .rhythm: return "Rhythm"
        case .streak: return "Streak"
        }
    }

    /// Repairs a stored order into a complete, duplicate-free one. A stored
    /// order is a preference, not a schema, so it is never trusted verbatim.
    static func order(from raw: String) -> [StoryTileKind] {
        var seen: Set<StoryTileKind> = []
        var order: [StoryTileKind] = []
        for name in raw.split(separator: ",") {
            guard let kind = StoryTileKind(rawValue: String(name)),
                  seen.insert(kind).inserted else { continue }
            order.append(kind)
        }
        for kind in StoryTileKind.allCases where !seen.contains(kind) {
            order.append(kind)
        }
        return order
    }

    static func raw(from order: [StoryTileKind]) -> String {
        order.map(\.rawValue).joined(separator: ",")
    }

    /// Moves one tile to sit before `target`, or to the end when target is nil.
    static func moving(_ kind: StoryTileKind,
                       before target: StoryTileKind?,
                       in order: [StoryTileKind]) -> [StoryTileKind] {
        guard kind != target else { return order }
        var result = order.filter { $0 != kind }
        if let target, let index = result.firstIndex(of: target) {
            result.insert(kind, at: index)
        } else {
            result.append(kind)
        }
        return result
    }
}
