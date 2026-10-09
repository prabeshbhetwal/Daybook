import AppKit

/// Runs the backup schedule's check: every half hour through macOS's own
/// scheduler for background work, a minute after launch, and on wake, so a
/// Mac that was asleep or shut down at the due time backs up soon after. The
/// check itself decides whether a backup is due. Started only by the running
/// app; checks and fixtures never start it.
final class BackupScheduler {
    private let activity = NSBackgroundActivityScheduler(identifier: "com.prabesh.daybook.backup")
    private var wakeObserver: NSObjectProtocol?

    func start(check: @escaping () -> Void) {
        activity.repeats = true
        activity.interval = BackupSchedule.checkInterval
        activity.tolerance = 5 * 60
        activity.qualityOfService = .utility
        activity.schedule { completion in
            // The check and the clone run on the main thread, where every
            // write to the data folder happens; the copy itself then goes on
            // in the background, so this activity is done once it is handed over.
            DispatchQueue.main.async {
                check()
                completion(.finished)
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in check() }
        // Not during launch itself, which has enough to do.
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: check)
    }

    deinit {
        activity.invalidate()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
}
