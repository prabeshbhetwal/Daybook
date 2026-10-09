import Foundation

/// How often Daybook backs itself up without being asked.
enum BackupSchedule: String, CaseIterable, Identifiable {
    case off
    case everySixHours
    case daily
    case weekly

    static let `default` = BackupSchedule.daily

    /// How often the running app looks for a backup that has come due. A
    /// backup counts as due this much early, or each one would land up to a
    /// check later than the last and the schedule would slip.
    static let checkInterval: TimeInterval = 30 * 60

    var id: String { rawValue }

    /// Elapsed time between backups: "every day" is every 24 hours, whatever
    /// the calendar does in between.
    var interval: TimeInterval? {
        switch self {
        case .off: return nil
        case .everySixHours: return 6 * 3_600
        case .daily: return 24 * 3_600
        case .weekly: return 7 * 24 * 3_600
        }
    }

    var title: String {
        switch self {
        case .off: return "Off"
        case .everySixHours: return "Every 6 hours"
        case .daily: return "Every day"
        case .weekly: return "Every week"
        }
    }

    /// Whether an automatic backup is due. A last backup dated after `now`
    /// (the clock was put back) does not hold the next one off.
    func isDue(lastBackup: Date?, now: Date) -> Bool {
        guard let interval else { return false }
        guard let lastBackup, lastBackup <= now else { return true }
        return now.timeIntervalSince(lastBackup) >= interval - Self.checkInterval
    }

    /// When the next automatic backup comes due, or nil when it is off.
    func nextDue(after lastBackup: Date?, now: Date) -> Date? {
        guard let interval else { return nil }
        guard let lastBackup, lastBackup <= now else { return now }
        return max(now, lastBackup.addingTimeInterval(interval - Self.checkInterval))
    }
}

/// How long automatic backups are kept. Backups made with Back Up Now are
/// always kept.
enum BackupRetention: String, CaseIterable, Identifiable {
    case forever
    case oneYear
    case threeMonths
    case oneMonth
    case twoWeeks
    case oneWeek

    static let `default` = BackupRetention.forever

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forever: return "Forever"
        case .oneYear: return "For a year"
        case .threeMonths: return "For 3 months"
        case .oneMonth: return "For a month"
        case .twoWeeks: return "For 2 weeks"
        case .oneWeek: return "For a week"
        }
    }

    /// The oldest an automatic backup may be at `now`, or nil to keep all.
    func cutoff(at now: Date, calendar: Calendar) -> Date? {
        let age: DateComponents
        switch self {
        case .forever: return nil
        case .oneYear: age = DateComponents(year: -1)
        case .threeMonths: age = DateComponents(month: -3)
        case .oneMonth: age = DateComponents(month: -1)
        case .twoWeeks: age = DateComponents(day: -14)
        case .oneWeek: age = DateComponents(day: -7)
        }
        return calendar.date(byAdding: age, to: now)
    }
}

/// Where backups go: iCloud Drive, or a folder the reader chose (another
/// disk, a synced folder from another service, a network share).
enum BackupDestination: Equatable {
    case iCloudDrive
    case folder(URL)

    /// Stored as the folder's path; empty is iCloud Drive.
    init(storedPath: String) {
        self = storedPath.isEmpty ? .iCloudDrive : .folder(URL(fileURLWithPath: storedPath, isDirectory: true))
    }

    var storedPath: String {
        switch self {
        case .iCloudDrive: return ""
        case .folder(let url): return url.path
        }
    }

    /// From the path alone: asking the disk would stall on a share that has
    /// gone away, and this is read while drawing.
    var name: String {
        switch self {
        case .iCloudDrive: return "iCloud Drive"
        case .folder(let url): return url.lastPathComponent
        }
    }

    /// The same folder by path: one read back from preferences carries a
    /// trailing slash the chosen URL may not, and URLs compare as text.
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.storedPath == rhs.storedPath }
}

/// What the last backup did, kept across launches so Settings can say when
/// the last one was made and the schedule knows when the next is due.
struct BackupLog: Codable, Equatable {
    /// When the last backup that worked was made, automatic or not.
    var lastSuccess: Date?
    /// The folder it made.
    var folderPath: String?
    /// Why the latest attempt failed, cleared by the next that works.
    var failure: String?
    var failedAt: Date?
}
