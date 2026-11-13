import Foundation

/// Settings sizes with the zoom: the slider reaches every zoom step, and the
/// window's minimum still fits a laptop screen at the largest zoom.
enum SettingsSizingChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The zoom slider reaches every zoom step, the largest included", sliderReachesEveryStep),
        ("The Settings window fits a laptop screen at the largest zoom", settingsFitsLaptopAtLargestZoom),
    ]

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
