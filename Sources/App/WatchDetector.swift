import AppKit
import IOKit.pwr_mgt

/// Whether something on screen is being watched right now: a visible app is
/// holding the display awake — a video, a call, a presentation. Read from
/// powerd's public assertion list; no permission involved, nothing about *what*
/// is playing. Only regular (Dock) apps count: keep-awake utilities are menu
/// bar apps, and a helper process keeping the screen on is not a person in
/// front of it. A browser playing a film holds exactly this ("Video Wake Lock").
enum WatchDetector {

    private static let displayTypes: Set<String> = [
        "NoDisplaySleepAssertion", "PreventUserIdleDisplaySleep"
    ]

    static func isWatching() -> Bool {
        var raw: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&raw) == kIOReturnSuccess,
              let byProcess = raw?.takeRetainedValue() as? [AnyHashable: Any] else { return false }
        let own = ProcessInfo.processInfo.processIdentifier
        for (key, value) in byProcess {
            guard let pid = (key as? NSNumber)?.int32Value ?? (key as? Int).map(Int32.init),
                  pid != own,
                  let assertions = value as? [[String: Any]],
                  assertions.contains(where: {
                      displayTypes.contains(($0["AssertType"] as? String) ?? "")
                  }),
                  let app = NSRunningApplication(processIdentifier: pid),
                  app.activationPolicy == .regular else { continue }
            return true
        }
        return false
    }
}
