import SwiftUI

/// The day as one band, divided into uniform hour columns. Drawn with `Canvas`
/// rather than Swift Charts because a busy day is several hundred segments and
/// Canvas draws them in a single immediate-mode pass.
///
/// Hovering names the app under the pointer; clicking a segment expands its
/// stretches for that hour. Only the selected segment's detail renders, so the
/// cost is bounded by one app in one hour rather than by the size of the day.
struct DayTimelineView: View {
    @ObservedObject var store: SessionStore
    /// The popover shows a shorter band and no detail row: it is a glance, not a
    /// workbench.
    var compact: Bool = false
    /// Coordinates to draw. Nil means the store's own day-scoped layout; the
    /// menu bar passes today's explicitly, because the dashboard may be browsing
    /// history and a "right now" panel must never follow it there.
    var layoutOverride: TimelineLayout?

    private var bandHeight: CGFloat { compact ? 26 : 44 }
    /// The menu bar's band. It draws today's segments and brackets, not the
    /// dashboard's day-scoped ones: drawing the selected day's segments on
    /// today's axis emptied the popover's strip whenever the dashboard was
    /// browsing another date.
    private var isGlance: Bool { layoutOverride != nil }
    private var segments: [TimelineSegment] { isGlance ? store.glanceTimeline : store.timelineSegments }
    private var brackets: [(start: Date, end: Date)] { isGlance ? store.glanceBrackets : store.focusBrackets }
    /// Space under the band for focus brackets — reserved only when there are
    /// brackets to draw. Reserving it unconditionally left a band of dead space
    /// beneath the timeline on every day with no sessions, which read as a
    /// rendering fault rather than as emptiness.
    private var bracketRow: CGFloat { brackets.isEmpty ? 0 : 10 }

    var body: some View {
        if let layout = layoutOverride ?? store.timelineLayout, !layout.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                band(layout)
                // Same rule as the bracket row: an axis with no labels on it is
                // fourteen points of nothing.
                if !layout.hourTicks().isEmpty { axis(layout) }
                if !compact { detail }
            }
        } else {
            // Never an empty frame: dead space that renders nothing is the
            // failure this replaced.
            Text("No app time recorded for this day yet.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(height: bandHeight + bracketRow, alignment: .leading)
        }
    }

    // MARK: - Band

    private func band(_ layout: TimelineLayout) -> some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            Canvas { context, size in
                // Elided gaps first, so activity draws over them.
                for gap in layout.gaps {
                    let rect = CGRect(x: gap.xStart * size.width, y: 0,
                                      width: (gap.xEnd - gap.xStart) * size.width,
                                      height: bandHeight)
                    context.fill(Path(roundedRect: rect, cornerRadius: Tokens.Radius.swatch),
                                 with: .color(Tokens.Surface.well))
                }

                // Hour columns inside clusters only.
                for hour in layout.hourTicks() {
                    guard let fraction = layout.fraction(for: hour) else { continue }
                    var line = Path()
                    line.move(to: CGPoint(x: fraction * size.width, y: 0))
                    line.addLine(to: CGPoint(x: fraction * size.width, y: bandHeight))
                    context.stroke(line, with: .color(Tokens.Surface.hairline),
                                   lineWidth: 0.5)
                }

                // A session under the pointer or selected frames its spans and
                // dims the rest; an app row under the pointer dims every other
                // app. Only on the dashboard's own day — the popover's glance
                // band passes a layout override and stays plain.
                let framed = isGlance ? nil : store.framedSession
                let highlight = isGlance ? nil : store.highlightedBundleID
                for segment in segments {
                    // An instant inside an elided gap has no position; drawing it
                    // at 0 would smear the segment across the band.
                    guard let startX = layout.fraction(for: segment.start),
                          let endX = layout.fraction(for: segment.end) else { continue }
                    let left = startX * size.width
                    let segmentWidth = max(1.5, endX * size.width - left)
                    let rect = CGRect(x: left, y: 0, width: segmentWidth, height: bandHeight)
                    let isFocused = store.hoveredSegment?.id == segment.id
                        || store.selectedSegment?.id == segment.id
                    let insideFrame = framed.map { session in
                        session.spans.contains { $0.start < segment.end && $0.end > segment.start }
                    } ?? true
                    let matchesApp = highlight.map { $0 == segment.bundleID } ?? true
                    let emphasis: Double = (insideFrame && matchesApp) ? (isFocused ? 1 : 0.92) : 0.22
                    context.fill(Path(roundedRect: rect, cornerRadius: Tokens.Radius.swatch),
                                 with: .color(TimelinePalette.color(segment.colorIndex)
                                    .opacity(emphasis)))
                    if isFocused {
                        context.stroke(Path(roundedRect: rect, cornerRadius: Tokens.Radius.swatch),
                                       with: .color(.primary.opacity(0.6)), lineWidth: 1)
                    }
                }

                for session in brackets {
                    guard let startX = layout.fraction(for: session.start),
                          let endX = layout.fraction(for: session.end) else { continue }
                    var path = Path()
                    let y = bandHeight + bracketRow / 2
                    path.move(to: CGPoint(x: startX * size.width, y: y))
                    path.addLine(to: CGPoint(x: endX * size.width, y: y))
                    context.stroke(path, with: .color(.accentColor),
                                   style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }

                if let framed {
                    for span in framed.spans {
                        guard let startX = layout.fraction(for: span.start),
                              let endX = layout.fraction(for: span.end) else { continue }
                        let rect = CGRect(x: startX * size.width - 3, y: -3,
                                          width: max(6, (endX - startX) * size.width + 6),
                                          height: bandHeight + 6)
                        context.stroke(Path(roundedRect: rect, cornerRadius: 7),
                                       with: .color(.accentColor
                                            .opacity(store.selectedSession != nil ? 1 : 0.6)),
                                       lineWidth: 1.5)
                    }
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    store.hoverTimeline(at: Double(point.x / width), glance: isGlance)
                case .ended:
                    store.hoverTimeline(at: nil)
                }
            }
            .onTapGesture { location in
                // Selection opens the detail row, which the glance band has not.
                if !isGlance { store.selectTimeline(at: Double(location.x / width)) }
            }
            .overlay(alignment: .topLeading) { gapLabels(layout, width: width) }
            .overlay(alignment: .topLeading) { hoverLabel(layout, width: width) }
        }
        .frame(height: bandHeight + bracketRow)
        .accessibilityLabel("Day timeline, \(segments.count) app segments, "
                            + "\(layout.gaps.count) inactive periods")
    }

    /// Real text for the elided durations, outside the `Canvas`. Hidden when the
    /// separator is too narrow to hold a label.
    @ViewBuilder
    private func gapLabels(_ layout: TimelineLayout, width: CGFloat) -> some View {
        // A gap the user named — "Dinner" — says so; the rest say what they are.
        let breaks = store.breakRecords(on: layoutOverride != nil ? Date() : store.selectedDay)
        ForEach(layout.gaps) { gap in
            let separatorWidth = (gap.xEnd - gap.xStart) * width
            let named = breaks.first { $0.start < gap.end && $0.end > gap.start }
            let title = named.map { $0.name.isEmpty ? "Break" : $0.name } ?? "No activity"
            if separatorWidth >= 40 {
                Text(title + " · " + Tokens.preciseDuration(gap.duration))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
                    .offset(x: min(max(gap.xStart * width - 30, 0), max(0, width - 110)),
                            y: bandHeight + 2)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func hoverLabel(_ layout: TimelineLayout, width: CGFloat) -> some View {
        if let hovered = store.hoveredSegment,
           let startX = layout.fraction(for: hovered.start),
           let endX = layout.fraction(for: hovered.end) {
            let centre = CGFloat((startX + endX) / 2) * width
            HStack(spacing: Tokens.Space.xs) {
                AppIcon(bundleID: hovered.bundleID, size: 14, appName: hovered.appName)
                Text(hovered.appName).font(.caption.weight(.medium))
                Text(Tokens.timeRange(hovered.start, hovered.end))
                    .font(.caption2).foregroundStyle(.secondary)
                Text(Tokens.preciseDuration(hovered.seconds))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, Tokens.Space.s)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            .fixedSize()
            .offset(x: min(max(centre - 90, 0), max(0, width - 180)), y: -6)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Axis

    private func axis(_ layout: TimelineLayout) -> some View {
        let ticks = layout.hourTicks()

        return GeometryReader { geometry in
            // Label count follows the width available, not a fixed ten. At a
            // fixed count the labels collided the moment the band was narrower
            // than the full panel — "3am4am" — which is exactly what happens
            // when the timeline shares a row with the app list.
            let perLabel: CGFloat = 46
            let room = max(1, Int(geometry.size.width / perLabel))
            let step = max(1, Int((Double(ticks.count) / Double(room)).rounded(.up)))
            let labelled = ticks.enumerated()
                .filter { $0.offset % step == 0 }.map(\.element)
            ForEach(labelled, id: \.self) { hour in
                if let fraction = layout.fraction(for: hour) {
                    Text(DayTimelineView.hourLabel(hour))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .position(x: fraction * geometry.size.width, y: 6)
                }
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }

    // MARK: - Detail row

    @ViewBuilder private var detail: some View {
        if let selected = store.selectedSegment {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Tokens.Space.s) {
                    AppIcon(bundleID: selected.bundleID, size: 16, appName: selected.appName)
                    Text(selected.appName).font(.callout.weight(.medium))
                    Text(DayTimelineView.hourLabel(selected.start))
                        .font(.caption).foregroundStyle(.tertiary)
                    Spacer()
                    Button("Close") { store.clearTimelineSelection() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                ForEach(store.stretchesInSelectedHour) { stretch in
                    Text("\(Tokens.timeRange(stretch.start, stretch.end))  ·  "
                         + Tokens.preciseDuration(stretch.seconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(Tokens.Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.25),
                        in: RoundedRectangle(cornerRadius: Tokens.cardCorner))
        }
    }

    // MARK: - Hours

    /// Every whole hour inside the window.
    static func hourTicks(from start: Date, to end: Date) -> [Date] {
        let calendar = Calendar.current
        // Truncate, then step forward: `date(bySetting:)` searches forward and
        // would skip the first hour.
        guard var cursor = calendar.dateInterval(of: .hour, for: start)?.start else {
            return []
        }
        if cursor < start { cursor = cursor.addingTimeInterval(3_600) }
        var result: [Date] = []
        while cursor <= end && result.count < 48 {
            result.append(cursor)
            cursor = cursor.addingTimeInterval(3_600)
        }
        return result
    }

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        return formatter
    }()

    static func hourLabel(_ date: Date) -> String {
        hourFormatter.string(from: date).lowercased()
    }
}
