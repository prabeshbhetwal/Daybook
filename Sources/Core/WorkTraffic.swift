import Foundation

/// Whether a coding or AI app is at work, from how many bytes it sends. Any
/// cloud agent — Cursor, Antigravity, Gemini, Copilot, Claude, Codex — uploads
/// the whole conversation to its model with every step, so this needs no setup
/// and no hook. Only byte counts are read, never what they carry.
///
/// Sent, not received: measured on the author's Mac, 10 October 2026, a
/// working Claude Code session sent 873 KB a minute and received 138 KB, while
/// an idle Cursor window moved up to 226 KB a minute in total — enough, counted
/// both ways, to read as busy. Idle agent sessions moved 1–3 KB. Process
/// starts, CPU and disk writes were measured too and rejected: an idle Cursor
/// started 27 processes and used 50 CPU-seconds in two minutes, more than an
/// agent at work.
struct WorkTraffic {
    /// Between readings.
    static let interval: TimeInterval = 20
    /// What one app must send across the readings kept to count as busy.
    static let busyBytes: UInt64 = 200 * 1_024
    /// A reading this small is a keep-alive, not a step of work. Two of the
    /// readings kept must pass it, so one burst — an update check — is not.
    static let activeBytes: UInt64 = 10 * 1_024
    static let readingsKept = 3

    private var previous: [Int32: UInt64] = [:]
    private var previousAt: Date?
    /// Recent per-reading bytes for each work app, newest last.
    private var history: [String: [UInt64]] = [:]
    /// When a work app was last seen busy.
    private(set) var lastBusy: Date?

    /// - Parameters:
    ///   - totals: bytes each process has sent since it started, as `nettop`
    ///     reports them.
    ///   - app: the work app a process belongs to; nil for any other process.
    mutating func observe(totals: [Int32: UInt64], app: (Int32) -> String?, at now: Date) {
        defer { previous = totals; previousAt = now }
        // The first reading, or one after typing paused the readings, has
        // nothing recent to compare with.
        guard let previousAt, now > previousAt, now.timeIntervalSince(previousAt) <= 3 * Self.interval else {
            history = [:]
            return
        }
        var moved: [String: UInt64] = [:]
        // A process first seen now is skipped: its total may be hours old.
        for (pid, total) in totals {
            guard let before = previous[pid], total >= before, let app = app(pid) else { continue }
            moved[app, default: 0] += total - before
        }
        for name in Set(history.keys).union(moved.keys) {
            history[name] = Array(((history[name] ?? []) + [moved[name] ?? 0]).suffix(Self.readingsKept))
        }
        history = history.filter { $0.value.contains { $0 > 0 } }
        if history.values.contains(where: Self.isBusy) { lastBusy = now }
    }

    static func isBusy(_ readings: [UInt64]) -> Bool {
        readings.reduce(0, +) >= busyBytes && readings.filter { $0 >= activeBytes }.count >= 2
    }

    /// `nettop -P -L 1 -x -J bytes_out` output: a header, then one
    /// `name.pid,bytes,` row per process. A name may itself contain dots.
    static func totals(fromNettop csv: String) -> [Int32: UInt64] {
        var totals: [Int32: UInt64] = [:]
        for line in csv.split(separator: "\n").dropFirst() {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 2, let dot = fields[0].lastIndex(of: "."),
                  let pid = Int32(fields[0][fields[0].index(after: dot)...]),
                  let sent = UInt64(fields[1]) else { continue }
            totals[pid] = sent
        }
        return totals
    }
}
