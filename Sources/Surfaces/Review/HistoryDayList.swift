import SwiftUI

/// Shared measures, so the hour axis sits exactly over every row's strip.
enum HistoryRowLayout {
    static let dateWidth: CGFloat = 46
    static let figureWidth: CGFloat = 70
    static let spacing: CGFloat = Tokens.Space.m
    static let inset: CGFloat = Tokens.Space.s
}

/// The filtered days, gathered under the month they fall in.
struct HistoryMonthGroup: Identifiable {
    let start: Date
    let days: [HistoryDay]

    var id: Date { start }
    var focused: TimeInterval { days.reduce(0) { $0 + $1.focused } }

    var title: String {
        Tokens.australianDate("MMMM yyyy").string(from: start)
    }

    /// Keeps the incoming order, which is newest first.
    static func group(_ days: [HistoryDay], calendar: Calendar = .current) -> [HistoryMonthGroup] {
        var groups: [HistoryMonthGroup] = []
        var current: [HistoryDay] = []
        var currentStart: Date?
        for day in days {
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: day.date)) ?? day.date
            if start != currentStart, let open = currentStart {
                groups.append(HistoryMonthGroup(start: open, days: current))
                current = []
            }
            currentStart = start
            current.append(day)
        }
        if let open = currentStart, !current.isEmpty {
            groups.append(HistoryMonthGroup(start: open, days: current))
        }
        return groups
    }
}

/// The day's recorded entries across its twenty-four hours: sessions in their
/// category's colour, recorded breaks in grey. One scale for every row, so a
/// morning person's list reads as a column of mornings.
struct HistoryDayStrip: View {
    let date: Date
    let entries: [DayEntry]
    var height: CGFloat = 8

    private struct Mark: Identifiable {
        let id: String
        let start: Double
        let length: Double
        let colour: Color
    }

    private var marks: [Mark] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        let total = max(1, dayEnd.timeIntervalSince(dayStart))
        var result: [Mark] = []
        func add(_ id: String, _ start: Date, _ end: Date, _ colour: Color) {
            let low = max(start, dayStart), high = min(end, dayEnd)
            guard high > low else { return }
            result.append(Mark(id: id, start: low.timeIntervalSince(dayStart) / total,
                               length: high.timeIntervalSince(low) / total, colour: colour))
        }
        for entry in entries {
            switch entry {
            case .session(let session):
                for (index, span) in session.spans.enumerated() {
                    add("\(session.id)-\(index)", span.start, span.end,
                        Tokens.Palette.workType(session.workType))
                }
            case .rest(let rest):
                add("\(rest.id)", rest.start, rest.end, Tokens.Palette.warmGrey.opacity(0.55))
            }
        }
        return result
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(StoryStyle.line)
                ForEach(marks) { mark in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(mark.colour)
                        .frame(width: max(3, geometry.size.width * mark.length))
                        .offset(x: geometry.size.width * mark.start)
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Clock labels over the strips: midnight to midnight, a label every six hours.
struct HistoryStripAxis: View {
    var leading: CGFloat = HistoryRowLayout.inset + HistoryRowLayout.dateWidth + HistoryRowLayout.spacing
    var trailing: CGFloat = HistoryRowLayout.inset + HistoryRowLayout.figureWidth + HistoryRowLayout.spacing

    var body: some View {
        GeometryReader { geometry in
            ForEach([0, 6, 12, 18], id: \.self) { hour in
                Text(InsightHourGrid.hourLabel(hour))
                    .font(Tokens.Typography.microLabel)
                    .foregroundStyle(.tertiary)
                    .fixedSize()
                    .offset(x: geometry.size.width * CGFloat(hour) / 24)
            }
        }
        .frame(height: 12)
        .padding(.leading, leading)
        .padding(.trailing, trailing)
        .accessibilityHidden(true)
    }
}

/// One day: its date, its shape across the clock, what it held, its focus.
struct HistoryDayRow: View {
    let day: HistoryDay
    let projection: StoryDayProjection
    let context: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: HistoryRowLayout.spacing) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(Calendar.current.component(.day, from: day.date))")
                        .font(Tokens.Typography.sectionTitle.monospacedDigit())
                    Text(Tokens.weekdayName(day.date).prefix(3).uppercased())
                        .font(Tokens.Typography.microLabel)
                        .foregroundStyle(isSelected ? AnyShapeStyle(Tokens.Colour.focus)
                                                    : AnyShapeStyle(.secondary))
                }
                .frame(width: HistoryRowLayout.dateWidth, alignment: .leading)
                VStack(alignment: .leading, spacing: 5) {
                    HistoryDayStrip(date: day.date, entries: projection.sessions)
                    Text(context.isEmpty ? "Recorded app use only" : context)
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                VStack(alignment: .trailing, spacing: 1) {
                    Text(day.focused > 0 ? Tokens.duration(day.focused) : "—")
                        .font(Tokens.Typography.rowTitle.weight(.semibold).monospacedDigit())
                        .foregroundStyle(day.focused > 0 ? .primary : .tertiary)
                    Text(day.sessions == 1 ? "1 session" : "\(day.sessions) sessions")
                        .font(Tokens.Typography.microLabel)
                        .foregroundStyle(.secondary)
                }
                .frame(width: HistoryRowLayout.figureWidth, alignment: .trailing)
            }
            .padding(.vertical, Tokens.Space.s)
            .padding(.horizontal, HistoryRowLayout.inset)
            .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
            .background(isSelected ? Tokens.Colour.focus.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(StoryPressStyle(hovers: true, cornerRadius: Tokens.Radius.nested))
        .simultaneousGesture(TapGesture(count: 2).onEnded { onOpen() })
        .accessibilityLabel(spoken)
        .accessibilityHint(isSelected ? "Clears the preview" : "Previews this day beside the list")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "Open as a story", onOpen)
    }

    private var spoken: String {
        var parts = [Tokens.longDate(day.date),
                     "\(Tokens.duration(day.focused)) focused",
                     "\(Tokens.duration(day.tracked)) tracked",
                     day.sessions == 1 ? "1 session" : "\(day.sessions) sessions"]
        if isSelected { parts.append("selected") }
        return parts.joined(separator: ", ")
    }
}

/// The picked day in the rail: enough to recognise it, and the way into its
/// full story. Rail tiles, never a card inside the list.
struct HistoryDayPreview: View {
    @ObservedObject var store: SessionStore
    let projection: StoryDayProjection
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            summaryTile
            if !projection.sessions.isEmpty { sessionsTile }
            if !projection.apps.isEmpty { appsTile }
            if !notes.isEmpty { notesTile }
        }
    }

    private var summaryTile: some View {
        StoryTile(title: Tokens.longDate(projection.date), trailing: nil) {
            Text(Tokens.preciseDuration(projection.focused))
                .font(Tokens.Typography.metricValue.monospacedDigit())
                .foregroundStyle(projection.focused > 0 ? AnyShapeStyle(Tokens.Colour.focus)
                                                        : AnyShapeStyle(.secondary))
            Text(summaryNote)
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 3) {
                HistoryDayStrip(date: projection.date, entries: projection.sessions, height: 10)
                HistoryStripAxis(leading: 0, trailing: 0)
            }
            .padding(.top, Tokens.Space.xs)
            Button(action: onOpen) {
                Text("Open as a story ›")
                    .font(Tokens.Typography.metadata.weight(.semibold))
                    .foregroundStyle(StoryStyle.action)
                    .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
            }
            .buttonStyle(StoryPressStyle())
            .accessibilityLabel("Open \(Tokens.longDate(projection.date)) as a story")
        }
    }

    private var summaryNote: String {
        var parts = ["logged focus"]
        if projection.tracked > 0 {
            parts.append("\(Tokens.duration(projection.tracked)) recorded app use")
        }
        if projection.longestFocusStretch > 0 {
            parts.append("longest stretch \(Tokens.preciseDuration(projection.longestFocusStretch))")
        }
        return parts.joined(separator: " · ")
    }

    private var sessionsTile: some View {
        let count = projection.focusSessionCount
        return StoryTile(title: "Sessions", trailing: count == 1 ? "1 session" : "\(count) sessions") {
            ForEach(projection.sessions) { entry in
                switch entry {
                case .session(let session):
                    entryRow(colour: Tokens.Palette.workType(session.workType),
                             title: session.name.isEmpty ? session.workType.displayName : session.name,
                             detail: "\(session.workType.displayName) · \(Tokens.timeRange(session.start, session.end))",
                             value: Tokens.duration(session.worked))
                case .rest(let rest):
                    entryRow(colour: Tokens.Palette.warmGrey.opacity(0.55),
                             title: rest.name.isEmpty ? "Break" : rest.name,
                             detail: Tokens.timeRange(rest.start, rest.end),
                             value: Tokens.duration(rest.length))
                }
            }
        }
    }

    private func entryRow(colour: Color, title: String, detail: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
            RoundedRectangle(cornerRadius: Tokens.Radius.bar, style: .continuous)
                .fill(colour)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Tokens.Typography.metadata.weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Tokens.Space.xs)
            Text(value)
                .font(Tokens.Typography.metadata.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var appsTile: some View {
        let limit = store.engine.store.menuAppCount
        return StoryTile(title: projection.apps.count > limit ? "Top \(limit) apps" : "Apps",
                  trailing: projection.apps.count == 1 ? "1 recorded" : "\(projection.apps.count) recorded") {
            ForEach(Array(projection.apps.prefix(limit).enumerated()), id: \.element.id) { index, app in
                StoryAppRow(app: app, rank: index)
            }
        }
    }

    /// Notes saved against any stretch of the day's sessions, oldest first.
    private var notes: [(id: UUID, title: String, text: String)] {
        var result: [(id: UUID, title: String, text: String)] = []
        for entry in projection.sessions {
            guard case .session(let session) = entry else { continue }
            for recordID in session.recordIDs {
                let text = store.metadataArchive.metadata(for: recordID)?.note ?? ""
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    result.append((recordID, session.name.isEmpty ? session.workType.displayName : session.name,
                                   trimmed))
                }
            }
        }
        return result
    }

    private var notesTile: some View {
        StoryTile(title: "Notes", trailing: nil) {
            ForEach(notes, id: \.id) { note in
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title)
                        .font(Tokens.Typography.metadata.weight(.semibold))
                    Text(note.text)
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
