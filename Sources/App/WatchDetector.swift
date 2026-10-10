import AppKit
import IOKit.pwr_mgt

/// Who is holding the display awake right now, read from powerd's public
/// assertion list: no permission involved, nothing about *what* is playing.
///
/// A visible (Dock) app holding it is something being watched — a video, a
/// call, a presentation; a browser playing a film holds exactly this ("Video
/// Wake Lock"). Anything else holding it is a keep-awake utility: menu bar apps
/// such as Amphetamine, Caffeine or KeepingYouAwake, and `caffeinate`. That is
/// the machine kept on, not a person in front of it, so it is presence only
/// where the user says so (`countsKeepAwake`).
enum WatchDetector {
    struct Reading: Equatable {
        var watching = false
        var keptAwake = false
        /// The apps being watched. A call or a film uploads and decodes; that
        /// is watching, and must not read as work going on.
        var watchedApps: Set<String> = []
    }

    private static let displayTypes: Set<String> = [
        "NoDisplaySleepAssertion", "PreventUserIdleDisplaySleep"
    ]

    static func read() -> Reading {
        var reading = Reading()
        var raw: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&raw) == kIOReturnSuccess,
              let byProcess = raw?.takeRetainedValue() as? [AnyHashable: Any] else { return reading }
        let own = ProcessInfo.processInfo.processIdentifier
        for (key, value) in byProcess {
            guard let pid = (key as? NSNumber)?.int32Value ?? (key as? Int).map(Int32.init),
                  pid != own,
                  let assertions = value as? [[String: Any]],
                  assertions.contains(where: {
                      displayTypes.contains(($0["AssertType"] as? String) ?? "")
                  }) else { continue }
            let app = NSRunningApplication(processIdentifier: pid)
            if app?.activationPolicy == .regular {
                reading.watching = true
                if let bundleID = app?.bundleIdentifier { reading.watchedApps.insert(bundleID) }
            } else {
                reading.keptAwake = true
            }
        }
        return reading
    }
}
