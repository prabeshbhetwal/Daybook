import Foundation

/// What the wiring checks share: a store whose reader is a fake with every gate open for Chrome.
extension SiteSignalWiringChecks {
    /// `deferred` non-nil queues the worker's jobs, and `held` non-nil the deliveries, as the app's two
    /// queues would. `gate` and `trust` are what the reader finds when it asks.
    final class Wiring {
        let r: Rig
        let fake = SiteSignalChecks.FakeReader()
        let suite = "fc-selftest-site-wiring-" + UUID().uuidString
        let settings: SiteSignalSettings
        var deferred: [() -> Void]?
        var held: [() -> Void]?
        var gate = true, trust = true

        init(_ r: Rig, consented: Bool) {
            self.r = r
            settings = SiteSignalSettings(defaults: MemoryDefaults.suite(named: suite)!)
            if consented { settings.turnOn(apps: [SiteSignalChecks.chrome]) }
            r.evidence.frontPID = { _ in SiteSignalChecks.chromePID }
            r.evidence.siteReader = SiteSignalReader(
                settings: settings, reader: fake,
                gateOn: { [unowned self] in self.gate }, trusted: { [unowned self] in self.trust },
                bundleID: { $0 == SiteSignalChecks.chromePID ? SiteSignalChecks.chrome : nil },
                run: { [unowned self] work in if self.deferred != nil { self.deferred?.append(work) } else { work() } },
                deliver: { [unowned self] work in if self.held != nil { self.held?.append(work) } else { work() } },
                onReading: { [unowned self] in self.r.store.noteSiteReading($0, at: self.r.clock.value) })
        }

        func close() { r.close(); MemoryDefaults.remove(named: suite) }
        func runJobs() { let jobs = deferred ?? []; deferred = []; jobs.forEach { $0() } }
        func deliver() { let work = held ?? []; held = []; work.forEach { $0() } }
        var slices: [BeatSlice] { r.beats.flatMap(\.slices) }
    }

    @MainActor
    static func wired(session: Bool = true, auto: Bool = false, consented: Bool = true) -> Wiring? {
        ActivityEvidenceStoreChecks.rig(session: session, auto: auto).map { Wiring($0, consented: consented) }
    }
}
