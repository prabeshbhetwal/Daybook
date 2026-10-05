import Foundation

/// How often the app looks for a new version.
enum UpdateFrequency: Int, CaseIterable, Identifiable {
    case daily = 1
    case weekly = 7
    case fortnightly = 14
    case monthly = 30

    var id: Int { rawValue }
    var interval: TimeInterval { TimeInterval(rawValue) * 86_400 }

    var title: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .fortnightly: return "Fortnightly"
        case .monthly: return "Monthly"
        }
    }

    /// The choice closest to an interval the updater stored, so a value set
    /// some other way still shows as one of the four.
    static func nearest(to interval: TimeInterval) -> UpdateFrequency {
        allCases.min { abs($0.interval - interval) < abs($1.interval - interval) } ?? .weekly
    }
}

/// What happens when a new version is found.
enum UpdateInstallMode: String, CaseIterable, Identifiable {
    /// The release notes, with Install, Remind Me Later or Skip.
    case askFirst
    /// Downloads quietly, then installs after a countdown that can be cancelled.
    case automatic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .askFirst: return "Ask first"
        case .automatic: return "Install automatically"
        }
    }

    var detail: String {
        switch self {
        case .askFirst: return "Shows what is new, with Install, Remind Me Later or Skip This Version."
        case .automatic: return "Downloads in the background, then installs after a 30-second countdown you can cancel."
        }
    }
}
