import Foundation
import AppKit
import Combine

struct InstalledApplication: Equatable, Identifiable {
    let bundleID: String
    let name: String
    let url: URL?
    let isInstalled: Bool
    var id: String { bundleID }
    var displayName: String { isInstalled ? name : "\(name) — Missing" }

    init(bundleID: String, name: String, url: URL?, isInstalled: Bool = true) {
        self.bundleID = ActivityRule.normalisedBundleID(bundleID) ?? bundleID.lowercased()
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.url = url; self.isInstalled = isInstalled
    }
}

/// One mutable value shared between a run-loop callback and the code waiting
/// on it. Both touch it on the same thread; the reference exists only because
/// a callback cannot capture a local `var` without escaping it.
private final class RunLoopFlag {
    var isSet = false
}

final class InstalledAppCatalog: ObservableObject {
    @Published private(set) var applications: [InstalledApplication] = []
    @Published private(set) var isLoading = false

    private let discoverStandard: () -> [InstalledApplication]
    private let discoverSpotlight: () -> [InstalledApplication]
    private let observed: () -> [InstalledApplication]
    private let worker: DispatchQueue

    init(discoverStandard: @escaping () -> [InstalledApplication] = { InstalledAppCatalog.standardApplications() },
         discoverSpotlight: @escaping () -> [InstalledApplication] = InstalledAppCatalog.spotlightApplications,
         observed: @escaping () -> [InstalledApplication] = { [] }) {
        self.discoverStandard = discoverStandard
        self.discoverSpotlight = discoverSpotlight
        self.observed = observed
        self.worker = DispatchQueue(label: "com.prabesh.daybook.app-catalog",
                                    qos: .userInitiated)
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        worker.async { [weak self] in
            guard let self else { return }
            let discovered = Self.deduplicated(
                self.discoverStandard() + self.discoverSpotlight() + self.observed())
            DispatchQueue.main.async {
                self.applications = discovered
                self.isLoading = false
            }
        }
    }

    func discoverSynchronouslyForVerification() -> [InstalledApplication] {
        Self.deduplicated(discoverStandard() + discoverSpotlight() + observed())
    }

    static func deduplicated(_ applications: [InstalledApplication]) -> [InstalledApplication] {
        var byID: [String: InstalledApplication] = [:]
        for application in applications {
            let key = application.bundleID.lowercased()
            guard !key.isEmpty else { continue }
            if let existing = byID[key] {
                if !existing.isInstalled && application.isInstalled { byID[key] = application }
                else if existing.url == nil, application.url != nil { byID[key] = application }
            } else {
                byID[key] = application
            }
        }
        return byID.values.sorted {
            let names = $0.name.localizedCaseInsensitiveCompare($1.name)
            return names == .orderedSame ? $0.bundleID < $1.bundleID : names == .orderedAscending
        }
    }

    private static let standardRoots: [URL] = {
        var roots = [URL(fileURLWithPath: "/Applications", isDirectory: true),
                     URL(fileURLWithPath: "/System/Applications", isDirectory: true),
                     URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true)]
        roots.append(FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true))
        return roots
    }()

    static func standardApplications(fileManager: FileManager = .default) -> [InstalledApplication] {
        standardRoots.flatMap { root in
            let urls = (try? fileManager.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])) ?? []
            return urls.prefix(300).compactMap(application(at:))
        }
    }

    /// The Spotlight supplement is bounded in both time and size.
    private static let spotlightBudget: TimeInterval = 1.5
    private static let spotlightResultCap = 200

    /// Turns the current thread's run loop until `isSatisfied` holds or the
    /// budget expires, and reports which happened.
    ///
    /// A GCD worker owns a run loop but never runs it. An API that delivers
    /// through the run loop cannot make progress behind a blocking wait — the
    /// wait starves the very delivery it is waiting for. A keep-alive timer
    /// guarantees the loop always has a source, so each turn blocks for input
    /// rather than spinning.
    @discardableResult
    static func turnRunLoop(until isSatisfied: () -> Bool,
                            timeout: TimeInterval,
                            now: () -> Date = Date.init) -> Bool {
        if isSatisfied() { return true }
        let deadline = now().addingTimeInterval(timeout)
        let keepAlive = Timer(timeInterval: 0.02, repeats: true) { _ in }
        RunLoop.current.add(keepAlive, forMode: .default)
        defer { keepAlive.invalidate() }
        while now() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            if isSatisfied() { return true }
        }
        return isSatisfied()
    }

    /// Spotlight is intentionally scoped to ordinary application locations
    /// and capped. It supplements the bounded directory pass; it is not a disk
    /// crawler and never reads application content, windows, documents or URLs.
    static func spotlightApplications() -> [InstalledApplication] {
        let query = NSMetadataQuery()
        query.searchScopes = standardRoots
        query.predicate = NSPredicate(format: "%K == %@",
                                      NSMetadataItemContentTypeKey, "com.apple.application-bundle")
        let centre = NotificationCenter.default
        let gathered = RunLoopFlag()
        let token = centre.addObserver(forName: .NSMetadataQueryDidFinishGathering,
                                       object: query, queue: nil) { _ in gathered.isSet = true }
        defer { centre.removeObserver(token) }
        guard query.start() else { return [] }
        defer { query.stop() }
        // Gathering arrives through this thread's run loop, so it is turned
        // rather than blocked on. A budget that expires yields whatever was
        // gathered by then; it never yields more than was observed.
        turnRunLoop(until: { gathered.isSet }, timeout: spotlightBudget)
        query.disableUpdates()
        return query.results.prefix(spotlightResultCap).compactMap { item -> InstalledApplication? in
            guard let metadata = item as? NSMetadataItem,
                  let path = metadata.value(forAttribute: NSMetadataItemPathKey) as? String else {
                return nil
            }
            return application(at: URL(fileURLWithPath: path))
        }
    }

    static func application(at url: URL) -> InstalledApplication? {
        guard url.pathExtension.lowercased() == "app", let bundle = Bundle(url: url),
              let id = bundle.bundleIdentifier else { return nil }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return InstalledApplication(bundleID: id, name: name, url: url)
    }
}
