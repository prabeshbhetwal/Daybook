import SwiftUI

/// History's first view: a block of day cells per month, each shaded by the
/// focus it held, then a legend and a one-line readout of the day pointed at.
/// Pointing at a month, or at a row of the tree, lowers the days outside it.
struct HistoryDayGridView: View {
    let grid: HistoryDayGrid
    @ObservedObject var link: HistoryGridLink
    let focusedSpan: DateInterval?       // the row keyboard focus is on
    let onPickDay: (Date) -> Void
    let onPickMonth: (DateInterval) -> Void
    /// Names days in the zone the grid was built in.
    var calendar: Calendar = HistoryTreeBuilder.calendar()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    static let mostPerRow = 6

    private var cellSize: CGFloat { 12.zoomed }
    private var gap: CGFloat { 3.zoomed }
    private var blockGap: CGFloat { 14.zoomed }

    /// Whole blocks per row, oldest first: a row takes blocks while they fit
    /// `width` and number under `mostPerRow`, and always at least one, so a
    /// block never shrinks.
    static func rows(blockWidths: [CGFloat], fitting width: CGFloat, gap: CGFloat, mostPerRow: Int) -> [Range<Int>] {
        var rows: [Range<Int>] = []
        var start = 0
        var used: CGFloat = 0
        for (index, blockWidth) in blockWidths.enumerated() {
            if index > start, index - start >= mostPerRow || used + gap + blockWidth > width {
                rows.append(start..<index)
                start = index
                used = blockWidth
            } else {
                used += (index > start ? gap : 0) + blockWidth
            }
        }
        if start < blockWidths.count { rows.append(start..<blockWidths.count) }
        return rows
    }

    /// Whether a drawn day is lowered: only when `span` holds at least one
    /// drawn day of the grid and this day is outside it.
    static func isDimmed(_ day: Date, by span: DateInterval?, in grid: HistoryDayGrid) -> Bool {
        guard let span else { return false }
        let inside = { (date: Date) in date >= span.start && date < span.end }
        guard !inside(day) else { return false }
        return grid.blocks.contains { $0.cells.contains { inside($0.day) } }
    }

    /// The days a block offers as buttons: every recorded day, none to come.
    static func recordedCells(_ block: HistoryGridBlock) -> [HistoryGridCell] {
        block.cells.filter { $0.kind != .toCome }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack(alignment: .top, spacing: gap) {
                weekdayLetters
                GridFlow(spacing: blockGap, mostPerRow: Self.mostPerRow) {
                    ForEach(grid.blocks) { monthBlock($0) }
                }
            }
            legend
            Text(readout)
                .font(Tokens.Typography.body)
                .monospacedDigit()
                .foregroundStyle(StoryStyle.supportingInk)
                .lineLimit(1)
        }
        .storyRenderEvidence(.historyGrid)
    }

    /// Beside the first row of blocks only: later rows sit under the first.
    private var weekdayLetters: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text(" ").font(Tokens.Typography.caption)   // the month label's line
            VStack(spacing: gap) {
                ForEach(Array(HistoryDayGridBuilder.weekdayLetters.enumerated()), id: \.offset) { _, letter in
                    Text(letter)
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(StoryStyle.supportingInk)
                        .frame(height: cellSize)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func monthBlock(_ block: HistoryGridBlock) -> some View {
        let columns = (block.leadingBlanks + block.cells.count + 6) / 7
        return VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text(HistoryGridWords.monthLabel(block, calendar: calendar))
                .font(Tokens.Typography.caption)
                .foregroundStyle(StoryStyle.supportingInk)
                .contentShape(Rectangle())
                .onTapGesture { onPickMonth(block.month) }
            HStack(alignment: .top, spacing: gap) {
                ForEach(0..<columns, id: \.self) { column in
                    VStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { row in
                            let index = column * 7 + row - block.leadingBlanks
                            if block.cells.indices.contains(index) {
                                dayCell(block.cells[index])
                            } else {
                                Color.clear.frame(width: cellSize, height: cellSize)
                            }
                        }
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in
            if inside {
                link.span = block.month
            } else {
                if link.span == block.month { link.span = nil }
                if let day = link.day, block.month.contains(day) { link.day = nil }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HistoryGridWords.blockLabel(block, calendar: calendar))
        .accessibilityValue(HistoryGridWords.blockValue(block))
        .accessibilityChildren {
            ForEach(Self.recordedCells(block), id: \.day) { cell in
                Button(HistoryGridWords.spokenDay(cell, calendar: calendar)) { onPickDay(cell.day) }
            }
        }
    }

    private func dayCell(_ cell: HistoryGridCell) -> some View {
        let shape = RoundedRectangle(cornerRadius: 3.zoomed, style: .continuous)
        let dimmed = Self.isDimmed(cell.day, by: link.span ?? focusedSpan, in: grid)
        return ZStack {
            switch cell.kind {
            case .toCome:
                shape.strokeBorder(FocusRamp.toCome, lineWidth: 1)
            case .recorded(let step):
                shape.fill(FocusRamp.fill(step))
                if step != .none, contrast == .increased {
                    shape.strokeBorder(Tokens.Colour.line, lineWidth: 1)
                }
            }
            if cell.isToday { shape.strokeBorder(Color.primary, lineWidth: 1.5.zoomed) }
        }
        .frame(width: cellSize, height: cellSize)
        .opacity(dimmed ? 0.4 : 1)
        .animation(Tokens.Motion.animation(Tokens.Motion.hover, reduceMotion: reduceMotion), value: dimmed)
        .contentShape(Rectangle())
        // Leaving a cell keeps it in the readout until the pointer leaves the
        // month, so crossing the gap between two cells does not flicker.
        .onHover { inside in if inside { link.day = cell.day } }
        .onTapGesture { if cell.kind != .toCome { onPickDay(cell.day) } }
    }

    private var legend: some View {
        GridFlow(spacing: Tokens.Space.s, mostPerRow: .max) {
            Text("Focus in a day")
            ForEach(Array(HistoryGridWords.legend.enumerated()), id: \.offset) { _, item in
                HStack(spacing: Tokens.Space.xs) {
                    swatch(item.0)
                    Text(item.1)
                }
            }
        }
        .font(Tokens.Typography.caption)
        .foregroundStyle(StoryStyle.supportingInk)
    }

    @ViewBuilder private func swatch(_ step: HistoryFocusStep?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 3.zoomed, style: .continuous)
        Group {
            if let step { shape.fill(FocusRamp.fill(step)) } else { shape.strokeBorder(FocusRamp.toCome, lineWidth: 1) }
        }
        .frame(width: cellSize, height: cellSize)
    }

    /// The day pointed at; at rest today, or the last day drawn when today is not in the grid.
    private var readout: String {
        let cells = grid.blocks.flatMap(\.cells)
        let shown = link.day.flatMap { day in cells.first { $0.day == day } }
            ?? cells.first(where: \.isToday) ?? cells.last
        return shown.map { HistoryGridWords.readout($0, calendar: calendar) } ?? ""
    }
}

/// Lays its views out left to right in rows that wrap between whole views,
/// using `HistoryDayGridView.rows`, so a view keeps its own size.
private struct GridFlow: Layout {
    let spacing: CGFloat
    let mostPerRow: Int

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        frames(fitting: proposal.width, subviews).reduce(CGRect.zero) { $0.union($1) }.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (frame, subview) in zip(frames(fitting: bounds.width, subviews), subviews) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(frame.size))
        }
    }

    private func frames(fitting width: CGFloat?, _ subviews: Subviews) -> [CGRect] {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var frames: [CGRect] = []
        var y: CGFloat = 0
        for row in HistoryDayGridView.rows(blockWidths: sizes.map(\.width), fitting: width ?? .infinity,
                                           gap: spacing, mostPerRow: mostPerRow) {
            var x: CGFloat = 0
            for index in row {
                frames.append(CGRect(origin: CGPoint(x: x, y: y), size: sizes[index]))
                x += sizes[index].width + spacing
            }
            y += (row.map { sizes[$0].height }.max() ?? 0) + spacing
        }
        return frames
    }
}
