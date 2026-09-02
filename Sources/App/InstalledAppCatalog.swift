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
        self.worker = DispatchQueue(label: "com.prabesh.focuscontinuity.app-catalog",
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

    /// Spotlight is intentionally scoped to ordinary application locations
    /// and capped. It supplements the bounded directory pass; it is not a disk
    /// crawler and never reads application content, windows, documents or URLs.
    static func spotlightApplications() -> [InstalledApplication] {
        let query = NSMetadataQuery()
        query.searchScopes = standardRoots
        query.predicate = NSPredicate(format: "%K == %@",
                                      NSMetadataItemContentTypeKey, "com.apple.application-bundle")
        let centre = NotificationCenter.default
        let semaphore = DispatchSemaphore(value: 0)
        let token = centre.addObserver(forName: .NSMetadataQueryDidFinishGathering,
                                       object: query, queue: nil) { _ in semaphore.signal() }
        query.start()
        _ = semaphore.wait(timeout: .now() + 1.5)
        query.disableUpdates()
        let result = query.results.prefix(200).compactMap { item -> InstalledApplication? in
            guard let metadata = item as? NSMetadataItem,
                  let path = metadata.value(forAttribute: NSMetadataItemPathKey) as? String else {
                return nil
            }
            return application(at: URL(fileURLWithPath: path))
        }
        query.stop()
        centre.removeObserver(token)
        return result
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
