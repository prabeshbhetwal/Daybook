import CoreGraphics
import Foundation

/// The interface zoom is held as a step: what is stored or typed snaps to one,
/// the steps stop at both ends, the setting survives a relaunch, and a length
/// written as `N.zoomed` follows the shared zoom.
enum InterfaceZoomChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A stored zoom snaps to a step, and anything unreadable is 100%", storedZoomSnaps),
        ("Zoom steps stop at 80% and 140%", zoomStepsStopAtEnds),
        ("The control-size band shifts below 100% and above 110%", controlBand),
        ("The zoom setting saves, reloads and reaches every window", zoomSettingRoundTrips),
        ("Lengths written as N.zoomed scale with the zoom", zoomedLiterals),
    ]

    /// Runs `body` with the shared zoom at `percent`, then puts it back, even
    /// when the body's checks fail. Every check that moves the zoom goes through it.
    static func withZoom<T>(_ percent: Int, _ body: () -> T) -> T {
        let previous = ZoomModel.shared.percent
        ZoomModel.shared.apply(percent: percent)
        defer { ZoomModel.shared.apply(percent: previous) }
        return body()
    }

    private static func close(_ actual: CGFloat, _ expected: CGFloat) -> Bool {
        abs(actual - expected) < 0.001
    }

    /// The key is written out: it is the name an earlier install's value is found under.
    private static let storedKey = "fc.interfaceZoom"

    private static func storedZoomSnaps() -> [String] {
        var problems: [String] = []
        // Ties round up; 1.15 is the one a plain multiplication gets wrong.
        let scales: [(Double, Int)] = [(1.37, 140), (0.5, 80), (1.25, 130), (1.15, 120), (120, 140),
                                       (-1, 80), (.nan, 100), (.infinity, 100), (-.infinity, 100)]
        for (scale, expected) in scales {
            let got = InterfaceZoom.nearestPercent(toScale: scale)
            expect(got == expected, "scale \(scale) should snap to \(expected)%, got \(got)%", &problems)
        }

        let suite = "fc-selftest-zoom-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return ["no isolated defaults suite"] }
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let store = PersistenceStore(defaults: defaults)
        expect(store.interfaceZoomPercent == 100,
               "no stored zoom should read as 100%, got \(store.interfaceZoomPercent)%", &problems)
        defaults.set("1.2" as String, forKey: storedKey)
        expect(store.interfaceZoomPercent == 100,
               "a stored string should read as 100%, got \(store.interfaceZoomPercent)%", &problems)
        defaults.set(1.2 as Double, forKey: storedKey)
        expect(store.interfaceZoomPercent == 120,
               "a stored 1.2 should read as 120%, got \(store.interfaceZoomPercent)%", &problems)
        store.interfaceZoomPercent = 90
        let written = defaults.object(forKey: storedKey) as? Double
        expect(written == 0.9, "90% should be stored as exactly 0.9, got \(String(describing: written))", &problems)
        return problems
    }

    private static func zoomStepsStopAtEnds() -> [String] {
        var problems: [String] = []
        let moves: [(Int, Int, Int)] = [(140, 1, 140), (80, -1, 80), (100, 1, 110), (105, 1, 120)]
        for (percent, delta, expected) in moves {
            let got = InterfaceZoom.stepped(percent, by: delta)
            expect(got == expected, "\(percent)% stepped by \(delta) should be \(expected)%, got \(got)%", &problems)
        }
        let steps: [(Int, Int, Bool)] = [(140, 1, false), (80, -1, false), (100, 0, false), (110, -1, true)]
        for (percent, delta, expected) in steps {
            let got = InterfaceZoom.canStep(percent, by: delta)
            expect(got == expected, "canStep(\(percent), by: \(delta)) should be \(expected), got \(got)", &problems)
        }
        return problems
    }

    private static func controlBand() -> [String] {
        var problems: [String] = []
        let shifts: [Int: Int] = [80: -1, 90: -1, 100: 0, 110: 0, 120: 1, 130: 1, 140: 1]
        for (percent, expected) in shifts.sorted(by: { $0.key < $1.key }) {
            let got = InterfaceZoom.controlSizeShift(forPercent: percent)
            expect(got == expected, "\(percent)% should shift controls by \(expected), got \(got)", &problems)
        }
        return problems
    }

    private static func zoomSettingRoundTrips() -> [String] {
        var problems: [String] = []
        let suite = "fc-selftest-zoom-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return ["no isolated defaults suite"] }
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        withZoom(100) {
            let store = PersistenceStore(defaults: defaults)
            let settings = SettingsModel(store: store, isTrackingEnabled: true,
                                         onChange: {}, onTrackingChanged: { _ in })
            settings.interfaceZoom = 1.3
            expect(store.interfaceZoomPercent == 130,
                   "1.3 should be stored as 130%, got \(store.interfaceZoomPercent)%", &problems)
            expect(ZoomModel.shared.percent == 130,
                   "every window should be at 130%, got \(ZoomModel.shared.percent)%", &problems)
            let reloaded = SettingsModel(store: PersistenceStore(defaults: defaults), isTrackingEnabled: true,
                                         onChange: {}, onTrackingChanged: { _ in })
            expect(abs(reloaded.interfaceZoom - 1.3) < 0.001,
                   "a new settings model should read 1.3, got \(reloaded.interfaceZoom)", &problems)
            settings.interfaceZoom = 1.26
            expect(store.interfaceZoomPercent == 130,
                   "1.26 should be stored as 130%, got \(store.interfaceZoomPercent)%", &problems)
        }
        return problems
    }

    private static func zoomedLiterals() -> [String] {
        var problems: [String] = []
        withZoom(140) {
            expect(close(10.zoomed, 14), "10.zoomed at 140% should be 14, got \(10.zoomed)", &problems)
            expect(close(12.5.zoomed, 17.5), "12.5.zoomed at 140% should be 17.5, got \(12.5.zoomed)", &problems)
        }
        // At 100% a length is the literal it was written as, bit for bit.
        withZoom(100) {
            expect(12.zoomed == 12, "12.zoomed at 100% should be exactly 12, got \(12.zoomed)", &problems)
            expect(12.5.zoomed == 12.5, "12.5.zoomed at 100% should be exactly 12.5, got \(12.5.zoomed)", &problems)
        }
        return problems
    }
}
