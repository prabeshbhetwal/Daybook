import Foundation

// MARK: - Categories

enum AppCategory: String, Codable, CaseIterable {
    case work
    case breakTime
    case neutral

    var displayName: String {
        switch self {
        case .work: return "Work"
        case .breakTime: return "Break"
        case .neutral: return "Neutral"
        }
    }
}

// MARK: - State machine vocabulary

enum PauseReason: Equatable {
    case manual
    case distractionApp(bundleID: String)
    case extendedBreak
    case systemSleep
    /// The user said so, before leaving. Distinct from `.manual` because it also
    /// stops background recording: pausing a session still leaves you at the
    /// Mac, whereas declaring yourself away means nothing should accrue at all.
    case away
    /// Nobody has touched the machine for `idlePauseThreshold`. Distinct from
    /// `.manual` because only this one resumes by itself — undoing a pause the
    /// user pressed would be the app overruling a deliberate act.
    case idle
    /// Nobody has touched the machine, but something on screen is being
    /// watched — a video, a call, a presentation is keeping the display awake.
    /// Presence without input: never an absence, so never asked about; not
    /// work either outside Meetings and Learning, so the clock stops quietly
    /// and the stretch is written down as "Watching".
    case watching

    var displayName: String {
        switch self {
        case .manual: return "Paused"
        case .distractionApp: return "Paused (distraction)"
        case .extendedBreak: return "Paused (break)"
        case .systemSleep: return "Paused (sleep)"
        case .away: return "Away"
        case .idle: return "Paused (idle)"
        case .watching: return "Watching"
        }
    }
}

enum AwayTrigger: String, Codable, Equatable {
    case screenLock
    case systemSleep
}

enum SessionState: Equatable {
    case idle
    case running
    case paused(reason: PauseReason)
    case awaitingUserDecision(away: TimeInterval, lastApp: String)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }

    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .running: return "Running"
        case .paused(let reason): return reason.displayName
        case .awaitingUserDecision: return "Awaiting decision"
        }
    }
}

/// Every input the engine understands. `SessionEngine.transition(on:)` switches
/// exhaustively over `(SessionState, SessionEvent)`; unlisted pairs are no-ops.
enum SessionEvent: Equatable {
    case launch
    case awayBegan(trigger: AwayTrigger)
    case awayEnded
    case appActivated(bundleID: String?, name: String)
    case dwellExpired(bundleID: String)
    case manualPause
    case manualResume
    /// "I am stepping away." The one away signal the app does not have to guess,
    /// so it never asks about it afterwards.
    case markedAway
    /// Seconds since the last keypress or click, sampled by the ticker. The
    /// engine is otherwise event-driven; this is the one signal that has to be
    /// observed rather than announced.
    case idleObserved(seconds: TimeInterval)
    /// The same seconds, but something on screen is being watched meanwhile
    /// (the store tells the two apart). Quiet in front of a film is presence.
    case watchingObserved(seconds: TimeInterval)
    case decision(UserDecision)
    case resetSession
    case overrideApplied(bundleID: String)
}

enum UserDecision: String, Equatable, CaseIterable {
    /// "I was away." Excluded from the session; nothing is written down.
    case continueSession
    /// "I was working." The gap is added back as work on this session.
    case mergeTime
    /// "That was a break." Excluded exactly like `continueSession`, and also
    /// recorded as rest — so the day shows what the hole in the timeline was
    /// instead of leaving it blank. The distinction is what gets written down,
    /// not the arithmetic: being away and taking a break both stop the clock.
    case tookBreak
    /// "Start fresh." The old session is closed where the absence began.
    case resetTimer
}

// MARK: - Work type

/// What kind of work a completed session was. Distinct from `AppCategory`, which
/// answers "should this app pause my session?" — collapsing the two would break
/// the auto-pause logic.
enum WorkType: String, Codable, CaseIterable {
    case deepWork, meetings, admin, learning, breakTime

    var displayName: String {
        switch self {
        case .deepWork: return "Deep work"
        case .meetings: return "Meetings"
        case .admin: return "Admin"
        case .learning: return "Learning"
        case .breakTime: return "Break"
        }
    }

    var symbolName: String {
        switch self {
        case .deepWork: return "brain.head.profile"
        case .meetings: return "person.2.fill"
        case .admin: return "tray.full.fill"
        case .learning: return "book.fill"
        case .breakTime: return "cup.and.saucer.fill"
        }
    }

    /// Whether passive presence is the work itself: a meeting is attended, a
    /// lecture is watched. Anywhere else, watching without input is a pause.
    var countsWhileWatching: Bool { self == .meetings || self == .learning }

    /// Rest is not focus. A break belongs on the timeline, where it explains a
    /// gap, but never in the day's focused total — nothing else was stopping a
    /// session logged as "Break" from filling the daily goal and holding up a
    /// streak, which is the opposite of what recording it is for.
    var countsAsFocus: Bool { self != .breakTime }

    /// The kinds a person can actually start. `.breakTime` is written by the
    /// away card and by nothing else: offering it in the picker put "Break"
    /// under a button reading "Start Focus", and starting one produced a session
    /// that could not fill a goal, hold a streak, or count as focus — a session
    /// whose only effect was to exist.
    static var startable: [WorkType] { allCases.filter(\.countsAsFocus) }
}

// MARK: - Persisted models

struct SessionRecord: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var workType: WorkType
    var start: Date
    var end: Date
    var workSeconds: Double
    var detectedApp: String?
    /// Segments of one piece of work share a thread. Continuing a session
    /// starts a new record with the same thread rather than reopening the old
    /// one, so a four-hour lunch is never rendered as worked time.
    var threadID: UUID
    /// True when the app started this session itself rather than the user.
    /// Kept so the detector never ends work a person deliberately began, and so
    /// a later learner can tell its own guesses from real decisions.
    var isAuto: Bool

    init(id: UUID = UUID(),
         name: String,
         workType: WorkType,
         start: Date,
         end: Date,
         workSeconds: Double,
         detectedApp: String? = nil,
         threadID: UUID = UUID(),
         isAuto: Bool = false) {
        self.id = id
        self.name = name
        self.workType = workType
        self.start = start
        self.end = end
        self.workSeconds = workSeconds
        self.detectedApp = detectedApp
        self.threadID = threadID
        self.isAuto = isAuto
    }

    /// Records written before threads existed decode with a fresh thread each,
    /// so every old session becomes its own single-segment thread — which is
    /// the truth about it. Same pattern as `AppUsageSession.endReason`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        workType = try container.decode(WorkType.self, forKey: .workType)
        start = try container.decode(Date.self, forKey: .start)
        end = try container.decode(Date.self, forKey: .end)
        workSeconds = try container.decode(Double.self, forKey: .workSeconds)
        detectedApp = try container.decodeIfPresent(String.self, forKey: .detectedApp)
        threadID = try container.decodeIfPresent(UUID.self, forKey: .threadID) ?? UUID()
        // Records written before auto sessions existed were all started by hand.
        isAuto = try container.decodeIfPresent(Bool.self, forKey: .isAuto) ?? false
    }
}

extension SessionRecord {

    /// Wall-clock length, which is the work plus whatever was paused inside it.
    var span: TimeInterval { max(0, end.timeIntervalSince(start)) }

    /// The work this record contributes to a window, spread evenly across its
    /// span.
    ///
    /// Filing a whole record under the day it *ended* was the single largest
    /// source of wrong numbers in this app. A session begun on Friday afternoon
    /// and stopped on Sunday evening donated all of Friday's work to Sunday:
    /// Friday then read as a day with no focus at all, which broke the streak,
    /// blanked a bar on the week chart, and dropped the day from the "usual
    /// pace" median as inactive. Spreading is a guess about *when* inside the
    /// span the work happened; end-day attribution is a guess too, and an
    /// unbounded one.
    func workSeconds(in range: (start: Date, end: Date)) -> TimeInterval {
        // A zero-length record — a start immediately followed by a stop — has no
        // span to spread across, so it belongs wholly to the instant it happened.
        guard span > 0 else {
            return (end >= range.start && end < range.end) ? workSeconds : 0
        }
        let low = max(start, range.start)
        let high = min(end, range.end)
        guard high > low else { return 0 }
        return workSeconds * (high.timeIntervalSince(low) / span)
    }

    func workSeconds(on day: Date, calendar: Calendar) -> TimeInterval {
        guard let bounds = SessionRecord.dayBounds(day, calendar: calendar) else { return 0 }
        return workSeconds(in: bounds)
    }

    static func dayBounds(_ day: Date,
                          calendar: Calendar) -> (start: Date, end: Date)? {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        return (start, end)
    }
}

/// One column of the seven-day rhythm chart.
struct DayBar: Identifiable, Equatable {
    let id: Date
    let label: String
    let minutes: Int
    let isToday: Bool
}

/// A pinned one-click start, derived from history.
struct QuickStart: Identifiable, Equatable {
    let id: String
    let name: String
    let workType: WorkType
}

/// A flattened, `Codable` snapshot of the engine. Enums with payloads are stored
/// as primitives so the format stays stable and cheap to encode on every transition.
struct PersistedState: Codable, Equatable {
    enum Kind: String, Codable {
        case idle
        case running
        case paused
        case awaiting
    }

    var kind: Kind
    var name: String
    var sessionStart: Date
    var totalPaused: TimeInterval
    var pauseStart: Date?
    var pauseReason: String?
    var pauseBundleID: String?
    var awayStart: Date?
    var awayTrigger: AwayTrigger?
    var pendingAway: TimeInterval?
    var lastApp: String
    var savedAt: Date
    /// Optional so blobs written by an earlier build still decode.
    var lastAppBundleID: String?
    var decisionStarted: Date?
    var version: Int?
    /// Nil in snapshots written before threads existed.
    var threadID: UUID?
    var isAuto: Bool?
    /// Absence banked while an away card was up and not yet applied to a
    /// session. Optional so blobs written before it existed still decode; a
    /// missing value means nothing was owed, which is what `?? 0` says.
    var shadowAway: TimeInterval?
}

extension PersistedState {
    /// Flattens a live state into its stored representation.
    init(state: SessionState,
         name: String,
         sessionStart: Date,
         totalPaused: TimeInterval,
         pauseStart: Date?,
         away: (start: Date, trigger: AwayTrigger)?,
         lastApp: String,
         lastAppBundleID: String?,
         decisionStarted: Date?,
         savedAt: Date,
         threadID: UUID?,
         isAuto: Bool,
         shadowAway: TimeInterval = 0) {
        var kind: Kind
        var reason: String?
        var bundleID: String?
        var pending: TimeInterval?

        switch state {
        case .idle:
            kind = .idle
        case .running:
            kind = .running
        case .paused(let pauseReason):
            kind = .paused
            switch pauseReason {
            case .manual: reason = "manual"
            case .extendedBreak: reason = "extendedBreak"
            case .systemSleep: reason = "systemSleep"
            case .away: reason = "away"
            case .idle: reason = "idle"
            case .watching: reason = "watching"
            case .distractionApp(let id):
                reason = "distractionApp"
                bundleID = id
            }
        case .awaitingUserDecision(let away, _):
            kind = .awaiting
            pending = away
        }

        self.init(kind: kind,
                  name: name,
                  sessionStart: sessionStart,
                  totalPaused: totalPaused,
                  pauseStart: pauseStart,
                  pauseReason: reason,
                  pauseBundleID: bundleID,
                  awayStart: away?.start,
                  awayTrigger: away?.trigger,
                  pendingAway: pending,
                  lastApp: lastApp,
                  savedAt: savedAt,
                  lastAppBundleID: lastAppBundleID,
                  decisionStarted: decisionStarted,
                  version: 1,
                  threadID: threadID,
                  isAuto: isAuto,
                  shadowAway: shadowAway)
    }

    /// Rehydrates the pause reason; unknown values fall back to `.manual`.
    var restoredPauseReason: PauseReason {
        switch pauseReason {
        case "distractionApp": return .distractionApp(bundleID: pauseBundleID ?? "")
        case "extendedBreak": return .extendedBreak
        case "systemSleep": return .systemSleep
        case "away": return .away
        case "idle": return .idle
        case "watching": return .watching
        default: return .manual
        }
    }
}

// MARK: - Constants

enum FocusConstants {
    /// D7 — away intervals below this are discarded entirely.
    static let awayDebounce: TimeInterval = 5
    /// D6 — continuous frontmost dwell on a break app before pausing.
    static let distractionDwell: TimeInterval = 20
    /// Beyond this, an absence ends the session rather than pausing it. Picked
    /// so a long lunch or a school run still keeps your session, while anything
    /// that could be a night, a commute home, or a closed laptop does not.
    static let defaultLongAwayCap: TimeInterval = 4 * 3600
    static let longAwayCapOptions: [TimeInterval] = [
        3_600, 2 * 3_600, 3 * 3_600, 4 * 3_600, 6 * 3_600, 8 * 3_600
    ]
    /// Absences at least this long are asked about on a blurred screen rather
    /// than from the menu bar. Half an hour: a coffee is a quick click, lunch is
    /// long enough to have lost the thread. `nil` in the store means Never.
    static let defaultFullPromptAfter: TimeInterval = 30 * 60
    static let fullPromptAfterOptions: [TimeInterval] = [
        20 * 60, 30 * 60, 45 * 60, 60 * 60, 90 * 60, 120 * 60
    ]
    /// How far back "Continue Today" looks. Recency rather than the calendar
    /// date: at ten past midnight the thing you want to resume is what you were
    /// doing at eleven, and nothing about that work changed because a date
    /// rolled over. A calendar rule offers yesterday's work all of today and
    /// hides tonight's ten minutes after you started it.
    static let continueWindow: TimeInterval = 6 * 3_600
    /// Idle time after which a session pauses itself. Deliberately tolerant:
    /// reading a long document, thinking, and taking a call are all work the
    /// keyboard cannot see, and a three-minute rule punishes them. Lunch is
    /// still caught.
    static let idlePauseThreshold: TimeInterval = 600
    /// A break prompt stays up longer than a congratulation: it asks for
    /// something, and carries a reason worth reading before it goes.
    static let breakHUDSeconds: TimeInterval = 12
    /// Sessions shorter than this are never written. A misclick is not history.
    static let minimumRecordedSession: TimeInterval = 30
    /// D9 — selectable extended-break thresholds, in seconds.
    static let thresholdOptions: [TimeInterval] = [300, 600, 900, 1800, 3600]
    static let defaultThreshold: TimeInterval = 900
    /// Archive capacity. Raised from the original 50 (about one week) because
    /// streaks and Insights need years of history.
    static let archiveCapacity = 5000
    /// A day counts toward the streak once its sessions total this much work.
    static let streakMinimum: TimeInterval = 25 * 60
    /// Window used to derive the quick-start list.
    static let quickStartWindowDays = 14
    /// Recent sessions shown per app in the menu bar, and how many apps.
    static let defaultMenuSessions = 5
    static let defaultMenuApps = 4
    /// Break reminders: work this long continuously, then take this long off.
    static let defaultWorkInterval: TimeInterval = 50 * 60
    static let defaultBreakLength: TimeInterval = 10 * 60
    /// Wide enough for a pomodoro and for someone who works in one long block.
    /// Three fixed choices assumed everyone works the same way.
    static let workIntervalOptions: [TimeInterval] = [
        15 * 60, 25 * 60, 30 * 60, 45 * 60, 50 * 60,
        60 * 60, 90 * 60, 120 * 60, 180 * 60
    ]
    /// Up to an hour: lunch is a break, and the old 15-minute ceiling could not
    /// describe one.
    static let breakLengthOptions: [TimeInterval] = [
        5 * 60, 10 * 60, 15 * 60, 20 * 60, 30 * 60, 45 * 60, 60 * 60
    ]
    /// A short day must not render as one block on a one-hour axis.
    static let minimumTimelineSpan: TimeInterval = 4 * 3_600
    /// Gaps at or over this collapse to a labelled separator instead of eating
    /// the band's width.
    static let timelineGapThreshold: TimeInterval = 20 * 60
    /// D3 — cosmetic title refresh cadence.
    static let titleRefreshInterval: TimeInterval = 30
    static let titleRefreshTolerance: TimeInterval = 15
    /// D11 — settle delay so the WindowServer is ready after a wake.
    static let alertPresentationDelay: TimeInterval = 1.5
    /// Input density is sampled at event boundaries, never on a timer, so this
    /// ring holds the last N app switches rather than N seconds. Fixed size, so
    /// memory is constant however long the app runs.
    static let densityRingSize = 15
    /// Per-minute floors separating producing from consuming.
    static let activeKeysPerMinute: Double = 12
    static let activeClicksPerMinute: Double = 4
    /// An app must be attended at least this long to count as a session's side
    /// app. Keeps a two-second Finder detour out of the list.
    static let sideAppMinimum: TimeInterval = 60
    // MARK: Auto sessions

    /// Media above this share of the window vetoes the score outright: a film
    /// playing is not deep work however much typing accompanies it.
    static let mediaVetoShare: Double = 0.25
    /// App switches per minute above this start costing score. Rapid churn
    /// between many apps is not deep work.
    static let calmSwitchRate: Double = 2
    static let switchPenaltyWeight: Double = 0.15
    /// Window the score is measured over.
    static let focusWindow: TimeInterval = 15 * 60
    /// Asymmetric on purpose. Equal thresholds make an automatic mode flap on
    /// and off around the boundary, which is what makes such modes feel stupid.
    static let autoStartThreshold: Double = 0.65
    static let autoStopThreshold: Double = 0.35
    /// The pattern must hold this long before a session starts; the session is
    /// then backdated to when the stretch began, so the wait is not lost.
    static let autoStartDwell: TimeInterval = 5 * 60
    /// Once started, a session cannot be auto-ended before this — one trip to
    /// Slack must not undo it.
    static let autoMinRunDwell: TimeInterval = 3 * 60

    // MARK: Daily goal

    static let defaultDailyGoal: TimeInterval = 4 * 3_600
    /// From half an hour to twelve. Finer near the bottom, where the difference
    /// between 30m and 1h is most of the target, and coarser at the top where
    /// an hour either way matters less.
    ///
    /// Capped at twelve deliberately. Past that a "daily goal" stops describing
    /// a working day, and a cap is the one place this app should hold an
    /// opinion — it exists to keep time honest, not to encourage more of it.
    static let dailyGoalOptions: [TimeInterval] = [
        1_800, 2_700, 3_600, 5_400, 7_200, 9_000, 10_800, 12_600,
        14_400, 18_000, 21_600, 25_200, 28_800, 32_400, 36_000, 39_600, 43_200
    ]
    /// Days of history used for the personal median, and the floor below which
    /// no median is worth quoting.
    static let goalMedianWindowDays = 14
    static let goalMedianMinimumDays = 3

    // MARK: Rewards

    /// Cheap praise stops landing almost immediately, so this is deliberately low.
    /// Apps below this in a period collapse into one line. A five-second Finder
    /// visit is a true measurement, but it costs a full row and a bar too small
    /// to see — the same space as an app that took an hour.
    static let minorAppFloor: TimeInterval = 30

    static let rewardsPerDay = 4
    static let rewardCooldown: TimeInterval = 45 * 60
    /// How long a focused app and a music app must overlap before it is a thing
    /// worth remarking on.
    static let musicPairingDwell: TimeInterval = 30 * 60
    static let hudDisplaySeconds: TimeInterval = 5

    static let bundleIdentifier = "com.prabesh.focuscontinuity"
}

enum Diagnostics {
    static func log(_ message: String) {
        FileHandle.standardError.write(Data("[FocusContinuity] \(message)\n".utf8))
    }
}
