import AppKit
import ApplicationServices
import Foundation

/// The kind of site in a confirmed browser's front tab, read at an activation and at each beat edge
/// (never on a timer of its own) and written into the beat being recorded. Evidence only, as the beats are:
/// nothing here reads back into the engine. The reader decides whether anything is read (the gate, consent,
/// trust and the confirmed list); nothing here sees an address.
extension SessionStore {
    /// Asks about `app` while beats are being recorded (R7: before the first tick of a recording, nothing is),
    /// when it is in front and its process is known. The reader refuses an app that is not a confirmed browser,
    /// and that refusal leaves a pending read of the browser alone.
    func requestSiteRead(app: String?, at now: Date) {
        let evidence = activityEvidence
        guard recordsBeats, evidence.recording, let reader = evidence.siteReader, let app else { return }
        if let pid = evidence.frontPID(app), reader.request(app: app, pid: pid, at: now) { return }
        // A read that was refused (the signal turned off, the browser unticked, trust gone, the breaker tripped)
        // says nothing of the tab, so the kind a beat edge carried over is dropped, not kept.
        guard evidence.recorder.openSite != nil else { return }
        noteSiteReading(SiteReading(kind: nil, app: app, requestedAt: now), at: now)
    }

    /// An answer reaches the recorder only while recording goes on; the recorder drops one for another app.
    func noteSiteReading(_ reading: SiteReading, at now: Date) {
        let evidence = activityEvidence
        guard recordsBeats, evidence.recording else { return }
        evidence.recorder.site(reading.kind, app: reading.app, requestedAt: reading.requestedAt, at: now,
                               counters: evidence.reading, idleSeconds: idle.idleSeconds())
    }

    /// The app's reader: the worker is one serial utility queue, answers come back on the main queue, and
    /// the settings are the app's own preferences. Everything the worker calls is safe off the main thread.
    /// Until a probe report opens the gate for the running macOS (`SignalGate.passing`), nothing is read.
    /// `gateOn` stands in for that gate in checks, and `trusted` for Accessibility.
    func installSiteSignal(defaults: UserDefaults, gateOn: (() -> Bool)? = nil, trusted: (() -> Bool)? = nil) {
        let worker = DispatchQueue(label: "\(FocusConstants.bundleIdentifier).site-signal", qos: .utility)
        let macOSMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        activityEvidence.siteReader = SiteSignalReader(
            settings: SiteSignalSettings(defaults: defaults), reader: AXSiteAddressReader(),
            gateOn: gateOn ?? { SignalGate.isOn(.siteKind, macOSMajor: macOSMajor) },
            trusted: trusted ?? { AXIsProcessTrusted() },
            bundleID: { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier },
            run: { worker.async(execute: $0) },
            deliver: { DispatchQueue.main.async(execute: $0) },
            onReading: { [weak self] in
                guard let self else { return }
                self.noteSiteReading($0, at: self.now())
            })
        // The activation's own application: when another is in front by now, nothing is read.
        activityEvidence.frontPID = { app in
            guard let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier == app else { return nil }
            return front.processIdentifier
        }
    }
}
