import CoreGraphics
import Foundation

/// A window's minimum follows the zoom but never outgrows its screen, a
/// window left below the new minimum grows without leaving the screen, and
/// whatever follows the zoom hears of each change once.
enum ZoomWindowChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The window's minimum grows with the zoom but never past the screen", minimumCapped),
        ("A window grows to the new minimum and stays on screen", windowGrowsOnScreen),
        ("A zoom change reaches each follower once, and a released follower hears nothing", followerFires),
    ]

    private static func close(_ actual: CGSize, _ expected: CGSize) -> Bool {
        abs(actual.width - expected.width) < 0.001 && abs(actual.height - expected.height) < 0.001
    }

    private static func close(_ actual: CGRect, _ expected: CGRect) -> Bool {
        abs(actual.minX - expected.minX) < 0.001 && abs(actual.minY - expected.minY) < 0.001
            && close(actual.size, expected.size)
    }

    private static func minimumCapped() -> [String] {
        var problems: [String] = []
        let base = CGSize(width: 980, height: 680)
        let roomy = CGSize(width: 2_560, height: 1_400)
        let laptop = CGSize(width: 1_470, height: 900)
        let cases: [(CGFloat, CGSize, CGSize)] = [
            (1.4, roomy, CGSize(width: 1_372, height: 952)),
            (1.4, laptop, CGSize(width: 1_372, height: 860)),
            (0.8, roomy, CGSize(width: 784, height: 544)),
            (1.4, CGSize(width: 1_200, height: 1_000), CGSize(width: 1_160, height: 952)),
            (1, CGSize(width: CGFloat.infinity, height: CGFloat.infinity), base),
        ]
        for (scale, visible, expected) in cases {
            let got = InterfaceZoom.windowMinimum(base: base, scale: scale, visible: visible)
            expect(close(got, expected),
                   "scale \(scale) on \(visible) should give \(expected), got \(got)", &problems)
        }
        return problems
    }

    private static func windowGrowsOnScreen() -> [String] {
        var problems: [String] = []
        // AppKit coordinates, bottom-up: the top edge is minY + height.
        let visible = CGRect(x: 0, y: 0, width: 1_470, height: 900)
        let minimum = CGSize(width: 1_372, height: 860)
        let cases: [(CGRect, CGRect)] = [
            (CGRect(x: 100, y: 100, width: 1_000, height: 700), CGRect(x: 98, y: 0, width: 1_372, height: 860)),
            (CGRect(x: 400, y: 150, width: 1_000, height: 700), CGRect(x: 98, y: 0, width: 1_372, height: 860)),
            // Already at least the minimum: untouched, even where it is wider than the screen.
            (CGRect(x: 0, y: 200, width: 1_500, height: 900), CGRect(x: 0, y: 200, width: 1_500, height: 900)),
            // Only the short side grows; the wide one is not touched.
            (CGRect(x: 50, y: 100, width: 1_400, height: 700), CGRect(x: 50, y: 0, width: 1_400, height: 860)),
        ]
        for (frame, expected) in cases {
            let got = InterfaceZoom.grownFrame(frame, toFit: minimum, within: visible)
            expect(close(got, expected), "\(frame) should become \(expected), got \(got)", &problems)
        }
        return problems
    }

    /// The main queue has to turn between changes: a follower hops to it
    /// before it calls back.
    private static func drain() {
        for _ in 0..<3 { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    }

    private static func followerFires() -> [String] {
        var problems: [String] = []
        InterfaceZoomChecks.withZoom(100) {
            var calls = 0
            var follower: ZoomFollower? = ZoomFollower { calls += 1 }
            ZoomModel.shared.apply(percent: 120)
            drain()
            expect(calls == 1, "one change should reach the follower once, got \(calls) calls", &problems)
            ZoomModel.shared.apply(percent: 140)
            drain()
            expect(calls == 2, "a second change should make two calls in all, got \(calls)", &problems)
            follower = nil
            ZoomModel.shared.apply(percent: 90)
            drain()
            expect(calls == 2, "a released follower should hear nothing, got \(calls) calls", &problems)
            _ = follower
        }
        return problems
    }
}
