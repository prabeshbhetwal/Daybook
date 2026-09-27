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
        bundleID = Self.shared(try container.decode(String.self, forKey: .bundleID))
        appName = Self.shared(try container.decode(String.self, forKey: .appName))
        start = try container.decode(Date.self, forKey: .start)
        end = try container.decode(Date.self, forKey: .end)
        endReason = try container.decodeIfPresent(UsageEndReason.self, forKey: .endReason)
            ?? .appSwitch
    }

    /// Tens of thousands of records name a few hundred apps, and decoding gave
    /// every record its own copy of both strings: about 5 MB at 80,000 records
    /// of uncapped history. Equal strings now share one.
    private static var names: Set<String> = []
    private static let namesLock = NSLock()

    private static func shared(_ name: String) -> String {
        namesLock.lock()
        defer { namesLock.unlock() }
        return names.insert(name).memberAfterInsert
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
    /// Journal lines kept before the snapshot is rewritten. A minute's
    /// checkpoint is one line, so this bounds the journal to hours of changes
    /// while a full rewrite happens a few times a day instead of every minute.
    static let journalCompactionThreshold = 500
}

/// One authoritative in-memory view of app usage. Durable records remain
/// untouched until persistence succeeds; an overlay with the same stable UUID
/// replaces that record for every reader, while new pending UUIDs append in
/// observation order. A correction below the archive noise floor removes its
/// durable record from the view, matching what a successful checkpoint writes.
struct AppUsageSnapshot {
    private(set) var sessions: [AppUsageSession]
    let accurateFrom: Date
    let revision: Int
    /// The overlay this view was built from: each pending record's id, whether
    /// it stands in for a durable record, and the slot it landed in (nil when
    /// the view leaves it out). A later reading of the same shape — only the
    /// live record's end has moved — patches those slots instead of copying
    /// and re-hashing every durable record. Nil when ids repeat on either
    /// side, which only a full rebuild resolves exactly.
    private var overlayShape: [OverlaySlot]?

    private struct OverlaySlot {
        let id: UUID
        let replacesDurable: Bool
        let slot: Int?
    }

    /// Which stored records touch each day asked about, found once per build.
    /// History is uncapped, and today's total and goal read the view every
    /// second: scanning all of it cost about 1.3 ms a tick at 80,000 records.
    /// Shared by copies of one build; a patch changes only the live slots,
    /// which are read fresh on every call.
    private let dayIndex = DayIndex()

    private final class DayIndex {
        struct Key: Hashable { let start: Date; let end: Date }
        var days: [Key: [Int]] = [:]
    }

    init(archive: AppUsageArchive, tracker: AppUsageTracker? = nil) {
        let overlay = tracker?.usageOverlaySessions() ?? []
        let built = Self.overlay(durable: archive.sessions, with: overlay)
        self.sessions = built.sessions
        self.overlayShape = built.shape
        self.accurateFrom = archive.metadata.accurateFrom
        self.revision = archive.revision &* 1_000_003 &+ (tracker?.overlayRevision ?? 0)
    }

    /// Swaps a newer reading of the same pending records into place, giving
    /// exactly what a rebuild over the same durable records would. False, with
    /// nothing changed, when the shape differs: another id, or a record that
    /// crossed the length that decides whether it is shown.
    mutating func replaceOverlay(with pending: [AppUsageSession]) -> Bool {
        guard let shape = overlayShape, pending.count == shape.count else { return false }
        for (session, entry) in zip(pending, shape) {
            guard session.id == entry.id,
                  Self.isShown(session, replacesDurable: entry.replacesDurable)
                    == (entry.slot != nil) else { return false }
        }
        for (session, entry) in zip(pending, shape) {
            if let slot = entry.slot { sessions[slot] = session }
        }
        return true
    }

    /// A replacement must clear the archive's noise floor to stay; a record
    /// the archive has never held only needs some length.
    private static func isShown(_ session: AppUsageSession, replacesDurable: Bool) -> Bool {
        replacesDurable
            ? session.seconds >= AppUsageConstants.minimumSegment
            : session.seconds > 0
    }

    private static func overlay(durable: [AppUsageSession],
                                with pending: [AppUsageSession])
        -> (sessions: [AppUsageSession], shape: [OverlaySlot]?) {
        var latest: [UUID: AppUsageSession] = [:]
        for session in pending { latest[session.id] = session }

        let durableIDs = Set(durable.map(\.id))
        var result: [AppUsageSession] = []
        var slots: [UUID: Int] = [:]
        result.reserveCapacity(durable.count + pending.count)
        for session in durable {
            guard let replacement = latest[session.id] else {
                result.append(session)
                continue
            }
            if isShown(replacement, replacesDurable: true) {
                slots[replacement.id] = result.count
                result.append(replacement)
            }
        }

        var appended: Set<UUID> = []
        for session in pending
        where !durableIDs.contains(session.id) && !appended.contains(session.id) {
            appended.insert(session.id)
            if isShown(session, replacesDurable: false) {
                slots[session.id] = result.count
                result.append(session)
            }
        }
        guard latest.count == pending.count, durableIDs.count == durable.count else {
            return (result, nil)
        }
        let shape = pending.map {
            OverlaySlot(id: $0.id, replacesDurable: durableIDs.contains($0.id), slot: slots[$0.id])
        }
        return (result, shape)
    }

    func total(on day: Date, calendar: Calendar = .current) -> TimeInterval {
        guard let bounds = SessionRecord.dayBounds(day, calendar: calendar) else { return 0 }
        return indices(touching: bounds).reduce(0) { total, index in
            let session = sessions[index]
            let start = max(session.start, bounds.start)
            let end = min(session.end, bounds.end)
            return end > start ? total + end.timeIntervalSince(start) : total
        }
    }

    /// The records that touch a local day, in stored order: everything a
    /// reading clipped to that day can see, and nothing it would discard.
    func sessions(touching day: Date, calendar: Calendar = .current) -> [AppUsageSession] {
        guard let bounds = SessionRecord.dayBounds(day, calendar: calendar) else { return [] }
        return indices(touching: bounds).map { sessions[$0] }
    }

    /// Stored order, so a sum over them adds in exactly the order a full scan
    /// would; records it skips are ones that scan adds nothing for.
    private func indices(touching bounds: (start: Date, end: Date)) -> [Int] {
        func touches(_ index: Int) -> Bool {
            sessions[index].end > bounds.start && sessions[index].start < bounds.end
        }
        guard let shape = overlayShape else { return sessions.indices.filter(touches) }
        let live = shape.compactMap(\.slot)
        let key = DayIndex.Key(start: bounds.start, end: bounds.end)
        let stored: [Int]
        if let cached = dayIndex.days[key] {
            stored = cached
        } else {
            let liveSlots = Set(live)
            stored = sessions.indices.filter { !liveSlots.contains($0) && touches($0) }
            if dayIndex.days.count >= 8 { dayIndex.days.removeAll() }
            dayIndex.days[key] = stored
        }
        let touchingLive = live.filter(touches)
        return touchingLive.isEmpty ? stored : (stored + touchingLive).sorted()
    }
}

/// Local-only per-app usage history: a Codable snapshot plus an append-only
/// journal of the changes since it was written. Corrupt files are moved aside
/// rather than lost, and brought back once a build can read them again.
///
/// Every checkpoint used to rewrite the whole history, so a minute's heartbeat
/// on the open stretch cost the full file, and the history had to be capped to
/// keep that affordable. A change is now one journal line; the snapshot is
/// rewritten only when the journal is long, and nothing is ever dropped.
final class AppUsageArchive {

    /// The on-disk v2 shape. Keeping this private lets the archive evolve its
    /// container without exposing a persistence detail to the rest of the app.
    private struct Envelope: Codable {
        let metadata: AppUsageMetadata
        let sessions: [AppUsageSession]
    }

    /// One change since the snapshot. Replaying is idempotent, so a crash
    /// between writing the snapshot and clearing the journal loses nothing.
    private enum JournalChange: Codable {
        case upsert(AppUsageSession)
        case remove(UUID)
    }

    private let directory: URL
    private let fileURL: URL
    private let journalURL: URL
    private var journalEntries = 0
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
        self.journalURL = directory.appendingPathComponent("app-usage-journal.jsonl")
        self.now = now
        self.calendar = calendar
        self.cache = []
        self.metadata = AppUsageMetadata(accurateFrom: now())
        self.cache = load()
        guard !isReadOnly else { return }
        replayJournal()
        guard !isReadOnly else { return }
        recoverSetAsideFiles()
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
        return persistMutation(candidate, change: .upsert(session))
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
                return persistMutation(candidate, change: .remove(session.id))
            }
            guard cache[index] != session else { return true }
            var candidate = cache
            candidate[index] = session
            return persistMutation(candidate, change: .upsert(session))
        }

        // There is nothing to persist or roll back for an unsaved stretch below
        // the noise floor; treating that as success lets the tracker complete an
        // explicit idle/suspend transition without inventing a file mutation.
        guard session.seconds >= AppUsageConstants.minimumSegment else { return true }
        var candidate = cache
        candidate.append(session)
        return persistMutation(candidate, change: .upsert(session))
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

    // MARK: - Storage

    private func load() -> [AppUsageSession] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            return preserveCorruptFile(after: error)
        }

        // Both attempts' errors are kept: the v1 fallback always fails on a v2
        // file with "expected an array", which hid why the envelope failed.
        let envelopeError: Error
        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            metadata = envelope.metadata
            guard envelope.metadata.schemaVersion == 2 else {
                isReadOnly = true
                Diagnostics.log("app usage schema \(envelope.metadata.schemaVersion) is unsupported; opened read-only")
                return envelope.sessions
            }
            return envelope.sessions
        } catch {
            envelopeError = error
        }

        let legacy: [AppUsageSession]
        do {
            legacy = try JSONDecoder().decode([AppUsageSession].self, from: data)
        } catch {
            return preserveCorruptFile(after: "as v2: \(envelopeError); as v1: \(error)")
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

    private func preserveCorruptFile(after decodeError: Any) -> [AppUsageSession] {
        if let aside = UnreadableFile.setAside(fileURL, prefix: "app-usage-corrupt-",
                                               pathExtension: "json", at: now()) {
            Diagnostics.log("app usage unreadable, moved to \(aside.lastPathComponent): \(decodeError)")
        } else {
            isReadOnly = true
            Diagnostics.log("app usage unreadable and could not be preserved elsewhere; source kept read-only")
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

    /// Publishes a change only once it is durable: as one journal line while
    /// the journal is short, or as a fresh snapshot once it is long.
    @discardableResult
    private func persistMutation(_ candidate: [AppUsageSession],
                                 change: JournalChange) -> Bool {
        guard !isReadOnly else { return false }
        let durable = journalEntries + 1 < AppUsageConstants.journalCompactionThreshold
            ? appendToJournal(change)
            : compact(to: candidate)
        guard durable else { return false }
        cache = candidate
        revision += 1
        onDidChange?()
        return true
    }

    private func appendToJournal(_ change: JournalChange) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: journalURL.path) {
                guard FileManager.default.createFile(atPath: journalURL.path, contents: nil) else {
                    Diagnostics.log("failed to create the app usage journal")
                    return false
                }
            }
            var line = try JSONEncoder().encode(change)
            line.append(0x0A)
            let handle = try FileHandle(forWritingTo: journalURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            journalEntries += 1
            return true
        } catch {
            Diagnostics.log("failed to append app usage: \(error)")
            return false
        }
    }

    /// Writes the whole history as the snapshot, then clears the journal it
    /// absorbed. If clearing fails, replaying those lines again is harmless.
    private func compact(to sessions: [AppUsageSession]) -> Bool {
        guard save(sessions: sessions) else { return false }
        if (try? FileManager.default.removeItem(at: journalURL)) != nil
            || !FileManager.default.fileExists(atPath: journalURL.path) {
            journalEntries = 0
        }
        return true
    }

    /// Applies the changes written since the snapshot. A torn final line is
    /// the one write a crash can interrupt, so it alone is skipped, and then
    /// cut off: the next append would otherwise join the torn bytes and be
    /// unreadable too. An unreadable line anywhere else
    /// means the journal cannot be trusted, and it is moved aside like any
    /// other unreadable history; if that fails, nothing more is written.
    private func replayJournal() {
        guard let data = try? Data(contentsOf: journalURL) else { return }
        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        var sessions = cache
        var applied = 0
        var skippedTornLine = false
        for (offset, line) in lines.enumerated() {
            guard let change = try? JSONDecoder().decode(JournalChange.self, from: Data(line)) else {
                if offset == lines.count - 1 { skippedTornLine = true; break }
                guard let aside = UnreadableFile.setAside(journalURL, prefix: "app-usage-journal-corrupt-",
                                                          pathExtension: "jsonl", at: now()) else {
                    isReadOnly = true
                    Diagnostics.log("app usage journal unreadable at line \(offset + 1) and could not be set aside; kept read-only")
                    cache = sessions
                    return
                }
                Diagnostics.log("app usage journal unreadable at line \(offset + 1); moved to \(aside.lastPathComponent)")
                break
            }
            switch change {
            case .upsert(let session):
                if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                    sessions[index] = session
                } else {
                    sessions.append(session)
                }
            case .remove(let id):
                sessions.removeAll { $0.id == id }
            }
            applied += 1
        }
        cache = sessions
        journalEntries = lines.count
        // The next append must start on a line of its own. If the torn bytes
        // cannot be cut off, appending would bury that record in them too.
        if skippedTornLine, !dropTornLine(from: data) {
            isReadOnly = true
            Diagnostics.log("app usage journal ends in a torn line that could not be removed; kept read-only")
            return
        }
        // Starting each launch from one clean snapshot keeps the journal short.
        if applied > 0 { _ = compact(to: sessions) }
    }

    /// Truncates the journal to just before its last line.
    private func dropTornLine(from data: Data) -> Bool {
        var end = data.endIndex
        while end > data.startIndex, data[end - 1] == 0x0A { end -= 1 }
        let keep = data[..<end].lastIndex(of: 0x0A).map { $0 + 1 } ?? data.startIndex
        do {
            let handle = try FileHandle(forWritingTo: journalURL)
            defer { try? handle.close() }
            try handle.truncate(atOffset: UInt64(keep - data.startIndex))
            return true
        } catch {
            return false
        }
    }

    /// History set aside as unreadable is brought back once it reads again.
    ///
    /// This is how history went missing: a build that knew only the v1 format
    /// found a v2 file, could not read it and set it aside, and the newer build
    /// that came next started a fresh file beside it. Records are merged by id,
    /// so nothing is duplicated, and the file is renamed rather than deleted.
    /// The accuracy epoch is left alone: recovered records may predate it and
    /// are then shown as less certain, which is the honest reading.
    private func recoverSetAsideFiles() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names.sorted()
        where name.hasPrefix("app-usage-corrupt-") && name.hasSuffix(".json") {
            let url = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else { continue }
            let recovered: [AppUsageSession]
            if let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
               envelope.metadata.schemaVersion == 2 {
                recovered = envelope.sessions
            } else if let legacy = try? JSONDecoder().decode([AppUsageSession].self, from: data) {
                recovered = legacy
            } else {
                continue
            }
            let known = Set(cache.map(\.id))
            let missing = recovered.filter { !known.contains($0.id) }
            if !missing.isEmpty {
                let merged = (cache + missing).sorted {
                    ($0.start, $0.end) < ($1.start, $1.end)
                }
                guard compact(to: merged) else { return }
                cache = merged
                revision += 1
                Diagnostics.log("recovered \(missing.count) app usage records from \(name)")
            }
            let restored = directory.appendingPathComponent(
                name.replacingOccurrences(of: "app-usage-corrupt-", with: "app-usage-recovered-"))
            try? FileManager.default.moveItem(at: url, to: restored)
        }
    }
}
