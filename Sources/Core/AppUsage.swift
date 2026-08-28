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

/// Identifies the app-usage file format and when corrected usage recording
/// became authoritative. Earlier records remain visible as history, but are not
/// silently represented as having the later recording guarantees.
struct AppUsageMetadata: Codable, Equatable {
    let schemaVersion: Int
    let accurateFrom: Date

    init(schemaVersion: Int = 2, accurateFrom: Date) {
        self.schemaVersion = schemaVersion
        self.accurateFrom = accurateFrom
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

    /// The on-disk v2 shape. Keeping this private lets the archive evolve its
    /// container without exposing a persistence detail to the rest of the app.
    private struct Envelope: Codable {
        let metadata: AppUsageMetadata
        let sessions: [AppUsageSession]
    }

    private let directory: URL
    private let fileURL: URL
    private let now: () -> Date
    private let calendar: Calendar
    private var cache: [AppUsageSession]

    private(set) var revision = 0
    private(set) var metadata: AppUsageMetadata
    private(set) var legacyBackupURL: URL?
    /// Unsupported schema or failed evidence preservation makes the archive a
    /// display-only view for this process. Existing bytes are never downgraded
    /// or overwritten after either condition.
    private(set) var isReadOnly = false
    var onDidChange: (() -> Void)?

    init(directory: URL = SessionArchive.defaultDirectory,
         calendar: Calendar = .current,
         now: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.fileURL = directory.appendingPathComponent("app-usage.json")
        self.now = now
        self.calendar = calendar
        self.cache = []
        self.metadata = AppUsageMetadata(accurateFrom: now())
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
        guard !isReadOnly,
              session.seconds >= AppUsageConstants.minimumSegment else { return false }
        var candidate = cache
        candidate.append(session)

        if candidate.count > AppUsageConstants.capacity {
            candidate.removeFirst(candidate.count - AppUsageConstants.capacity)
        }
        return persistMutation(candidate)
    }

    /// Inserts a newly observed stretch or corrects the existing stretch with
    /// the same stable UUID. A late idle observation can therefore shorten (or
    /// remove) a previously saved checkpoint without leaving a duplicate tail.
    @discardableResult
    func checkpoint(_ session: AppUsageSession) -> Bool {
        guard !isReadOnly else { return false }
        if let index = cache.firstIndex(where: { $0.id == session.id }) {
            guard session.seconds >= AppUsageConstants.minimumSegment else {
                var candidate = cache
                candidate.remove(at: index)
                return persistMutation(candidate)
            }
            guard cache[index] != session else { return true }
            var candidate = cache
            candidate[index] = session
            return persistMutation(candidate)
        }

        // There is nothing to persist or roll back for an unsaved stretch below
        // the noise floor; treating that as success lets the tracker complete an
        // explicit idle/suspend transition without inventing a file mutation.
        guard session.seconds >= AppUsageConstants.minimumSegment else { return true }
        var candidate = cache
        candidate.append(session)
        if candidate.count > AppUsageConstants.capacity {
            candidate.removeFirst(candidate.count - AppUsageConstants.capacity)
        }
        return persistMutation(candidate)
    }

    // MARK: - Queries

    /// Whether any ordinary app usage intersects `interval` before `cutoff`.
    /// `contains` stops at the first match and reads the backing cache directly,
    /// avoiding the full filtered-array allocation used by `sessions`.
    func containsUsage(in interval: DateInterval, before cutoff: Date) -> Bool {
        let upperBound = min(interval.end, cutoff)
        guard upperBound > interval.start else { return false }
        return cache.contains { session in
            !AppUsageArchive.systemProcesses.contains(session.bundleID)
                && session.end > interval.start
                && session.start < upperBound
        }
    }

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
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            return preserveCorruptFile(after: error)
        }

        if let envelope = try? JSONDecoder().decode(Envelope.self, from: data) {
            metadata = envelope.metadata
            guard envelope.metadata.schemaVersion == 2 else {
                isReadOnly = true
                Diagnostics.log("app usage schema \(envelope.metadata.schemaVersion) is unsupported; opened read-only")
                return envelope.sessions
            }
            return envelope.sessions
        }

        let legacy: [AppUsageSession]
        do {
            legacy = try JSONDecoder().decode([AppUsageSession].self, from: data)
        } catch {
            return preserveCorruptFile(after: error)
        }

        let stamp = Int(now().timeIntervalSince1970)
        let backup = directory.appendingPathComponent("app-usage-v1-backup-\(stamp).json")
        do {
            try data.write(to: backup, options: .atomic)
            legacyBackupURL = backup
        } catch {
            isReadOnly = true
            Diagnostics.log("failed to preserve legacy app usage; source kept read-only: \(error)")
            return legacy
        }

        guard save(sessions: legacy) else {
            isReadOnly = true
            Diagnostics.log("failed to migrate app usage after backup; source kept read-only")
            return legacy
        }
        return legacy
    }

    private func preserveCorruptFile(after decodeError: Error) -> [AppUsageSession] {
        let stamp = Int(now().timeIntervalSince1970)
        let aside = directory.appendingPathComponent("app-usage-corrupt-\(stamp).json")
        do {
            try FileManager.default.moveItem(at: fileURL, to: aside)
            Diagnostics.log("app usage unreadable, moved to \(aside.lastPathComponent): \(decodeError)")
        } catch {
            isReadOnly = true
            Diagnostics.log("app usage unreadable and could not be preserved elsewhere; source kept read-only: \(error)")
        }
        return []
    }

    @discardableResult
    private func save(sessions: [AppUsageSession]) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
            let envelope = Envelope(metadata: metadata, sessions: sessions)
            try JSONEncoder().encode(envelope).write(to: fileURL, options: .atomic)
            return true
        } catch {
            Diagnostics.log("failed to write app usage: \(error)")
            return false
        }
    }

    @discardableResult
    private func persistMutation(_ candidate: [AppUsageSession]) -> Bool {
        guard !isReadOnly, save(sessions: candidate) else { return false }
        cache = candidate
        revision += 1
        onDidChange?()
        return true
    }
}
