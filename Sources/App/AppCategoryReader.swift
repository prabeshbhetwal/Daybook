import AppKit

/// The category an app declares about itself — `LSApplicationCategoryType`
/// from its Info.plist ("public.app-category.developer-tools" and friends).
/// Self-reported, optional, and often missing outside the App Store (Dia and
/// Chrome declare nothing), so it is a hint of last resort behind
/// `PurposeMap`'s rules and the user's overrides. Cached because the lookup
/// touches the disk, and consulted only for apps the rules do not know.
/// Main-thread only, like every caller of `PurposeMap.purpose`.
final class AppCategoryReader {
    static let shared = AppCategoryReader()
    private var cache: [String: String?] = [:]

    func category(for bundleID: String) -> String? {
        if let cached = cache[bundleID] { return cached }
        let value = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .flatMap { Bundle(url: $0) }
            .flatMap { $0.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String }
        cache[bundleID] = value
        return value
    }
}
