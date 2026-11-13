import Foundation

/// How an app is told apart on a strip or a chart when every app wears the one
/// app-use accent: by a divider where the app changes, and by its icon where
/// there is room. Pure, so the rules are tested without a window.
enum AppMarkLayout {
    /// Points at 100% zoom. Icon size and the room kept clear around it.
    static let iconPoints = 16.0
    static let paddingPoints = 4.0

    /// An icon fits when both sides hold the icon and its padding on both
    /// ends. Anything narrower leaves the app to the hover tooltip.
    static func showsIcon(width: Double, height: Double = .infinity, scale: Double) -> Bool {
        let needed = (iconPoints + 2 * paddingPoints) * scale
        return width >= needed && height >= needed
    }

    /// Where a divider is drawn, as a cell offset from the strip's start: at
    /// each boundary where the app changes, none at either end. A run is cut
    /// at every stretch boundary, so one app often spans several runs; a
    /// divider inside it read as a switch that never happened.
    static func dividerCells(_ runs: [SessionShape.Run]) -> [Int] {
        var offsets: [Int] = []
        var cells = 0
        for (run, next) in zip(runs, runs.dropFirst()) {
            cells += run.cells
            if run.bundleID != next.bundleID { offsets.append(cells) }
        }
        return offsets
    }

    /// One unbroken stretch of the strip in one app: where its icon goes.
    struct Streak: Equatable {
        let bundleID: String
        let startCell: Int
        let cells: Int
    }

    /// Neighbouring runs of the same app joined, so the app's icon is drawn
    /// once, centred on all of it, not once per run. Gaps carry no icon.
    static func streaks(_ runs: [SessionShape.Run]) -> [Streak] {
        var streaks: [Streak] = []
        var cell = 0
        var previous: String?
        for run in runs {
            if let id = run.bundleID, !run.isGap {
                if previous == id, let last = streaks.last {
                    streaks[streaks.count - 1] = Streak(bundleID: id, startCell: last.startCell,
                                                        cells: last.cells + run.cells)
                } else {
                    streaks.append(Streak(bundleID: id, startCell: cell, cells: run.cells))
                }
                previous = id
            } else {
                previous = nil
            }
            cell += run.cells
        }
        return streaks
    }
}
