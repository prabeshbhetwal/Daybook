import AppKit
import Foundation

/// The apps the system says can open a web link: the candidates for the site
/// signal's app list, before `SiteSignalSettings.candidates` sorts and ticks them.
enum WebLinkApps {
    static func current() -> [(bundleID: String, name: String)] {
        var seen: Set<String> = []
        return NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://example.com")!).compactMap { url in
            guard let id = Bundle(url: url)?.bundleIdentifier, seen.insert(id).inserted else { return nil }
            return (id, url.deletingPathExtension().lastPathComponent)
        }
    }
}
