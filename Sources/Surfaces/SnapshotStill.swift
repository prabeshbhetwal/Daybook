import SwiftUI
import AppKit

private struct RendersStillKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while `Snapshotter` draws a PNG. A view that changes on a timer
    /// holds one state then: when a still is taken must not change what it
    /// shows. The product never sets it.
    var rendersStill: Bool {
        get { self[RendersStillKey.self] }
        set { self[RendersStillKey.self] = newValue }
    }
}

extension Snapshotter {
    /// How long the image must stay the same before it is taken, and the
    /// longest a still waits for that.
    static let stillFrameInterval: TimeInterval = 0.05
    static let stillFramesUnchanged = 3
    static let stillWaitLimit: TimeInterval = 6

    /// Overlay scrollers in every still. With a mouse attached, AppKit swaps
    /// overlay scrollers for ones that take room a second or two after the
    /// process starts, which narrowed whatever was being drawn at the time.
    /// The argument domain lives in memory; no preferences are written.
    static func pinStillScrollers() {
        var arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        arguments["AppleShowScrollBars"] = "WhenScrolling"
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
    }

    static func render<V: View>(_ view: V, appearance: SnapshotAppearance,
                                to url: URL) -> Bool {
        guard let png = stillPNG(of: view, appearance: appearance, name: url.lastPathComponent) else {
            return false
        }
        do {
            try png.write(to: url)
            return true
        } catch {
            return false
        }
    }

    /// The view as a PNG, taken once it has stopped changing. Work started in
    /// `onAppear`, a scroll anchor and a loaded list land a few run-loop turns
    /// after the first layout, and a fixed short wait caught them in some
    /// runs and not others. Animations are off, so nothing is caught part way.
    static func stillPNG<V: View>(of view: V, appearance: SnapshotAppearance,
                                  name: String = "still") -> Data? {
        // ImageRenderer substitutes yellow prohibition placeholders for native
        // controls. Host the real AppKit-backed view offscreen instead. This
        // captures our own view, not the user's screen, and needs no permission.
        let host = NSHostingView(rootView: view
            .environment(\.rendersStill, true)
            .transaction { transaction in
                transaction.disablesAnimations = true
                transaction.animation = nil
            })
        let size = host.fittingSize
        guard size.width > 0, size.height > 0 else { return nil }
        let frame = NSRect(origin: .zero, size: size)
        let window = StillWindow(contentRect: frame, styleMask: [.borderless],
                                 backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.contentView = host
        host.frame = frame
        window.orderFront(nil)
        defer { window.orderOut(nil); window.close() }

        // Compared at one pixel per point: drawing the full-resolution image
        // takes most of a second, and it is drawn once, at the end.
        let deadline = Date().addingTimeInterval(stillWaitLimit)
        var previous: Data?
        var unchanged = 0
        while unchanged < stillFramesUnchanged {
            RunLoop.current.run(until: Date().addingTimeInterval(stillFrameInterval))
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            guard let next = pointPixels(of: host) else { return nil }
            unchanged = next == previous ? unchanged + 1 : 0
            previous = next
            if Date() > deadline {
                FileHandle.standardError.write(Data("\(name) was still changing after \(Int(stillWaitLimit)) s\n".utf8))
                break
            }
        }
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func pointPixels(of view: NSView) -> Data? {
        let size = view.bounds.size
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                            pixelsWide: Int(size.width.rounded(.up)),
                                            pixelsHigh: Int(size.height.rounded(.up)),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0),
              let pixels = bitmap.bitmapData else { return nil }
        bitmap.size = size
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return Data(bytes: pixels, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }
}

/// A still's window keeps text fields out of focus. Focus lands some turns
/// after the first layout, and a focused field's cursor blinks, so a still
/// showed a focused field in some runs and not in others.
private final class StillWindow: NSWindow {
    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        if responder is NSTextField || responder is NSText { return false }
        return super.makeFirstResponder(responder)
    }
}
