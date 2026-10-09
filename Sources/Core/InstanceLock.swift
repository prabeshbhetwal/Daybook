import Foundation

/// One Daybook at a time: two copies would write the same history and
/// preferences. The running app holds an exclusive lock on a file in its data
/// folder for as long as it runs, whichever folder its bundle is in. The
/// kernel releases it when the process ends, a crash included, so a stale
/// lock never keeps the app from starting.
enum InstanceLock {
    static let fileName = ".daybook.lock"
    /// Posted by a second copy before it quits; the running one brings its
    /// window forward.
    static let reopenNotification = Notification.Name("com.prabesh.daybook.reopen")

    enum Outcome: Equatable {
        /// Keep the descriptor open for the life of the process.
        case acquired(Int32)
        case heldElsewhere
        /// The file could not be opened. The app starts anyway: a lock file
        /// is never a reason to refuse to record.
        case unavailable
    }

    static func acquire(in directory: URL, fileManager: FileManager = .default) -> Outcome {
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = open(directory.appendingPathComponent(fileName).path, O_RDWR | O_CREAT, 0o644)
        guard descriptor >= 0 else { return .unavailable }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let held = errno == EWOULDBLOCK
            close(descriptor)
            return held ? .heldElsewhere : .unavailable
        }
        return .acquired(descriptor)
    }
}
