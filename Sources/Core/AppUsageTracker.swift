import Foundation

/// Turns frontmost-app changes into usage sessions. Driven entirely by the
/// notifications `EventMonitor` already receives — no polling, no new
/// permissions, bundle identifiers and localised names only. Window titles, URLs
/// and keystrokes are never read.
///
/// Tracking can be switched off; when off, nothing is recorded at all.
final class AppUsageTracker {

    private struct OpenSegment {
        let bundleID: String
        let appName: String
        let start: Date
    }

    private let archive: AppUsageArchive
    private let now: () -> Date
    private let ownBundleID: String?
    private let idle: IdleMonitor
    private var open: OpenSegment?

    private(set) var isEnabled: Bool

    init(archive: AppUsageArchive,
         ownBundleID: String? = Bundle.main.bundleIdentifier,
         isEnabled: Bool = true,
         idle: IdleMonitor = IdleMonitor(),
         now: @escaping () -> Date = Date.init) {
        self.archive = archive
        self.ownBundleID = ownBundleID
        self.isEnabled = isEnabled
        self.idle = idle
        self.now = now
    }

    /// After this much input-free time, the machine is not being used and the
    /// open stretch stops accruing. Screen Time is criticised for exactly the
    /// opposite: counting an app as in use whenever it is frontmost, even when
    /// nobody is at the keyboard.
    static let idleCutoff: TimeInterval = 180

    /// The instant the open stretch should end, and whether idle trimmed it.
    ///
    /// The clock is sampled **once**: comparing a trimmed end against a freshly
    /// sampled `now()` was always true by microseconds, which labelled every
    /// stretch `.idle` and made grouping apply the 15-minute away bridge where
    /// the 5-minute gap belonged.
    private func effectiveEnd() -> (end: Date, trimmed: Bool) {
        let moment = now()
        let idleFor = idle.idleSeconds()
        guard idleFor >= AppUsageTracker.idleCutoff else { return (moment, false) }
        return (moment.addingTimeInterval(-idleFor), true)
    }

    /// The app that is frontmost right now, if tracking is running.
    var currentBundleID: String? { open?.bundleID }

    /// How long the in-flight stretch has run, idle-trimmed exactly as a real
    /// close would trim it. Lets the menu bar show a live "at the Mac" figure
    /// without writing a record every second: the archive only learns about an
    /// open stretch when something forces a flush, and between flushes the total
    /// stood visibly still — five minutes of "0m" after a boot, in one measured
    /// case, because nothing had happened yet to trigger a write.
    func openSeconds() -> TimeInterval {
        guard let segment = open else { return 0 }
        return max(0, effectiveEnd().end.timeIntervalSince(segment.start))
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        if !enabled { closeOpenSegment(reason: .systemLock) }
        isEnabled = enabled
    }

    /// A new app came to the front. Closes the previous stretch and opens one.
    func appActivated(bundleID: String?, name: String) {
        guard isEnabled else { return }
        // Our own popover taking focus must not chop the user's session in two.
        if let bundleID, bundleID == ownBundleID { return }
        guard let bundleID else { return }
        // The lock screen is not an app the user chose to use. Closing the open
        // stretch but opening none means the absence records as a gap, which is
        // what it was.
        if AppUsageArchive.systemProcesses.contains(bundleID) {
            closeOpenSegment(reason: .systemLock)
            return
        }
        if open?.bundleID == bundleID { return }

        closeOpenSegment(reason: .appSwitch)
        open = OpenSegment(bundleID: bundleID,
                           appName: name.isEmpty ? bundleID : name,
                           start: now())
    }

    /// The user went away — lock, sleep or power off. Time spent away is not
    /// usage, so the stretch ends here rather than running until they return.
    func suspend() {
        closeOpenSegment(reason: .systemLock)
    }

    private func closeOpenSegment(reason: UsageEndReason) {
        guard let segment = open else { return }
        open = nil
        let (candidate, wasTrimmed) = effectiveEnd()
        // Idle trimming outranks the nominal reason: the stretch really ended
        // when input stopped, not when the app changed.
        archive.record(AppUsageSession(bundleID: segment.bundleID,
                                       appName: segment.appName,
                                       start: segment.start,
                                       end: max(segment.start, candidate),
                                       endReason: wasTrimmed ? .idle : reason))
    }

    /// Flushes the in-flight stretch so queries include it. Called before the
    /// menu bar reads its data, and on terminate.
    func flush() {
        guard let segment = open else { return }
        let (candidate, wasTrimmed) = effectiveEnd()
        let end = max(segment.start, candidate)
        let written = archive.record(AppUsageSession(bundleID: segment.bundleID,
                                                     appName: segment.appName,
                                                     start: segment.start,
                                                     end: end,
                                                     endReason: wasTrimmed ? .idle : .stillOpen))
        // Only advance when the write actually landed. The archive refuses
        // anything under `minimumSegment`, and flushes fire on every app switch,
        // lock and wake — so moving the start regardless quietly deleted the
        // seconds between two rapid flushes, always downward, without limit.
        guard written else { return }
        // Continue from where the flushed portion ended, so the same seconds are
        // never written twice.
        open = OpenSegment(bundleID: segment.bundleID,
                           appName: segment.appName,
                           start: end)
    }

    /// True when the open stretch has been accruing long enough that losing it
    /// to a crash would matter. Drives the periodic flush.
    func openSeconds(exceeds limit: TimeInterval) -> Bool {
        openSeconds() >= limit
    }

    /// The machine came back. Reopens tracking for whatever is frontmost, because
    /// waking and carrying on in the *same* app posts no activation notification —
    /// that work was simply never recorded.
    func resume(bundleID: String?, name: String) {
        guard isEnabled, open == nil, let bundleID, bundleID != ownBundleID,
              !AppUsageArchive.systemProcesses.contains(bundleID) else { return }
        open = OpenSegment(bundleID: bundleID,
                           appName: name.isEmpty ? bundleID : name,
                           start: now())
    }
}
