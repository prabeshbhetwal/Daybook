import Foundation

/// Asks a confirmed browser which kind of site its front tab shows, off the main
/// thread, and hands back only a `SiteReading`. Every gate is checked when a read
/// is asked for, when the worker starts the read and, on the main thread, when its
/// answer arrives, so `gateOn` and `trusted` must be safe to call from the worker. Logs nothing.
final class SiteSignalReader {
    private let settings: SiteSignalSettings
    private let reader: SiteAddressReading
    private let gateOn: () -> Bool
    private let trusted: () -> Bool
    private let bundleID: (pid_t) -> String?
    private let run: (@escaping () -> Void) -> Void
    private let deliver: (@escaping () -> Void) -> Void
    private let onReading: (SiteReading) -> Void

    /// Main thread only: timeouts per app since recording began.
    private var timeouts: [String: Int] = [:]
    /// The newest request's number. A reset or a newer request makes older ones
    /// stale: a stale job reads nothing and a stale answer is dropped. Read on the worker too.
    private var newest = 0
    private let newestLock = NSLock()

    init(settings: SiteSignalSettings, reader: SiteAddressReading,
         gateOn: @escaping () -> Bool, trusted: @escaping () -> Bool,
         bundleID: @escaping (pid_t) -> String?,
         run: @escaping (@escaping () -> Void) -> Void,
         deliver: @escaping (@escaping () -> Void) -> Void,
         onReading: @escaping (SiteReading) -> Void) {
        self.settings = settings
        self.reader = reader
        self.gateOn = gateOn
        self.trusted = trusted
        self.bundleID = bundleID
        self.run = run
        self.deliver = deliver
        self.onReading = onReading
    }

    /// Called on the main thread; returns at once. Reads nothing unless gate, consent, trust and the
    /// confirmed list all allow `app`, and its breaker is not tripped; says whether it asked. A newer request
    /// replaces a pending one.
    @discardableResult func request(app: String, pid: pid_t, at: Date) -> Bool {
        guard allows(app), timeouts[app, default: 0] < SiteSignalConstants.timeoutsBeforeSkipping else { return false }
        let number = bumpNewest()
        let remembered = settings.remembers ? settings.rememberedSites : [:]
        let reader = self.reader, bundleID = self.bundleID
        run { [weak self] in
            // Checked again as the job starts: the signal may have been turned off while it waited.
            guard let self, self.isNewest(number), self.allows(app), bundleID(pid) == app else { return }
            let result = Self.readKind(reader: reader, pid: pid, remembered: remembered)
            self.deliver { [weak self] in
                self?.finish(app: app, number: number, at: at, kind: result.kind, timedOut: result.timedOut)
            }
        }
        return true
    }

    /// Recording ended: breakers reset, pending and in-flight results are dropped.
    func reset() {
        timeouts = [:]
        bumpNewest()
    }

    /// The only place an address exists: it is reduced to a kind here and dropped.
    private static func readKind(reader: SiteAddressReading, pid: pid_t,
                                 remembered: [String: SiteKind]) -> (kind: SiteKind?, timedOut: Bool) {
        switch reader.read(pid: pid, timeout: SiteSignalConstants.readTimeout) {
        case .address(let address):
            let kind = SiteAddress.siteName(fromAddress: address)
                .flatMap { SiteKindTable.kind(forSite: $0, remembered: remembered) }
            return (kind, false)
        case .failed: return (nil, false)
        case .timedOut: return (nil, true)
        }
    }

    private func finish(app: String, number: Int, at: Date, kind: SiteKind?, timedOut: Bool) {
        guard isNewest(number) else { return }
        if timedOut { timeouts[app, default: 0] += 1 }
        guard allows(app) else { return }
        onReading(SiteReading(kind: kind, app: app, requestedAt: at))
    }

    private func allows(_ app: String) -> Bool {
        gateOn() && settings.isConsented && trusted() && settings.apps.contains(app)
    }

    @discardableResult private func bumpNewest() -> Int {
        newestLock.lock(); defer { newestLock.unlock() }
        newest += 1
        return newest
    }

    private func isNewest(_ number: Int) -> Bool {
        newestLock.lock(); defer { newestLock.unlock() }
        return newest == number
    }
}
