import Foundation

/// Beats on disk: one file per local calendar day of a beat's start,
/// `beats/YYYY-MM-DD.jsonl`, a beat to a line. Evidence expires (`prune`), so
/// these files are not part of the backups; the snapshot a session keeps is.
/// `Core` only.
final class BeatArchive {
    private let directory: URL
    /// Gregorian in the given calendar's zone: day names then read the same under any user calendar.
    private let calendar: Calendar
    private var cache: [String: [Beat]] = [:]
    /// When each cached day was last used, to drop the least recent: reading old sessions must not
    /// keep every day decoded for the life of the app.
    private var lastUse: [String: Int] = [:]
    private var uses = 0
    /// Days kept decoded at once. Appending reads today's file, and a day read again costs one decode.
    static let cachedDayLimit = 8
    /// Moves whenever the beats a reader would see have changed.
    private(set) var revision = 0
    /// Directory listings and day files read from disk. A check reads it to show a pass touched none.
    private(set) var diskReads = 0
    /// Day files decoded from disk alone, which the snapshot sweep budgets.
    private(set) var dayFileReads = 0

    /// Inside the data folder, but not a part of any backup: evidence expires, history does not.
    static let folderName = "beats"

    init(directory: URL = SessionArchive.defaultDirectory.appendingPathComponent(BeatArchive.folderName),
         calendar: Calendar = .current) {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        self.directory = directory
        self.calendar = gregorian
    }

    func append(_ beat: Beat) throws {
        let name = dayName(for: beat.start)
        var day = beats(onDay: name)
        let encoder = JSONEncoder()
        try journal(name).append(encoder.encode(beat))
        day.append(beat)
        cache[name] = day
        revision += 1
    }

    /// Sorted by start then offset, each (start, offset) once: a pause or a restart inside one
    /// cell leaves two beats with the same start, and both are kept. Reads the local-day files
    /// from two days before the interval's start to two days after its end (zone offsets differ
    /// by up to 26 hours) and filters by time, so a beat filed under another zone's day after the
    /// Mac changed zone is still found.
    func beats(in interval: DateInterval) -> [Beat] {
        struct Key: Hashable { let start: Date; let offset: Int }
        let first = dayName(for: shifted(interval.start, byDays: -2))
        let last = dayName(for: shifted(interval.end, byDays: 2))
        var found: [Key: Beat] = [:]
        for name in dayNames() where name >= first && name <= last {
            for beat in beats(onDay: name) where beat.start < interval.end && beat.end > interval.start {
                found[Key(start: beat.start, offset: beat.offset)] = beat
            }
        }
        return found.values.sorted { ($0.start, $0.offset) < ($1.start, $1.offset) }
    }

    /// Whether the files kept reach back to the day of `start`: false with none, or when the oldest
    /// is a later day (a session from before it has only part of its beats, or none).
    func covers(from start: Date) -> Bool {
        dayNames().first.map { $0 <= dayName(for: start) } ?? false
    }

    var cachedDayCount: Int { cache.count }

    /// Removes day files whose day is more than `days` days before `now`'s; returns how many.
    @discardableResult
    func prune(olderThan days: Int, now: Date) -> Int {
        let keepFrom = dayName(for: shifted(now, byDays: -days))
        var removed = 0
        for name in dayNames() where name < keepFrom {
            if (try? FileManager.default.removeItem(at: fileURL(name))) != nil {
                cache[name] = nil
                lastUse[name] = nil
                removed += 1
            }
        }
        if removed > 0 { revision += 1 }
        return removed
    }

    // MARK: - Files

    private func fileURL(_ name: String) -> URL { directory.appendingPathComponent("\(name).jsonl") }
    private func journal(_ name: String) -> JournalFile { JournalFile(url: fileURL(name)) }

    /// The day files on disk, as `YYYY-MM-DD`. Ordered by name, which is by date.
    private func dayNames() -> [String] {
        diskReads += 1
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return files.compactMap { file -> String? in
            guard file.hasSuffix(".jsonl") else { return nil }
            let name = String(file.dropLast(".jsonl".count))
            let parts = name.split(separator: "-", omittingEmptySubsequences: false)
            guard name.count == 10, parts.count == 3, parts.allSatisfy({ Int($0) != nil }) else { return nil }
            return name
        }.sorted()
    }

    private func dayName(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func shifted(_ date: Date, byDays days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    /// A day file is read once. Reading also leaves the file ready for an append: a line
    /// a cut-short write left is dropped, or ended if it reads.
    private func beats(onDay name: String) -> [Beat] {
        uses += 1
        lastUse[name] = uses
        if let cached = cache[name] { return cached }
        diskReads += 1
        dayFileReads += 1
        var beats: [Beat] = []
        let journal = journal(name)
        if let contents = journal.read() {
            let replay = journal.replay(Beat.self, from: contents)
            beats = replay.changes
            if contents.lastWriteCut {
                _ = replay.skippedTornLine ? journal.dropTornLine(from: contents.data) : journal.endLastLine()
            }
        }
        cache[name] = beats
        if cache.count > Self.cachedDayLimit,
           let oldest = cache.keys.min(by: { lastUse[$0, default: 0] < lastUse[$1, default: 0] }) {
            cache[oldest] = nil
            lastUse[oldest] = nil
        }
        return beats
    }
}
