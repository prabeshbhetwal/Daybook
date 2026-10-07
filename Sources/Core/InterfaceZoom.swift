import CoreGraphics
import Foundation

/// The interface zoom's steps, as percents: 80 to 140 in tens. Pure, so every
/// reader of a stored or typed value lands on the same step.
enum InterfaceZoom {
    static let percents = [80, 90, 100, 110, 120, 130, 140]
    static let defaultPercent = 100

    /// The step nearest a scale (1.2 is 120%), ties rounding up. A scale
    /// outside the range takes the end step; one that is not a number is 100%.
    static func nearestPercent(toScale scale: Double) -> Int {
        guard scale.isFinite else { return defaultPercent }
        // The scale arrives as a decimal fraction, so 1.15 times 100 is
        // 114.99999999999999: round that error away before breaking the tie.
        let percent = (scale * 100 * 1_000_000).rounded() / 1_000_000
        let clamped = min(max(percent, Double(percents[0])), Double(percents[percents.count - 1]))
        return Int((clamped / 10).rounded(.toNearestOrAwayFromZero)) * 10
    }

    /// A percent moved onto the nearest step.
    static func snapped(_ percent: Int) -> Int {
        nearestPercent(toScale: Double(percent) / 100)
    }

    /// The step `delta` steps from the one nearest `percent`, stopping at the ends.
    static func stepped(_ percent: Int, by delta: Int) -> Int {
        let index = percents.firstIndex(of: snapped(percent)) ?? percents.startIndex
        let reach = min(max(delta, -percents.count), percents.count)
        return percents[min(max(index + reach, 0), percents.count - 1)]
    }

    /// Whether `delta` steps from `percent` land on a different step.
    static func canStep(_ percent: Int, by delta: Int) -> Bool {
        stepped(percent, by: delta) != snapped(percent)
    }

    /// How far native controls move along their size scale: one smaller below
    /// 100%, one larger above 110%, as is between.
    static func controlSizeShift(forPercent percent: Int) -> Int {
        let step = snapped(percent)
        return step < 100 ? -1 : (step > 110 ? 1 : 0)
    }

    /// What a window leaves free of its screen's visible area, so a window at
    /// its minimum never fills the screen edge to edge.
    static let screenMargin: CGFloat = 40

    /// A window's minimum at a zoom: each side is `base` times `scale`, held
    /// to the visible area less `screenMargin` so the window still fits the
    /// screen it opens on. An infinite `visible` leaves a side uncapped.
    static func windowMinimum(base: CGSize, scale: CGFloat, visible: CGSize) -> CGSize {
        CGSize(width: min(base.width * scale, max(visible.width - screenMargin, 0)),
               height: min(base.height * scale, max(visible.height - screenMargin, 0)))
    }

    /// `frame`, grown on any side below `minimum` with its top-left corner
    /// kept, then moved the shortest distance onto `visible`. A frame already
    /// at least `minimum` comes back unchanged: a window never shrinks here.
    /// AppKit coordinates, so the top edge is `maxY`.
    static func grownFrame(_ frame: CGRect, toFit minimum: CGSize, within visible: CGRect) -> CGRect {
        guard frame.width < minimum.width || frame.height < minimum.height else { return frame }
        return resized(frame, to: CGSize(width: max(frame.width, minimum.width),
                                         height: max(frame.height, minimum.height)),
                       within: visible)
    }

    /// `frame` at `size` with its top-left corner kept, then moved the
    /// shortest distance onto `visible`. When it is too big for `visible` the
    /// left and top edges win, so the title bar stays reachable.
    static func resized(_ frame: CGRect, to size: CGSize, within visible: CGRect) -> CGRect {
        var origin = CGPoint(x: frame.minX, y: frame.maxY - size.height)
        origin.x = max(min(origin.x, visible.maxX - size.width), visible.minX)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        return CGRect(origin: origin, size: size)
    }
}
