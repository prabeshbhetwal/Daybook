import AppKit
import SwiftUI

/// Settings sizes with the zoom: the slider reaches every zoom step, and the
/// window's minimum still fits a laptop screen at the largest zoom.
enum SettingsSizingChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The zoom slider reaches every zoom step, the largest included", sliderReachesEveryStep),
        ("The Settings window fits a laptop screen at the largest zoom", settingsFitsLaptopAtLargestZoom),
        ("A zoomed Settings window grows no wider than its page", settingsWindowStopsAtPage),
        ("The menu bar panel's footer fits the panel at every zoom", popoverFooterFits),
        ("The Settings window has no green button and no full screen", settingsWindowCannotZoom),
    ]

    /// With the width capped, the green button could only shrink Settings.
    private static func settingsWindowCannotZoom() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .running)
            defer { FixtureFactory.cleanUp() }
            let settings = SettingsModel(store: store.engine.store, isTrackingEnabled: true,
                                         onChange: {}, onTrackingChanged: { _ in })
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.fullScreenPrimary]
            window.contentView = NSHostingView(rootView: SettingsWindowContent(
                settings: settings, navigation: MainWindowModel(store: store), store: store))
            window.contentView?.layoutSubtreeIfNeeded()
            var problems: [String] = []
            expect(window.standardWindowButton(.zoomButton)?.isEnabled == false,
                   "the green button should be off", &problems)
            expect(window.collectionBehavior.contains(.fullScreenNone)
                   && !window.collectionBehavior.contains(.fullScreenPrimary),
                   "the window should not offer full screen, has \(window.collectionBehavior.rawValue)", &problems)
            return problems
        }
    }

    /// The green button asked for a 1,900-point window and got one, with
    /// empty bands either side of the 720-point page.
    private static func settingsWindowStopsAtPage() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .running)
            defer { FixtureFactory.cleanUp() }
            let settings = SettingsModel(store: store.engine.store, isTrackingEnabled: true,
                                         onChange: {}, onTrackingChanged: { _ in })
            let host = NSHostingController(rootView: SettingsWindowContent(
                settings: settings, navigation: MainWindowModel(store: store), store: store))
            let width = host.sizeThatFits(in: CGSize(width: 3_000, height: 2_000)).width
            var problems: [String] = []
            expect(width <= SettingsLayout.maximumWindowWidth + 0.5,
                   "a 3,000-point offer should stop at \(SettingsLayout.maximumWindowWidth), got \(width)", &problems)
            expect(SettingsLayout.maximumWindowWidth >= SettingsLayout.minimumWindowWidth,
                   "the maximum width should not undercut the minimum", &problems)
            return problems
        }
    }

    /// Four destinations truncated to "Check for Upd…" in the 340-point panel.
    private static func popoverFooterFits() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            for percent in InterfaceZoom.percents {
                let (needed, room) = InterfaceZoomChecks.withZoom(percent) { () -> (CGFloat, CGFloat) in
                    let metrics = PopoverMetrics.fitting(CGSize(width: 1_440, height: 900))
                    let host = NSHostingView(rootView: PopoverFooter(onOpenApplication: {}, onOpenSettings: {}))
                    return (host.fittingSize.width, metrics.width - metrics.outerPadding * 2)
                }
                expect(needed <= room, "at \(percent)% the footer needs \(needed) points, the panel has \(room)", &problems)
            }
            return problems
        }
    }

    /// Walks the slider's range in its own step, the way the slider does, and
    /// expects to land on every step. In scales the walk stopped at 130%.
    private static func sliderReachesEveryStep() -> [String] {
        var problems: [String] = []
        let range = ZoomControl.sliderRange
        let stops = Array(stride(from: range.lowerBound, through: range.upperBound, by: ZoomControl.sliderStep))
        let reached = Set(stops.map { InterfaceZoom.nearestPercent(toScale: $0 / 100) })
        for percent in InterfaceZoom.percents {
            expect(reached.contains(percent), "the slider should stop at \(percent)%, stops at \(reached.sorted())", &problems)
        }
        expect(stops.last == range.upperBound,
               "the slider's last stop should be its top, \(range.upperBound), got \(String(describing: stops.last))",
               &problems)
        expect((InterfaceZoom.percents.last ?? 0) > 130,
               "zoom should go past 130%, tops out at \(String(describing: InterfaceZoom.percents.last))%", &problems)
        return problems
    }

    /// A 14-inch MacBook Pro's default visible area, less the menu bar and the
    /// margin every window keeps to the screen edge.
    private static func settingsFitsLaptopAtLargestZoom() -> [String] {
        var problems: [String] = []
        let visible = CGSize(width: 1_512 - InterfaceZoom.screenMargin, height: 945 - 37 - InterfaceZoom.screenMargin)
        let largest = InterfaceZoom.percents[InterfaceZoom.percents.count - 1]
        let (width, height, sidebar) = InterfaceZoomChecks.withZoom(largest) {
            (SettingsLayout.minimumWindowWidth, SettingsLayout.minimumWindowHeight, SettingsLayout.sidebarWidth)
        }
        expect(width <= visible.width, "the minimum width at \(largest)% should fit \(visible.width), got \(width)", &problems)
        expect(height <= visible.height, "the minimum height at \(largest)% should fit \(visible.height), got \(height)", &problems)
        expect(width - sidebar >= 400,
               "the page beside the sidebar should keep 400 points to read, got \(width - sidebar)", &problems)
        return problems
    }
}
