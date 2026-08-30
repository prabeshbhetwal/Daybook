import SwiftUI

struct TimelineRestEvidence: Identifiable, Equatable {
    let id: UUID
    let name: String
    let start: Date
    let end: Date

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

/// Presentation-only partition of one elided gap. Named rests retain only
/// their canonical overlap; every interval outside them remains unknown
/// inactivity instead of inheriting the rest's label.
struct TimelineGapEvidence: Equatable {
    let rests: [TimelineRestEvidence]
    let unknown: [DateInterval]

    init(gap: TimelineGap, breaks: [SessionRecord]) {
        rests = breaks.compactMap { record in
            guard record.workType == .breakTime else { return nil }
            let start = max(gap.start, record.start)
            let end = min(gap.end, record.end)
            guard end > start else { return nil }
            return TimelineRestEvidence(id: record.id,
                                        name: record.name.isEmpty ? "Break" : record.name,
                                        start: start, end: end)
        }.sorted { $0.start < $1.start }

        var unlabelled: [DateInterval] = []
        var cursor = gap.start
        for rest in rests {
            if rest.start > cursor {
                unlabelled.append(DateInterval(start: cursor, end: rest.start))
            }
            cursor = max(cursor, rest.end)
        }
        if cursor < gap.end {
            unlabelled.append(DateInterval(start: cursor, end: gap.end))
        }
        unknown = unlabelled
    }
}

/// The day as one band, divided into uniform hour columns. Drawn with `Canvas`
/// rather than Swift Charts because a busy day is several hundred segments and
/// Canvas draws them in a single immediate-mode pass.
///
/// Hovering names the app under the pointer; clicking a segment expands its
/// stretches for that hour. Only the selected segment's detail renders, so the
/// cost is bounded by one app in one hour rather than by the size of the day.
struct DayTimelineView: View {
    @ObservedObject var store: SessionStore
    @Environment(\.focusShowsTimelineLabels) private var showsTimelineLabels
    /// The popover shows a shorter band and no detail row: it is a glance, not a
    /// workbench.
    var compact: Bool = false
    /// Coordinates to draw. Nil means the store's own day-scoped layout; the
    /// menu bar passes today's explicitly, because the dashboard may be browsing
    /// history and a "right now" panel must never follow it there.
    var layoutOverride: TimelineLayout?
    /// Today grants the ribbon the screen's dominant visual weight. Legacy and
    /// compact consumers retain their existing measures.
    var dominant: Bool = false
    /// The purpose-built Today surface presents detail in its inspector below
    /// the ribbon; legacy Dashboard keeps the inline hour detail.
    var showsDetail: Bool = true
    /// Today owns mutually exclusive app/session inspection. Legacy Dashboard
    /// retains its established combined selection behaviour.
    var usesTodaySelection: Bool = false

    private var bandHeight: CGFloat { compact ? 26 : dominant ? 64 : 44 }
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
                if !compact { timelineLegend }
                // Same rule as the bracket row: an axis with no labels on it is
                // fourteen points of nothing.
                if showsTimelineLabels, !layout.hourTicks().isEmpty { axis(layout) }
                if !compact { watchingStatus }
                if !compact && showsDetail { detail }
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
        let recordedBreaks = store.breakRecords(
            on: layoutOverride != nil ? Date() : store.selectedDay)
        return GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            Canvas { context, size in
                // The ribbon is one object: a single rounded band with its
                // stretches butted together, rather than a row of separate
                // blocks. Clipping a copy keeps the focus brackets and the
                // selected-session frame — which sit outside the band — free.
                let bandRect = CGRect(x: 0, y: 0, width: size.width, height: bandHeight)
                var band = context
                band.clip(to: Path(roundedRect: bandRect,
                                   cornerRadius: Tokens.Radius.nested,
                                   style: .continuous))
                // Time with nothing recorded is the band's own ground, so a gap
                // reads as quiet rather than as a hole in the page.
                band.fill(Path(bandRect), with: .color(Tokens.Colour.elevated))

                // Elided gaps first, so activity draws over them.
                for gap in layout.gaps {
                    let rect = CGRect(x: gap.xStart * size.width, y: 0,
                                      width: (gap.xEnd - gap.xStart) * size.width,
                                      height: bandHeight)
                    band.fill(Path(rect), with: .color(Tokens.Colour.elevated))

                    // A canonical rest may occupy only part of this collapsed
                    // gap. Draw its proportional slice; unknown time keeps the
                    // ordinary inactivity fill around it.
                    let evidence = TimelineGapEvidence(gap: gap, breaks: recordedBreaks)
                    let gapDuration = max(1, gap.duration)
                    for rest in evidence.rests {
                        let from = rest.start.timeIntervalSince(gap.start) / gapDuration
                        let to = rest.end.timeIntervalSince(gap.start) / gapDuration
                        let restRect = CGRect(
                            x: (gap.xStart + from * (gap.xEnd - gap.xStart)) * size.width,
                            y: 0,
                            width: max(1.5, (to - from) * (gap.xEnd - gap.xStart) * size.width),
                            height: bandHeight)
                        band.fill(Path(restRect),
                                  with: .color(Tokens.Palette.workType(.breakTime)
                                     .opacity(0.55)))
                    }
                }

                // Hour columns inside clusters only.
                for hour in layout.hourTicks() {
                    guard let fraction = layout.fraction(for: hour) else { continue }
                    var line = Path()
                    line.move(to: CGPoint(x: fraction * size.width, y: 0))
                    line.addLine(to: CGPoint(x: fraction * size.width, y: bandHeight))
                    band.stroke(line, with: .color(Tokens.Colour.line), lineWidth: 0.5)
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
                    band.fill(Path(rect),
                              with: .color(TimelinePalette.color(segment.colorIndex)
                                 .opacity(emphasis)))
                    if isFocused {
                        band.stroke(Path(rect), with: .color(.primary.opacity(0.6)),
                                    lineWidth: 1)
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
                if !isGlance {
                    let fraction = Double(location.x / width)
                    if usesTodaySelection { store.selectTodayTimeline(at: fraction) }
                    else { store.selectTimeline(at: fraction) }
                }
            }
            .overlay(alignment: .topLeading) {
                if showsTimelineLabels, !compact { gapLabels(layout, width: width) }
            }
            .overlay(alignment: .topLeading) {
                if showsTimelineLabels { hoverLabel(layout, width: width) }
            }
        }
        .frame(height: bandHeight + bracketRow + gapLabelRow(layout))
        .accessibilityRepresentation { timelineAccessibilitySummary(layout) }
    }

    private var legendSegments: [TimelineSegment] {
        var seen: Set<String> = []
        return segments.filter { seen.insert($0.bundleID).inserted }
    }

    private var timelineLegend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110),
                                     spacing: Tokens.Space.s,
                                     alignment: .leading)],
                  alignment: .leading,
                  spacing: Tokens.Space.xs) {
            ForEach(legendSegments) { segment in
                HStack(spacing: Tokens.Space.xs) {
                    AppSwatch(rank: segment.colorIndex, bundleID: segment.bundleID,
                              appName: segment.appName, size: 14)
                    Text(segment.appName)
                        .lineLimit(1)
                }
            }
            if !brackets.isEmpty {
                Label("Focus session", systemImage: "bracket.square")
            }
        }
        .font(Tokens.Typography.metadata)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Timeline legend, "
                            + legendSegments.map(\.appName).joined(separator: ", ")
                            + (brackets.isEmpty ? "" : ", focus session brackets"))
    }

    private func timelineAccessibilitySummary(_ layout: TimelineLayout) -> some View {
        let breaks = store.breakRecords(on: isGlance ? Date() : store.selectedDay)
        return VStack(alignment: .leading, spacing: 0) {
            Text("Day timeline, \(segments.count) app segments, "
                 + "\(layout.gaps.count) inactive periods")
                .accessibilityAddTraits(.isHeader)
            ForEach(segments) { segment in
                if isGlance {
                    Text(segmentAccessibilityLabel(segment))
                } else {
                    Button(segmentAccessibilityLabel(segment)) {
                        selectForAccessibility(segment, layout: layout)
                    }
                    .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
                }
            }
            ForEach(layout.gaps) { gap in
                let evidence = TimelineGapEvidence(gap: gap, breaks: breaks)
                ForEach(evidence.rests) { rest in
                    Text("\(rest.name), \(Tokens.timeRange(rest.start, rest.end)), "
                         + "\(Tokens.spent(rest.duration)) rest")
                }
                let unknown = evidence.unknown.reduce(0) { $0 + $1.duration }
                if unknown > 0 {
                    Text("Other inactivity, \(Tokens.spent(unknown))")
                }
            }
            ForEach(Array(brackets.enumerated()), id: \.offset) { _, bracket in
                Text("Focus session, \(Tokens.timeRange(bracket.start, bracket.end))")
            }
        }
    }

    private func segmentAccessibilityLabel(_ segment: TimelineSegment) -> String {
        "\(segment.appName), \(Tokens.timeRange(segment.start, segment.end)), "
            + "\(Tokens.spent(segment.seconds)) tracked"
    }

    private func selectForAccessibility(_ segment: TimelineSegment, layout: TimelineLayout) {
        let midpoint = segment.start.addingTimeInterval(segment.seconds / 2)
        guard let fraction = layout.fraction(for: midpoint) else { return }
        if usesTodaySelection { store.selectTodayTimeline(at: fraction) }
        else { store.selectTimeline(at: fraction) }
    }

    /// Real text for the elided durations, outside the `Canvas`. Hidden when the
    /// separator is too narrow to hold a label.
    @ViewBuilder
    private func gapLabels(_ layout: TimelineLayout, width: CGFloat) -> some View {
        let breaks = store.breakRecords(on: layoutOverride != nil ? Date() : store.selectedDay)
        ForEach(layout.gaps) { gap in
            let separatorWidth = (gap.xEnd - gap.xStart) * width
            let evidence = TimelineGapEvidence(gap: gap, breaks: breaks)
            if !evidence.rests.isEmpty, separatorWidth >= 28 {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(evidence.rests) { rest in
                        Text("\(rest.name) · \(Tokens.timeRange(rest.start, rest.end)) · "
                             + Tokens.preciseDuration(rest.duration))
                    }
                    let unknown = evidence.unknown.reduce(0) { $0 + $1.duration }
                    if unknown > 0 {
                        Text("Other inactivity · \(Tokens.preciseDuration(unknown))")
                            .foregroundStyle(.quaternary)
                    }
                }
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .fixedSize()
                .offset(x: min(max(gap.xStart * width - 30, 0), max(0, width - 260)),
                        y: bandHeight + bracketRow + 1)
                .allowsHitTesting(false)
            }
        }
    }

    private func gapLabelRow(_ layout: TimelineLayout) -> CGFloat {
        guard showsTimelineLabels, !compact, !layout.gaps.isEmpty else { return 0 }
        let breaks = store.breakRecords(on: layoutOverride != nil ? Date() : store.selectedDay)
        return layout.gaps.contains {
            !TimelineGapEvidence(gap: $0, breaks: breaks).rests.isEmpty
        } ? 24 : 0
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

    @ViewBuilder private var watchingStatus: some View {
        if !isGlance, store.isToday,
           FocusSurfaceMode(state: store.state) == .watching {
            Label("Watching now · focus is paused; app activity remains At the Mac evidence.",
                  systemImage: "play.rectangle")
                .font(Tokens.Typography.metadata)
                .foregroundStyle(Tokens.Colour.attention)
                .padding(.horizontal, Tokens.Space.s)
                .padding(.vertical, Tokens.Space.xs)
                .background(Tokens.Colour.attention.opacity(0.07), in: Capsule())
                .accessibilityLabel("Watching now. Focus is paused. App activity is At the Mac time.")
        }
    }

    @ViewBuilder private var detail: some View {
        if let selected = store.selectedSegment {
            SegmentHourDetail(
                bundleID: selected.bundleID,
                appName: selected.appName,
                hourStart: Calendar.current.dateInterval(of: .hour, for: selected.start)?.start
                    ?? selected.start,
                colorIndex: selected.colorIndex,
                stretches: store.stretchesInSelectedHour,
                onClose: { store.clearTimelineSelection() })
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

/// One app in one hour, told at a fixed size whatever the hour was like. A
/// messaging hour is dozens of half-minute glances, and listing each one grew
/// the card without limit while saying nothing. Now the summary line carries
/// the totals, a strip of the hour shows its shape — one block or confetti —
/// and only the longest visits are named; the rest are one line.
struct SegmentHourDetail: View {
    let bundleID: String
    let appName: String
    let hourStart: Date
    let colorIndex: Int
    let stretches: [TimelineSegment]
    let onClose: () -> Void

    private var hourEnd: Date { hourStart.addingTimeInterval(3_600) }

    /// Attended seconds inside this hour only — a stretch that crosses the
    /// hour's edge contributes its share, not its whole.
    private var totalInHour: TimeInterval {
        stretches.reduce(0) { total, stretch in
            total + max(0, min(stretch.end, hourEnd).timeIntervalSince(max(stretch.start, hourStart)))
        }
    }

    /// Chronological, at most five — the longest ones when there are more.
    private var named: [TimelineSegment] {
        guard stretches.count > 5 else { return stretches }
        let longest = stretches.sorted { $0.seconds > $1.seconds }.prefix(5)
        return longest.sorted { $0.start < $1.start }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack(spacing: Tokens.Space.s) {
                AppIcon(bundleID: bundleID, size: 16, appName: appName)
                Text(appName).font(.callout.weight(.medium))
                Text(DayTimelineView.hourLabel(hourStart))
                    .font(.caption).foregroundStyle(.tertiary)
                Text("\(stretches.count == 1 ? "1 visit" : "\(stretches.count) visits") · "
                     + "\(Tokens.preciseDuration(totalInHour)) of the hour")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Close", action: onClose)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
            }
            hourStrip
            rows
        }
        .padding(Tokens.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.25),
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.panel))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(appName), \(stretches.count) visits, "
                            + "\(Tokens.preciseDuration(totalInHour)) in this hour")
    }

    /// The hour as a fixed-height band with the app's visits filled in: one
    /// wide block reads as a sitting, confetti reads as checking. Quarter-hour
    /// ticks give the eye a scale.
    private var hourStrip: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            Canvas { context, size in
                context.fill(Path(roundedRect: CGRect(origin: .zero, size: size),
                                  cornerRadius: 3),
                             with: .color(Tokens.Colour.elevated))
                for quarter in 1...3 {
                    let x = size.width * CGFloat(quarter) / 4
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: 0))
                    line.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(line, with: .color(Tokens.Colour.line), lineWidth: 0.5)
                }
                for stretch in stretches {
                    let from = max(0, stretch.start.timeIntervalSince(hourStart) / 3_600)
                    let to = min(1, stretch.end.timeIntervalSince(hourStart) / 3_600)
                    guard to > from else { continue }
                    let rect = CGRect(x: from * size.width, y: 0,
                                      width: max(1.5, (to - from) * size.width),
                                      height: size.height)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2),
                                 with: .color(TimelinePalette.color(colorIndex)))
                }
            }
            .frame(width: width)
        }
        .frame(height: 10)
    }

    @ViewBuilder private var rows: some View {
        ForEach(named) { stretch in
            Text("\(Tokens.timeRange(stretch.start, stretch.end))  ·  "
                 + Tokens.preciseDuration(stretch.seconds))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        if stretches.count > named.count {
            let rest = stretches.count - named.count
            let restSeconds = totalInHour - named.reduce(0) { total, stretch in
                total + max(0, min(stretch.end, hourEnd)
                    .timeIntervalSince(max(stretch.start, hourStart)))
            }
            Text("The \(named.count) longest are listed · \(rest) shorter "
                 + "\(rest == 1 ? "visit" : "visits") make up the other "
                 + Tokens.preciseDuration(max(0, restSeconds)))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
