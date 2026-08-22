import Foundation

/// Why a stretch stopped. Grouping needs this to tell a quick detour from a real
/// break, and it costs a few bytes on a record we already write.
enum UsageEndReason: String, Codable {
    case appSwitch, idle, systemLock, stillOpen
}

/// One continuous stretch of an app being frontmost. Produced by
/// `AppUsageTracker`, never by the user. Recording keeps full fidelity: stretches
/// are never merged at write time, because grouping needs the gaps.
struct AppUsageSession: Codable, Equatable, Identifiable {
    let id: UUID
    var bundleID: String
    var appName: String
    var start: Date
    var end: Date
    var endReason: UsageEndReason

    var seconds: TimeInterval { max(0, end.timeIntervalSince(start)) }

    init(id: UUID = UUID(),
         bundleID: String,
         appName: String,
         start: Date,
         end: Date,
         endReason: UsageEndReason = .appSwitch) {
        self.id = id
        self.bundleID = bundleID
        self.appName = appName
        self.start = start
        self.end = end
        self.endReason = endReason
    }

    /// Records written before `endReason` existed must still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        bundleID = try container.decode(String.self, forKey: .bundleID)
        appName = try container.decode(String.self, forKey: .appName)
        start = try container.decode(Date.self, forKey: .start)
        end = try container.decode(Date.self, forKey: .end)
        endReason = try container.decodeIfPresent(UsageEndReason.self, forKey: .endReason)
            ?? .appSwitch
    }
}

/// A per-app rollup for the menu bar.
struct AppUsageSummary: Identifiable, Equatable {
    let bundleID: String
    let appName: String
    let totalSeconds: TimeInterval
    let longestSeconds: TimeInterval
    let recent: [AppUsageSession]      // newest first

    var id: String { bundleID }
    var lastSession: AppUsageSession? { recent.first }
}

enum AppUsageConstants {
    /// Segments shorter than this are Cmd-Tab noise, not usage.
    static let minimumSegment: TimeInterval = 5
    /// Consecutive stretches of one app closer together than this are one
    /// session — a quick detour, not a context switch.
    static let sessionGap: TimeInterval = 300
    /// Stepping away and returning to the same app inside this window is still
    /// one session, provided nothing else was used meanwhile.
    static let awayBridge: TimeInterval = 900
    /// How far back "most used" looks.
    static let summaryWindowDays = 14
    static let capacity = 20_000
}

/// Local-only per-app usage history. Same shape as `SessionArchive`: a plain
/// Codable file, atomic writes, corrupt files moved aside rather than lost.
final class AppUsageArchive {

    private let directory: URL
    private let fileURL: URL
    private let now: () -> Date
    private let calendar: Calendar
    private var cache: [AppUsageSession]

    init(directory: URL = SessionArchive.defaultDirectory,
         calendar: Calendar = .current,
         now: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.fileURL = directory.appendingPathComponent("app-usage.json")
        self.now = now
        self.calendar = calendar
        self.cache = []
        self.cache = load()
    }

    /// Processes that are the system talking to itself, never work the user
    /// did. `loginwindow` is the important one: it is frontmost for the whole
    /// time a screen is locked or asleep, so without this a night away reads as
    /// the day's busiest "app" — six hours at 80% of tracked time, measured.
    ///
    /// Idle trimming cannot catch it. Waking the Mac is itself input, so the
    /// idle timer has already reset by the time the stretch closes and only its
    /// tail is trimmed.
    static let systemProcesses: Set<String> = [
        "com.apple.loginwindow",
        "com.apple.ScreenSaver.Engine",
        "com.apple.screensaver",
        "com.apple.SecurityAgent",
        "com.apple.coreautha",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.dock",
        "com.apple.Spotlight",
        "com.apple.WindowManager"
    ]

    /// Filtered on read rather than on write, so stretches already recorded
    /// stop distorting every total without rewriting the user's history file.
    var sessions: [AppUsageSession] {
        cache.filter { !AppUsageArchive.systemProcesses.contains($0.bundleID) }
    }

    /// Appends verbatim. Merging at write time destroyed the gap evidence that
    /// `AppSessionGrouper` needs, and made the threshold impossible to retune —
    /// grouping is now done non-destructively at display time instead.
    ///
    /// Returns whether the segment was kept. `AppUsageTracker.flush` needs to
    /// know: it used to advance the open segment's start unconditionally, so two
    /// flushes closer together than `minimumSegment` silently deleted the
    /// seconds between them.
    @discardableResult
    func record(_ session: AppUsageSession) -> Bool {
        guard session.seconds >= AppUsageConstants.minimumSegment else { return false }
        cache.append(session)

        if cache.count > AppUsageConstants.capacity {
            cache.removeFirst(cache.count - AppUsageConstants.capacity)
        }
        save()
        return true
    }

    // MARK: - Queries

    /// Reads `sessions`, not `cache`. This was the one query in the app that
    /// skipped the system-process filter, and it is the one behind the popover
    /// header: on a day with six hours of `loginwindow` the menu bar said
    /// "At the Mac 7h 47m" while the dashboard, which filters, said "1h 49m".
    ///
    /// Clipped to the day rather than filed under the segment's end, so a
    /// stretch running through midnight is split the way the dashboard already
    /// splits it instead of landing wholly on the later day.
    func totalToday() -> TimeInterval {
        let start = calendar.startOfDay(for: now())
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return 0 }
        return sessions.reduce(0) { total, session in
            let low = max(session.start, start)
            let high = min(session.end, end)
            return high > low ? total + high.timeIntervalSince(low) : total
        }
    }

    func sessions(for bundleID: String, limit: Int) -> [AppUsageSession] {
        cache.filter { $0.bundleID == bundleID }
            .sorted { $0.end > $1.end }
            .prefix(limit)
            .map { $0 }
    }

    /// Most-used apps in the recent window, busiest first.
    func mostUsedApps(limit: Int, sessionsEach: Int) -> [AppUsageSummary] {
        let cutoff = now().addingTimeInterval(-Double(AppUsageConstants.summaryWindowDays) * 86_400)
        var grouped: [String: [AppUsageSession]] = [:]
        for session in cache where session.end >= cutoff {
            grouped[session.bundleID, default: []].append(session)
        }

        return grouped.values
            .compactMap { group -> AppUsageSummary? in
                guard let first = group.first else { return nil }
                let ordered = group.sorted { $0.end > $1.end }
                return AppUsageSummary(
                    bundleID: first.bundleID,
                    appName: ordered.first?.appName ?? first.appName,
                    totalSeconds: group.reduce(0) { $0 + $1.seconds },
                    longestSeconds: group.map(\.seconds).max() ?? 0,
                    recent: Array(ordered.prefix(sessionsEach)))
            }
            .sorted { $0.totalSeconds > $1.totalSeconds }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Storage

    private func load() -> [AppUsageSession] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            return try JSONDecoder().decode([AppUsageSession].self,
                                            from: Data(contentsOf: fileURL))
        } catch {
            let stamp = Int(now().timeIntervalSince1970)
            let aside = directory.appendingPathComponent("app-usage-corrupt-\(stamp).json")
            try? FileManager.default.moveItem(at: fileURL, to: aside)
            Diagnostics.log("app usage unreadable, moved to \(aside.lastPathComponent): \(error)")
            return []
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(cache).write(to: fileURL, options: .atomic)
        } catch {
            Diagnostics.log("failed to write app usage: \(error)")
        }
    }
}
