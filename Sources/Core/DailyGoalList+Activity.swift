import Foundation

/// Limits on an activity: the purpose Daybook reads from the apps in front
/// (communication, research, media, utility). Focused purposes are aimed at,
/// not kept within, so they cannot be limited. A limit counts the same
/// whole-day app totals an app limit does, each app filed under its purpose,
/// so the card and the day's record always agree.
extension DailyGoalList {
    /// The purpose an activity limit stands for; nil for a focused purpose or
    /// a label this version cannot read.
    static func limitedPurpose(_ raw: String) -> AppPurpose? {
        AppPurpose(rawValue: raw).flatMap { $0.isFocused ? nil : $0 }
    }

    /// The purposes an activity limit can be on, in the catalogue's order.
    static let limitablePurposes = AppPurpose.allCases.filter { !$0.isFocused }

    /// Each purpose's share of the day, by raw value. An app whose purpose
    /// depends on how it is used (a browser) is left out unless the person
    /// gave it one: a whole day's total says nothing about what it was for.
    static func purposeUse(apps: [(bundleID: String, total: TimeInterval)],
                           overrides: [String: String]) -> [String: TimeInterval] {
        var use: [String: TimeInterval] = [:]
        for app in apps where !ActivityCredit.isAmbiguous(app.bundleID, overrides) {
            let purpose = PurposeMap.purpose(for: app.bundleID, activity: .active, overrides: overrides)
            use[purpose.rawValue, default: 0] += app.total
        }
        return use
    }

    /// The day's time in apps whose purpose depends on how they were used (a
    /// browser with no purpose set): it could have been any activity.
    static func unreadUse(apps: [(bundleID: String, total: TimeInterval)],
                          overrides: [String: String]) -> TimeInterval {
        apps.filter { ActivityCredit.isAmbiguous($0.bundleID, overrides) }.reduce(0) { $0 + $1.total }
    }

    /// The activity limits that count today, by id, in the person's order.
    static func activityLimits(_ items: [DailyGoalItem]) -> [(id: UUID, purpose: AppPurpose, limit: TimeInterval)] {
        active(items).compactMap { item in
            guard case .activity(let raw) = item.target, item.kind == .limit,
                  let purpose = limitedPurpose(raw) else { return nil }
            return (item.id, purpose, item.seconds)
        }
    }
}
