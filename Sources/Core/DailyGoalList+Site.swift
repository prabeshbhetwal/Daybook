import Foundation

/// Limits on a kind of site (video, social, shopping...). Only the kind is ever
/// known, never the site, so a limit is on a kind. None can be counted yet: the
/// site signal is off on every Mac until a probe shows it reads true
/// (`SignalGate`), and beats are only recorded during sessions, while a limit
/// counts the whole day. So a site limit is shown as not available and is never
/// judged, and a day with one can still be perfect on its other goals.
/// shortcut: no site limit is offered or counted; add both when the gate opens
/// and site kinds are read outside sessions too.
extension DailyGoalList {
    /// What a site limit says in place of a figure until it can be counted.
    static let siteLimitUnavailable = "Not available yet"

    /// "Video sites"; a kind this version does not know is shown as stored.
    static func siteGoalName(_ raw: String) -> String {
        SiteKind(rawValue: raw).map { "\($0.displayName) sites" } ?? raw
    }

    /// The site limits in the list that count today, by id and name, in the person's order.
    static func siteLimits(_ items: [DailyGoalItem]) -> [(id: UUID, name: String, limit: TimeInterval)] {
        active(items).compactMap { item in
            guard case .site(let raw) = item.target, item.kind == .limit else { return nil }
            return (item.id, siteGoalName(raw), item.seconds)
        }
    }
}
