import SwiftUI
import AppKit

/// bundleID → icon, resolved once and cached. Uninstalled apps still appear in
/// history, so a miss is normal, not an error — verified on this machine, where
/// Xcode is absent and exercises the fallback.
final class AppIconProvider {
    static let shared = AppIconProvider()
    private var cache: [String: NSImage?] = [:]

    /// Rasterised once at the size actually drawn, then the original is dropped.
    ///
    /// `NSWorkspace.icon(forFile:)` hands back an `NSImage` carrying 32
    /// representations up to 2048×2048 — roughly 53 MB per icon if fully decoded.
    /// Caching those whole is what took the app from 17 MB to 49 MB. A 40px
    /// bitmap costs about 6 KB.
    func icon(for bundleID: String, size: CGFloat = 20) -> NSImage? {
        let key = "\(bundleID)@\(Int(size))"
        if let cached = cache[key] { return cached }

        let rasterised: NSImage? = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: bundleID)
            .map { Self.rasterise(NSWorkspace.shared.icon(forFile: $0.path), size: size) }
        cache[key] = rasterised
        return rasterised
    }

    /// The same, for an app known by where it is rather than by its id — the
    /// installed-app lists, which can hold two copies of one bundle.
    /// Kept in an evicting cache: scrolling every installed app would
    /// otherwise pin a thousand icons for the life of the process.
    func icon(forFile path: String, size: CGFloat) -> NSImage {
        let key = "\(path)@\(Int(size))" as NSString
        if let cached = fileCache.object(forKey: key) { return cached }
        let rasterised = Self.rasterise(NSWorkspace.shared.icon(forFile: path), size: size)
        fileCache.setObject(rasterised, forKey: key)
        return rasterised
    }
    private let fileCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 400
        return cache
    }()

    private static func rasterise(_ source: NSImage, size: CGFloat) -> NSImage {
        let target = NSSize(width: size, height: size)
        let image = NSImage(size: target)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: target),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1)
        image.unlockFocus()
        return image
    }
}

struct AppIcon: View {
    let bundleID: String
    var size: CGFloat = 20
    /// Used only for the fallback. An uninstalled app has no icon to load, and
    /// an empty dashed square says nothing about which app it stands for — the
    /// initial at least identifies it.
    var appName: String = ""

    var body: some View {
        Group {
            if let icon = AppIconProvider.shared.icon(for: bundleID, size: size) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                initialTile
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Colour keyed on the bundle id so one app keeps one colour everywhere,
    /// and across launches.
    private var initialTile: some View {
        let source = appName.isEmpty ? bundleID.components(separatedBy: ".").last ?? bundleID
                                     : appName
        let letter = source.first.map(String.init)?.uppercased() ?? "?"
        // NOT `hashValue`: Swift seeds string hashing per process, so the
        // colour would change on every launch. This sum is stable forever.
        let fingerprint = bundleID.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 3_600 }
        let hue = Double(fingerprint % 360) / 360
        return RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(Color(hue: hue, saturation: 0.5, brightness: 0.72))
            .overlay(
                Text(letter)
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

/// Forwarder. Every timeline, bar and chart already asks this by rank or by work
/// type; routing it through `Tokens.Palette` re-skins all of them at once and
/// leaves one definition of each colour.
enum TimelinePalette {
    static func color(_ index: Int) -> Color { Tokens.Palette.app(rank: index) }
    static func color(for workType: WorkType) -> Color { Tokens.Palette.workType(workType) }
    /// Time inside a tracked app but outside any focus session.
    static let untrackedLabel = "Untracked work"
    static let untracked = Tokens.Palette.untracked
}
