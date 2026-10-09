import AppKit
import Foundation
import SwiftUI

/// Settings lines its controls up the way System Settings does, and its sheet
/// keeps Close in one place. These break if a row's control is given a width
/// of its own again (a pop-up draws at its widest item whatever width it is
/// offered, so a wider frame centred it and each row's control ended at a
/// different place), or if a view joins Close in the title band's stack.
enum SettingsAlignmentChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Every Sessions setting's control ends at the same trailing edge", sessionsControlsAlign),
        ("A sheet's Close stays put while a form inside it is open", closeStaysPut),
    ]

    private static func closeStaysPut() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            @MainActor func titleBand(formOpen: Bool) -> NSBitmapImageRep? {
                let form = formOpen ? OpenInlineForm(name: "category", cancel: {}) : nil
                return render(StorySheet(title: "Settings", onClose: {}) {
                    Color.clear.preference(key: OpenInlineFormKey.self, value: form)
                }, width: 600, height: 120)
            }
            guard let closed = titleBand(formOpen: false), let open = titleBand(formOpen: true) else {
                return ["the sheet did not render"]
            }
            let changed = differingPixels(closed, open)
            expect(changed == 0, "the title band is drawn the same with a form open, \(changed) pixels moved",
                   &problems)
            return problems
        }
    }

    @MainActor private static func render<V: View>(_ view: V, width: CGFloat,
                                                   height: CGFloat) -> NSBitmapImageRep? {
        let host = hosted(view.frame(width: width, height: height), width: width, height: height)
        defer { host.window?.orderOut(nil); host.window?.close() }
        host.displayIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    private static func differingPixels(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> Int {
        guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh else { return Int.max }
        var count = 0
        for y in 0..<a.pixelsHigh {
            for x in 0..<a.pixelsWide where a.colorAt(x: x, y: y) != b.colorAt(x: x, y: y) {
                count += 1
            }
        }
        return count
    }

    /// The view laid out in an offscreen window, given a turn of the run loop
    /// so preferences it raises have reached the views that read them.
    @MainActor private static func hosted<V: View>(_ view: V, width: CGFloat, height: CGFloat) -> NSView {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        host.layoutSubtreeIfNeeded()
        return host
    }

    private static func sessionsControlsAlign() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            let suite = "fc-selftest-settings-alignment-\(UUID().uuidString)"
            guard let defaults = MemoryDefaults.suite(named: suite) else { return ["no isolated preferences"] }
            defer { MemoryDefaults.remove(named: suite) }
            let model = SettingsModel(store: PersistenceStore(defaults: defaults), isTrackingEnabled: true,
                                      onChange: {}, onTrackingChanged: { _ in })
            let edges = controlTrailingEdges(SettingsGroups(model: model, section: .focus))
            // The Goal panel has seven rows, each with one menu.
            expect(edges.count >= 7, "the Goal panel's seven controls are drawn, found \(edges.count)", &problems)
            if let first = edges.min(), let last = edges.max() {
                expect(last - first <= 1, "every control ends at one trailing edge, got \(edges.sorted())",
                       &problems)
            }
            return problems
        }
    }

    /// The trailing edge of each control drawn: the AppKit pop-up where the
    /// system draws one, otherwise the stand-in view SwiftUI gives each
    /// control the keyboard can reach.
    @MainActor private static func controlTrailingEdges<V: View>(_ view: V) -> [CGFloat] {
        let host = hosted(view.frame(width: 760).fixedSize(horizontal: false, vertical: true),
                          width: 760, height: 900)
        defer { host.window?.orderOut(nil); host.window?.close() }

        var frames = Set<[Int]>()
        func walk(_ view: NSView) {
            if view is NSPopUpButton || String(describing: type(of: view)).contains("KeyViewProxy") {
                let rect = view.convert(view.bounds, to: host)
                frames.insert([rect.minX, rect.minY, rect.maxX, rect.maxY].map { Int($0.rounded()) })
            }
            view.subviews.forEach(walk)
        }
        walk(host)
        return frames.map { CGFloat($0[2]) }
    }
}
