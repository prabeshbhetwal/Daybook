import Foundation

/// Whether an app is working for the user, from a counter each of its
/// processes keeps climbing while it works. Two are read, with the same rule:
///
/// - `.sending`: bytes sent. Any cloud agent — Cursor, Antigravity, Gemini,
///   Copilot, Claude, Codex, one in a Chrome, Arc or Firefox tab — uploads the
///   whole conversation to its model with every step, and an upload is work
///   too. Safari's pages run in system processes no app can be told from.
/// - `.computing`: processor time. A render, an export, a build or a local AI
///   model keeps a core or more busy for minutes.
///
/// Only the counts are read, never what they carry. Measured on the author's
/// Mac, 10 October 2026: an idle Cursor window sent nothing in ten minutes
/// while working agent sessions sent 1.2–1.5 MB a minute; received bytes were
/// no use, since an idle Cursor once moved 226 KB a minute in total. Idle apps
/// used at most 0.42 of a core, and a build 1.78 cores and more. Process
/// starts and disk writes told nothing apart: an idle Cursor started 27
/// processes in two minutes.
struct WorkTraffic {
    /// Between readings.
    static let interval: TimeInterval = 20
    static let readingsKept = 3

    /// What one app must add across the readings kept to count as busy.
    let busy: UInt64
    /// A reading this small is a keep-alive, not a step of work. Two of the
    /// readings kept must pass it, so one burst — an update check — is not.
    let active: UInt64
    /// Whether a process's count passes to its parent when it exits, as
    /// processor time does. The part already seen is then taken off, or a
    /// child's whole lifetime lands in one reading: a 90-second job read as
    /// 85 CPU-seconds in twenty.
    let foldsExitedChildren: Bool

    /// 200 KB sent across a minute, 10 KB in each of two readings.
    static let sending = WorkTraffic(busy: 200 * 1_024, active: 10 * 1_024)
    /// A core busy across a minute, a quarter of one in each of two readings,
    /// in nanoseconds of processor time.
    static let computing = WorkTraffic(busy: UInt64(readingsKept) * UInt64(interval) * 1_000_000_000,
                                       active: UInt64(interval / 4) * 1_000_000_000,
                                       foldsExitedChildren: true)

    private var previous: [Int32: UInt64] = [:]
    private var previousApps: [Int32: String] = [:]
    private var previousAt: Date?
    /// Recent per-reading amounts for each counted app, newest last.
    private var history: [String: [UInt64]] = [:]
    /// When a counted app was last seen busy.
    private(set) var lastBusy: Date?

    init(busy: UInt64, active: UInt64, foldsExitedChildren: Bool = false) {
        self.busy = busy
        self.active = active
        self.foldsExitedChildren = foldsExitedChildren
    }

    /// - Parameters:
    ///   - totals: each process's counter, as it stands now.
    ///   - app: the counted app a process belongs to; nil for any other process.
    mutating func observe(totals: [Int32: UInt64], app: (Int32) -> String?, at now: Date) {
        let apps = foldsExitedChildren ? totals.keys.reduce(into: [Int32: String]()) { $0[$1] = app($1) } : [:]
        defer { previous = totals; previousApps = apps; previousAt = now }
        // The first reading, or one after typing paused the readings, has
        // nothing recent to compare with.
        guard let previousAt, now > previousAt, now.timeIntervalSince(previousAt) <= 3 * Self.interval else {
            history = [:]
            return
        }
        var added: [String: UInt64] = [:]
        // A process first seen now is skipped: its total may be hours old.
        for (pid, total) in totals {
            guard let before = previous[pid], total >= before, let app = app(pid) else { continue }
            added[app, default: 0] += total - before
        }
        if foldsExitedChildren {
            for (pid, before) in previous where totals[pid] == nil {
                guard let app = previousApps[pid], let sum = added[app] else { continue }
                added[app] = sum > before ? sum - before : 0
            }
        }
        for name in Set(history.keys).union(added.keys) {
            history[name] = Array(((history[name] ?? []) + [added[name] ?? 0]).suffix(Self.readingsKept))
        }
        history = history.filter { $0.value.contains { $0 > 0 } }
        if history.values.contains(where: isBusy) { lastBusy = now }
    }

    func isBusy(_ readings: [UInt64]) -> Bool {
        readings.reduce(0, +) >= busy && readings.filter { $0 >= active }.count >= 2
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

    /// Whether an app's work counts for the running session. Never one being
    /// watched, nor a call or media app — a call uploads and a film decodes,
    /// and an audio-only call holds the screen on for nothing — and never
    /// Daybook. Otherwise one used in the session counts; for sending, so does
    /// an untouched coding or AI app, an agent at work in another window, but
    /// not for computing, where it could be any runaway or idle-busy tool
    /// (Docker's virtual machine).
    static func counts(_ app: String, used: Set<String>, watched: Set<String>, own: String?,
                       sending: Bool) -> Bool {
        let workApp = AgentPresence.isWorkApp(app)
        guard app != own, !watched.contains(app) else { return false }
        if !workApp, [.communication, .media].contains(PurposeMap.purpose(for: app, activity: .active)) {
            return false
        }
        return used.contains(app) || (sending && workApp)
    }

    /// The apps worked in since the session began: those its own app record
    /// shows, and the one in front. Their work going on unwatched is the
    /// session's; a sync, a backup or an app never touched is not.
    static func appsUsed(_ usage: [AppUsageSession], since start: Date, frontmost: String?) -> Set<String> {
        var apps = Set(usage.filter { $0.end > start }.map(\.bundleID))
        if let frontmost { apps.insert(frontmost) }
        return apps
    }
}
