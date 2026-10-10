import Foundation

/// Something the Mac or Daybook did that stops or resumes recording, and when.
///
/// History used to guess why a day has a hole in it from how the last app
/// stretch ended, and every stop — lock, sleep, shut down, quit — ended the
/// same way, so all of them read "Mac locked". These say what happened.
///
/// An event seen as it happened carries its exact time in `at`. One found only
/// at the next launch — a crash, a force quit, a power cut — happened at some
/// moment between `at`, the last sign that Daybook was running, and `latest`,
/// the first moment it is known to have happened by.
struct MachineEvent: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case systemSleep, wake, displaySleep, displayWake
        case lock, unlock, userSwitchedOut, userSwitchedIn
        /// How a run ended. A log out, restart or shut down is the reason
        /// macOS gave, confirmed at the next launch by the boot and the login
        /// session; a quit is Daybook's own.
        case logOut, restart, shutDown, quit, updateRelaunch
        /// Another app quit Daybook: System Settings applying a permission, a
        /// script, an installer. `detail` names it.
        case quitByApp
        /// macOS asked Daybook to quit for a log out, restart or shut down
        /// that then never happened: another app refused, or it was cancelled.
        case logOutCancelled, restartCancelled, shutDownCancelled
        /// The Mac went down and came back, and macOS never said which.
        case restartOrShutDown
        /// Only ever the marker's word for a power-off macOS announced without
        /// a reason; the next launch settles it. Entries written as this before
        /// that are read by what followed them (`MachineEventLog`).
        case powerOffUnknown
        /// How a run ended without saying so, worked out at the next launch.
        case crashed, forceQuit, powerLost, kernelPanic
        case macStarted, daybookStarted
        /// The Mac came back on a different macOS; `detail` is the new one.
        case macOSUpdated
    }

    let kind: Kind
    let at: Date
    /// Set only for an event found afterwards: it happened by this moment.
    var latest: Date?
    /// Who quit Daybook, or the macOS version the Mac came back on.
    var detail: String?

    init(kind: Kind, at: Date, latest: Date? = nil, detail: String? = nil) {
        self.kind = kind
        self.at = at
        self.latest = latest
        self.detail = detail
    }

    /// When the event is known to be over: `latest`, or `at` for one seen live.
    var end: Date { latest ?? at }

    /// What the event list says happened.
    var title: String {
        switch kind {
        case .quitByApp: return "Daybook quit by \(detail ?? "another app")"
        case .macOSUpdated: return detail.map { "macOS updated to \($0)" } ?? kind.title
        default: return kind.title
        }
    }

    /// Whether the event belongs to a hole in the recording. The recording
    /// stops a moment after the event that stopped it, and a run found to
    /// have ended afterwards is dated from its last heartbeat, so an event
    /// counts from a little before the hole and by its whole window. The
    /// hole's name, its card and the story's pins all ask this.
    func falls(in hole: DateInterval) -> Bool {
        at < hole.end && end >= hole.start.addingTimeInterval(-2)
    }

    /// Daybook was back within the minute a hole needs, so none was left.
    func isQuickReturn(at resumed: Date) -> Bool { resumed.timeIntervalSince(end) < 60 }
}

extension MachineEvent.Kind {
    /// What the event list says happened, when the event adds no detail.
    var title: String {
        switch self {
        case .systemSleep: return "Mac went to sleep"
        case .wake: return "Mac woke"
        case .displaySleep: return "Display turned off"
        case .displayWake: return "Display turned on"
        case .lock: return "Screen locked"
        case .unlock: return "Screen unlocked"
        case .userSwitchedOut: return "Switched to another user"
        case .userSwitchedIn: return "Switched back to this user"
        case .logOut: return "Logged out"
        case .restart: return "Mac restarted"
        case .shutDown: return "Mac shut down"
        case .quit: return "Daybook quit"
        case .updateRelaunch: return "Daybook updated"
        case .quitByApp: return "Daybook quit by another app"
        case .logOutCancelled: return "Log out cancelled after Daybook quit"
        case .restartCancelled: return "Restart cancelled after Daybook quit"
        case .shutDownCancelled: return "Shut down cancelled after Daybook quit"
        case .restartOrShutDown: return "Mac restarted or shut down"
        case .powerOffUnknown: return "Shut down, restarted or logged out"
        case .crashed: return "Daybook crashed"
        case .forceQuit: return "Daybook was force quit"
        case .powerLost: return "Mac lost power or was forced off"
        case .kernelPanic: return "Mac restarted after a problem"
        case .macStarted: return "Mac started up"
        case .daybookStarted: return "Daybook opened"
        case .macOSUpdated: return "macOS updated"
        }
    }

    /// How a run of Daybook ends: said at the time, or found at the next launch.
    static let runEndings: Set<Self> = [.logOut, .restart, .shutDown, .quit, .updateRelaunch, .quitByApp,
                                        .logOutCancelled, .restartCancelled, .shutDownCancelled,
                                        .restartOrShutDown, .powerOffUnknown,
                                        .crashed, .forceQuit, .powerLost, .kernelPanic]

    /// What a hole in the day says when an event explains it, most telling
    /// first: a hole that holds a lock and a sleep was a sleep. An event that
    /// ends a hole rather than causing one — a wake, an unlock, a start — is
    /// not here.
    static let gapCauses: [(kind: Self, title: String)] = [
        (.powerLost, "Mac lost power"), (.kernelPanic, "Mac restarted after a problem"),
        (.crashed, "Daybook crashed"), (.forceQuit, "Daybook was force quit"),
        (.macOSUpdated, "Mac updating macOS"),
        (.shutDown, "Mac shut down"), (.restart, "Mac restarted"),
        (.restartOrShutDown, "Mac restarted or shut down"), (.logOut, "Logged out"),
        (.updateRelaunch, "Daybook updating"), (.quitByApp, "Daybook quit by another app"),
        (.logOutCancelled, "Daybook quit; log out cancelled"),
        (.restartCancelled, "Daybook quit; restart cancelled"),
        (.shutDownCancelled, "Daybook quit; shut down cancelled"),
        (.quit, "Daybook quit"),
        (.systemSleep, "Mac asleep"), (.userSwitchedOut, "Another user"),
        (.lock, "Mac locked"), (.displaySleep, "Display off"),
    ]
}
