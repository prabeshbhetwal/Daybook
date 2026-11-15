import AppKit
import SwiftUI

/// Checks for the History grid view that draws the day cells.
enum HistoryGridViewChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("The readout names the day and its focus", readoutWords),
        ("The legend states its steps in hours", legendWords),
        ("Month blocks wrap by whole months, six to a row", wholeMonthRows),
        ("A block speaks its month, its total and each recorded day", blockSpeech),
        ("Weekday letters sit beside the first row of months only", lettersBesideFirstRow),
        ("The grid draws inside its column at 980 and at 160% zoom", drawsInsideColumn),
        ("A period with no days in the grid dims nothing", dimsOnlyAPeriodInTheGrid)
    ]

    // MARK: - Fixtures

    private static let calendar = HistoryTreeChecks.calendar
    /// Sunday 15 November 2026.
    private static let today = HistoryTreeChecks.date(11, 15)

    /// From 20 October: nine November days of focus, 61h 10m in all, with
    /// Thursday 12 November at 9h 20m and today at 1h 5m so far.
    private static let autumn: [HistoryDay] = [HistoryTreeChecks.row(10, 20, focused: 3_600, sessions: 1)]
        + [3, 4, 5, 6, 9, 10, 11].map { HistoryTreeChecks.row(11, $0, focused: 26_100, sessions: 1) }
        + [HistoryTreeChecks.row(11, 12, focused: 33_600, sessions: 2),
           HistoryTreeChecks.row(11, 15, focused: 3_900, sessions: 1)]

    /// Twelve months, December 2025 to November 2026.
    private static let year: [HistoryDay] = [HistoryTreeChecks.row(12, 1, year: 2025, focused: 3_600, sessions: 1)] + autumn

    private static func grid(_ days: [HistoryDay]) -> HistoryDayGrid? {
        let top = HistoryTreeBuilder.top(days: days, today: today, calendar: calendar)
        return HistoryDayGridBuilder.grid(top: top, byDate: HistoryTreeBuilder.index(days, calendar: calendar),
                                          calendar: calendar)
    }

    private static func cell(on day: Date, in grid: HistoryDayGrid) -> HistoryGridCell? {
        grid.blocks.flatMap(\.cells).first { $0.day == day }
    }

    @MainActor private static func view(_ grid: HistoryDayGrid) -> HistoryDayGridView {
        HistoryDayGridView(grid: grid, link: HistoryGridLink(), focusedSpan: nil,
                           onPickDay: { _ in }, onPickMonth: { _ in }, calendar: calendar)
    }

    // MARK: - Words

    private static func readoutWords() -> [String] {
        var problems: [String] = []
        guard let grid = grid(autumn) else { return ["the autumn record drew no grid"] }
        let quietToday = HistoryGridCell(day: today, focused: 0, kind: .recorded(.none), isToday: true)
        let cases: [(HistoryGridCell?, String)] = [
            (cell(on: HistoryTreeChecks.date(11, 12), in: grid), "Thu 12 Nov · 9h 20m"),
            (cell(on: today, in: grid), "Sun 15 Nov (today) · 1h 5m so far"),
            (quietToday, "Sun 15 Nov (today) · no focus yet"),
            (cell(on: HistoryTreeChecks.date(11, 2), in: grid), "Mon 2 Nov · no focus"),
            (cell(on: HistoryTreeChecks.date(11, 16), in: grid), "Mon 16 Nov · still to come")
        ]
        for (cell, want) in cases {
            guard let cell else { problems.append("no cell for \"\(want)\""); continue }
            let got = HistoryGridWords.readout(cell, calendar: calendar)
            expect(got == want, "the readout says \"\(want)\", got \"\(got)\"", &problems)
        }
        return problems
    }

    private static func legendWords() -> [String] {
        var problems: [String] = []
        let words = HistoryGridWords.legend.map(\.1)
        let want = ["none", "under 2h", "2 to 5h", "5 to 8h", "8h or more", "still to come"]
        expect(words == want, "the legend reads \(want), got \(words)", &problems)
        let steps = HistoryGridWords.legend.map(\.0)
        expect(steps == HistoryFocusStep.allCases.map { Optional($0) } + [nil],
               "each legend word names its step in order, got \(steps)", &problems)
        return problems
    }

    private static func wholeMonthRows() -> [String] {
        var problems: [String] = []
        let widths = [CGFloat](repeating: 100, count: 12)
        func rows(_ width: CGFloat) -> [Range<Int>] {
            HistoryDayGridView.rows(blockWidths: widths, fitting: width, gap: 14, mostPerRow: 6)
        }
        let seven = rows(7 * 100 + 6 * 14)
        expect(seven == [0..<6, 6..<12], "room for seven still puts six in a row, got \(seven)", &problems)
        let four = rows(4 * 100 + 3 * 14)
        expect(four == [0..<4, 4..<8, 8..<12], "room for four gives three rows of four, got \(four)", &problems)
        let narrow = rows(50)
        expect(narrow == (0..<12).map { $0..<($0 + 1) },
               "a width under one block gives one block per row, got \(narrow)", &problems)
        return problems
    }

    private static func blockSpeech() -> [String] {
        var problems: [String] = []
        guard let november = grid(autumn)?.blocks.last else { return ["the autumn record drew no grid"] }
        let label = HistoryGridWords.blockLabel(november, calendar: calendar)
        expect(label == "November 2026", "the block is named \"November 2026\", got \"\(label)\"", &problems)
        let value = HistoryGridWords.blockValue(november)
        expect(value == "61 hours 10 minutes across 9 days",
               "the block's value is \"61 hours 10 minutes across 9 days\", got \"\(value)\"", &problems)
        if let thursday = november.cells.first(where: { $0.day == HistoryTreeChecks.date(11, 12) }) {
            let spoken = HistoryGridWords.spokenDay(thursday, calendar: calendar)
            expect(spoken == "Thursday 12 November, 9 hours 20 minutes",
                   "12 November is spoken \"Thursday 12 November, 9 hours 20 minutes\", got \"\(spoken)\"", &problems)
        } else {
            problems.append("November has no cell for the 12th")
        }
        let children = HistoryDayGridView.recordedCells(november).map(\.day)
        let toCome = november.cells.filter { $0.kind == .toCome }.map(\.day)
        expect(!toCome.isEmpty, "the fixture has days to come in November", &problems)
        expect(children.count == 15 && Set(children).isDisjoint(with: toCome),
               "November's children are its 15 recorded days and no day to come, got \(children.count)", &problems)
        return problems
    }

    // MARK: - Rendered

    /// Every view is placed this far in from the canvas's top-left corner.
    private static let margin: CGFloat = 20

    private static func lettersBesideFirstRow() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let grid = grid(year) else { return ["the year record drew no grid"] }
            expect(grid.blocks.count == 12, "the fixture draws twelve months, got \(grid.blocks.count)", &problems)
            let width: CGFloat = 900
            let frame = StoryWorkspaceChecks.renderFrame(view(grid).frame(width: width, alignment: .leading)
                                                             .padding(margin), width: width + 2 * margin, height: 500)
            guard let bitmap = frame.bitmap else { return problems + ["the grid drew nothing"] }
            // The gutter left of the blocks. Inked there, top to bottom: M, W
            // and F beside the first row, then the first letters of the legend
            // and the readout under the grid. Letters beside the second row too
            // would make eight.
            let runs = inkRuns(bitmap, canvasWidth: width + 2 * margin, columns: margin..<(margin + 9))
            expect(runs == 5, "the gutter holds M, W, F, the legend and the readout (5 marks), got \(runs)", &problems)
            return problems
        }
    }

    private static func drawsInsideColumn() -> [String] {
        MainActor.assumeIsolated {
            var problems: [String] = []
            guard let grid = grid(year) else { return ["the year record drew no grid"] }
            for (zoom, column) in [(100, 940), (160, 940), (160, 400)] as [(Int, CGFloat)] {
                InterfaceZoomChecks.withZoom(zoom) {
                    // Wider than the column, so a grid that overflows it shows.
                    let canvas = column + 2 * margin + 300
                    let frame = StoryWorkspaceChecks.renderFrame(view(grid).frame(width: column, alignment: .leading)
                                                                     .padding(margin), width: canvas, height: 1_200)
                    expect(frame.evidence.contains(.historyGrid), "at \(zoom)% the grid carries its evidence", &problems)
                    guard let box = drawnBox(frame, canvasWidth: canvas) else {
                        problems.append("at \(zoom)% the grid drew nothing"); return
                    }
                    expect(box.minX >= margin - 1 && box.maxX <= margin + column + 1,
                           "at \(zoom)% the grid stays within its \(Int(column))pt column, drew \(box)", &problems)
                }
            }
            return problems
        }
    }

    private static func dimsOnlyAPeriodInTheGrid() -> [String] {
        var problems: [String] = []
        guard let grid = grid(autumn) else { return ["the autumn record drew no grid"] }
        let days = grid.blocks.flatMap(\.cells).map(\.day)
        let lastYear = HistoryTreeBuilder.period(.year, containing: HistoryTreeChecks.date(6, 1, year: 2025), calendar: calendar)
        expect(!days.contains { HistoryDayGridView.isDimmed($0, by: nil, in: grid) },
               "with no period pointed at, no day is dimmed", &problems)
        expect(!days.contains { HistoryDayGridView.isDimmed($0, by: lastYear, in: grid) },
               "a year before the grid dims no day", &problems)
        let october = HistoryTreeBuilder.period(.month, containing: HistoryTreeChecks.date(10, 20), calendar: calendar)
        expect(HistoryDayGridView.isDimmed(HistoryTreeChecks.date(11, 12), by: october, in: grid),
               "October lowers a November day", &problems)
        expect(!HistoryDayGridView.isDimmed(HistoryTreeChecks.date(10, 20), by: october, in: grid),
               "October keeps an October day", &problems)
        return problems
    }

    // MARK: - Pixels

    private static func inked(_ bitmap: NSBitmapImageRep, _ x: Int, _ y: Int, ground: NSColor) -> Bool {
        guard let colour = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
        return abs(colour.redComponent - ground.redComponent) > 0.04
            || abs(colour.greenComponent - ground.greenComponent) > 0.04
            || abs(colour.blueComponent - ground.blueComponent) > 0.04
    }

    /// Separate stretches of inked pixel rows within `columns` (in points).
    private static func inkRuns(_ bitmap: NSBitmapImageRep, canvasWidth: CGFloat, columns: Range<CGFloat>) -> Int {
        guard let ground = bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB) else { return 0 }
        let scale = CGFloat(bitmap.pixelsWide) / canvasWidth
        let xs = Int(columns.lowerBound * scale)..<Int(columns.upperBound * scale)
        var runs = 0
        var wasInked = false
        for y in 0..<bitmap.pixelsHigh {
            let isInked = xs.contains { inked(bitmap, $0, y, ground: ground) }
            if isInked && !wasInked { runs += 1 }
            wasInked = isInked
        }
        return runs
    }

    /// The rectangle, in points, of everything drawn, as `ComponentEdgeChecks` measures it.
    private static func drawnBox(_ frame: StoryRenderedFrame, canvasWidth: CGFloat) -> CGRect? {
        guard let bitmap = frame.bitmap, let ground = bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB) else { return nil }
        let scale = CGFloat(bitmap.pixelsWide) / canvasWidth
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide where inked(bitmap, x, y, ground: ground) {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                      width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
    }
}
