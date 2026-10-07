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
}
