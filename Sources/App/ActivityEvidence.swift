import Foundation
import os

/// SessionStore's activity-evidence state, held by one reference so the store gains one stored property.
final class ActivityEvidence {
    var recorder = BeatRecorder()
    let archive: BeatArchive
    let counters: InputCounters
    /// What `observeIdle()` named this second: the beat the next tick adds to is of this presence.
    var lastPresence: BeatPresence = .paused
    /// The holders it read; nil when it did not (the first minute of quiet, when nothing depends on them).
    var lastWatched: Set<String>?
    /// The local day whose first tick already pruned expired beats.
    var lastPruneDay: Date?
    /// Beats are being recorded: the recorder was told the app in front when this turned on, and is
    /// ended once when it turns off (a session stops, "Record app use" goes off, the app quits).
    var recording = false
    /// Off, nothing is recorded or read. A check runs one script both ways to show recording changes
    /// nothing the session counts; the app never turns it off.
    var enabled = true
    /// What each session row's phases were last worked out from (`sessionActivity(for:)`).
    var memo: [SessionActivityMemoKey: SessionActivityMemo] = [:]
    /// What each row that is not running last read, and under which stamp.
    var stamped: [SessionActivityMemoKey: (stamp: SessionActivityStamp, shape: SessionActivityShape?)] = [:]
    /// Records the snapshot sweep has nothing to do for as they stand, so it does not look again.
    var settled: [UUID: SettledRecord] = [:]
    /// The session archive's revision when `refresh()` last wrote summaries after a stop.
    var sweptRevision = -1
    /// Asks which kind of site a confirmed browser's front tab shows; nil until the app builds one,
    /// so a store without one reads nothing.
    var siteReader: SiteSignalReader?
    /// The process of the app in front when it is the app named; nil reads nothing.
    var frontPID: (String) -> pid_t? = { _ in nil }
    /// The records already judged for an automatic split; nil until the first pass of a launch notes what is
    /// there, so nothing recorded before is ever split behind the person's back.
    var splitSeen: Set<UUID>?
    /// Automatic sessions whose own split was refused: the person is offered the cut instead (until a relaunch).
    var splitRefused: Set<UUID> = []
    /// Told of every session that ends, to ask the on-device model about it (Phase C); nil asks nothing.
    var categoryAssistant: CategoryAssistant?
    /// Its label file, for the person's answers to what it said (Keep, Merge Into, Remove, the tally).
    var aiLabels: AILabelStore?
    /// The records it has been told of or that were there when the app opened, so none is asked about twice
    /// and none from before the launch is asked about at all; nil until the first sweep of a launch.
    var assistantSeen: Set<UUID>?
    /// When that first sweep ran: a record that ended before it is never asked about, whatever id a split, a
    /// merge or an Undo has since given it (C4).
    var assistantSince: Date?
    /// `leisure.json`, read on first use (`SessionStore.leisureStore`).
    var leisure: LeisureStore?

    init(archive: BeatArchive = BeatArchive(), counters: InputCounters = InputCounters()) {
        self.archive = archive
        self.counters = counters
    }

    /// The system's input counters as they stand.
    var reading: CounterReading {
        CounterReading(keys: counters.keys(), clicks: counters.clicks(), scrolls: counters.scrolls())
    }

    private static let logger = Logger(subsystem: FocusConstants.bundleIdentifier, category: "evidence")
    static var loggedAppendFailure = false

    /// A beat that could not be written is dropped: evidence never raises an alert. The first failure
    /// of a launch is logged, so a disk that is full or a folder that is gone is findable and a
    /// ticker second after second is not. Returns whether this call logged.
    @discardableResult
    static func noteAppendFailure(_ error: Error) -> Bool {
        guard !loggedAppendFailure else { return false }
        loggedAppendFailure = true
        logger.error("A beat could not be written and was dropped: \(error.localizedDescription)")
        return true
    }
}

/// Everything a row that is not running is read from: its bounds and records, the beats on disk (the
/// archive's revision moves on each append and prune), the records, app use and summaries
/// (`EvidenceRevision`, without the day and the live overlay, which do not touch an ended row), and
/// the settings the phases are worked out under.
struct SessionActivityStamp: Equatable {
    let end: Date
    let recordIDs: [UUID]
    let beats: Int
    let sessions: Int
    let usageID: ObjectIdentifier?
    let usage: Int
    let metadata: Int
    let overridesDigest: String
    let countsWhileWatching: Bool

    init(end: Date, recordIDs: [UUID], beats: Int, evidence: SessionStore.EvidenceRevision, overridesDigest: String,
         countsWhileWatching: Bool) {
        self.end = end
        self.recordIDs = recordIDs
        self.beats = beats
        sessions = evidence.sessions
        usageID = evidence.usageID
        usage = evidence.usage
        metadata = evidence.metadata
        self.overridesDigest = overridesDigest
        self.countsWhileWatching = countsWhileWatching
    }
}
