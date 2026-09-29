import SwiftUI

/// Clock hours as History says them: "9 am", "9 am – 11 am".
enum HistoryHours {
    static func label(_ hour: Int) -> String {
        let wrapped = ((hour % 24) + 24) % 24
        let twelve = wrapped % 12 == 0 ? 12 : wrapped % 12
        return "\(twelve) \(wrapped < 12 ? "am" : "pm")"
    }

    static func span(from startHour: Int) -> String {
        "\(label(startHour)) – \(label(startHour + 2))"
    }

    /// The best two hours' figure, and where it mostly fell, said once.
    static func note(seconds: TimeInterval, phrase: String?) -> String {
        var note = "\(Tokens.duration(seconds)) of focus fell here"
        if let phrase { note += ", most of it \(phrase)" }
        return note + "."
    }
}

/// What the rail describes once the selection meets the archive: a session
/// that is gone, or hidden by a search, reads as the month it was in.
enum HistoryRailScope: Equatable {
    case month(Date)
    case day(Date)
    case session(DaySession, day: Date)

    static func resolve(_ selection: HistorySelection, session: DaySession?,
                        calendar: Calendar = .current) -> HistoryRailScope {
        switch selection {
        case .month(let start): return .month(start)
        case .day(let day): return .day(day)
        case .session(_, let day):
            if let session { return .session(session, day: day) }
            return .month(selection.monthStart(calendar: calendar))
        }
    }
}

/// History's rail: the month, day or session picked in the journal, and
/// nothing from any other time frame.
struct HistoryJournalRail: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    @Environment(\.focusInterfaceDensity) private var density

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            switch scope {
            case .month(let start):
                HistoryMonthRail(store: store, navigation: navigation, monthStart: start)
                    .storyRenderEvidence(.historyMonthRail)
            case .day(let day):
                HistoryDayRail(store: store, projection: store.storyDayProjection(on: day)) {
                    navigation.openDay(day)
                }
                .storyRenderEvidence(.historyDayRail)
            case .session(let session, let day):
                HistorySessionRail(store: store, session: session, day: day,
                                   apps: store.storyDayProjection(on: day).sessionDetails[session.id]?.apps ?? []) {
                    navigation.openDay(day)
                }
                .storyRenderEvidence(.historySessionRail)
            }
        }
        .padding(StoryStyle.railInsets(for: density))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scope: HistoryRailScope {
        let selection = navigation.historySelectionOrDefault()
        var session: DaySession?
        if case .session(let thread, let day) = selection {
            session = store.journalSession(thread: thread, on: day)
            // A search that hides the session, or its whole day, hides it
            // from the rail too.
            if store.historyFilter.isActive {
                let listed = store.historyJournal().contains { entry in
                    if case .day(let row) = entry { return row.date == day && (row.threads?.contains(thread) ?? true) }
                    return false
                }
                if !listed { session = nil }
            }
        }
        return HistoryRailScope.resolve(selection, session: session)
    }
}

/// The rail's title: which month, day or session it describes.
struct HistoryRailHeading: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Tokens.Typography.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(durations: detail)
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A month: where its focus went, when, which goals it met, which apps, how
/// it compares with the months before, and for this month, how it is going.
struct HistoryMonthRail: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    let monthStart: Date

    var body: some View {
        let calendar = Calendar.current
        let now = store.now()
        let isCurrent = calendar.isDate(monthStart, equalTo: now, toGranularity: .month)
        let anchor = isCurrent ? now
            : (calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) ?? monthStart)
        let facts = store.insightReading(scope: .month, anchoredAt: anchor, limit: 1).facts
        let month = HistoryJournalBuilder.month(starting: monthStart, days: store.historyDays, calendar: calendar)
        let archive = store.historyArchiveFacts()
        let recent = HistoryJournalBuilder.recentMonths(endingAt: monthStart, focusByDay: archive.focusByDay,
                                                        firstDay: archive.firstDay, calendar: calendar)
        let surface = store.insightSurface(for: .month)
        return VStack(alignment: .leading, spacing: Tokens.Space.m) {
            HistoryRailHeading(title: HistoryMonthHeader.title(monthStart))
            if !facts.categories.isEmpty {
                StoryTile(title: "Focus by category", trailing: nil) {
                    CategoryShareBar(shares: facts.categories)
                    if isCurrent, let placed = surface.categories {
                        Text("Where each lands in the day: \(placed.headline).")
                            .font(Tokens.Typography.metadata)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let window = facts.bestWindow {
                StoryTile(title: "Best two hours", trailing: nil) {
                    Text(HistoryHours.span(from: window.startHour))
                        .font(Tokens.Typography.sectionTitle)
                    Text(durations: HistoryHours.note(seconds: window.seconds, phrase: facts.bestWindowPhrase))
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !facts.goalRates.isEmpty { goalsTile(facts.goalRates) }
            if !facts.apps.isEmpty { appsTile(facts.apps, tracked: month.tracked) }
            if recent.count > 1 { recentTile(recent) }
            if isCurrent { soFar(surface) }
        }
    }

    /// `16h 25m recorded app use`: the month's app use, said once, here.
    static func appUseLine(tracked: TimeInterval) -> String {
        "\(Tokens.duration(tracked)) recorded app use"
    }

    private func goalsTile(_ rates: [InsightGoalRate]) -> some View {
        StoryTile(title: "Category goals", trailing: "days met") {
            ForEach(rates) { rate in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Tokens.Space.xs) {
                        Image(systemName: rate.workType.symbolName)
                            .font(Tokens.Typography.microLabel)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Tokens.Palette.workType(rate.workType))
                            .frame(width: 14)
                            .accessibilityHidden(true)
                        Text(rate.workType.displayName)
                            .font(Tokens.Typography.metadata)
                        Spacer(minLength: Tokens.Space.s)
                        Text("\(rate.metDays) of \(rate.focusedDays)")
                            .font(Tokens.Typography.metadata.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { geometry in
                        Capsule().fill(StoryStyle.line)
                            .overlay(alignment: .leading) {
                                Capsule().fill(Tokens.Palette.workType(rate.workType))
                                    .frame(width: geometry.size.width * rate.share)
                            }
                    }
                    .frame(height: 3)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(rate.workType.displayName): \(Tokens.spent(rate.goal)) goal met on "
                                    + "\(rate.metDays) of \(rate.focusedDays) focused days")
            }
        }
    }

    private func appsTile(_ apps: [AppRank], tracked: TimeInterval) -> some View {
        let limit = store.engine.store.menuAppCount
        return StoryTile(title: apps.count > limit ? "Top \(limit) apps" : "Apps",
                         trailing: apps.count == 1 ? "1 recorded" : "\(apps.count) recorded") {
            if tracked > 0 {
                Text(durations: Self.appUseLine(tracked: tracked))
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(apps.prefix(limit).enumerated()), id: \.element.id) { index, app in
                StoryAppRow(app: app, rank: index)
            }
        }
    }

    private func recentTile(_ recent: [JournalMonthTotal]) -> some View {
        let peak = max(recent.map(\.focused).max() ?? 0, 1)
        return StoryTile(title: recent.count >= 12 ? "Last 12 months" : "Months on record", trailing: nil) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(recent) { total in
                    let isShown = total.start == monthStart
                    Button { navigation.selectHistory(.month(total.start), scrolling: true) } label: {
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(Tokens.Colour.focus.opacity(isShown ? 1 : 0.35))
                                .frame(height: max(2, 44 * total.focused / peak))
                            Text(DateFormats.australian("MMMMM").string(from: total.start))
                                .font(Tokens.Typography.micro)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 60, alignment: .bottom)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(DurationText.spoken(in:
                        "\(HistoryMonthHeader.title(total.start)), \(Tokens.duration(total.focused)) focused"))
                    .accessibilityAddTraits(isShown ? .isSelected : [])
                }
            }
        }
    }

    @ViewBuilder private func soFar(_ surface: InsightSurface) -> some View {
        Text("This month so far")
            .font(Tokens.Typography.metadata.weight(.bold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, Tokens.Space.s)
        if surface.hasEvidence {
            if let pace = surface.pace { InsightSection(title: "Pace", insight: pace) }
            if let quality = surface.quality { InsightSection(title: "Focus quality", insight: quality) }
            if let continuity = surface.continuity { InsightSection(title: "Continuity", insight: continuity) }
        } else {
            Text(InsightSurface.insufficientEvidenceCopy)
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A day: its focus and shape, its apps, its notes in full, and the way into
/// its story. Its sessions are in the journal already.
struct HistoryDayRail: View {
    @ObservedObject var store: SessionStore
    let projection: StoryDayProjection
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            HistoryRailHeading(title: Tokens.longDate(projection.date))
            StoryTile(title: "Focus", trailing: nil) {
                Text(durations: Tokens.preciseDuration(projection.focused))
                    .font(Tokens.Typography.metricValue.monospacedDigit())
                    .foregroundStyle(projection.focused > 0 ? AnyShapeStyle(Tokens.Colour.focus)
                                                            : AnyShapeStyle(.secondary))
                if let note = summaryNote {
                    Text(durations: note)
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 3) {
                    HistoryDayStrip(date: projection.date, entries: projection.sessions, height: 10)
                    HistoryStripAxis(leading: 0, trailing: 0)
                }
                .padding(.top, Tokens.Space.xs)
                Button("Open as a story ›", action: onOpen)
                    .buttonStyle(StoryLinkStyle())
                    .accessibilityLabel("Open \(Tokens.longDate(projection.date)) as a story")
            }
            if !projection.apps.isEmpty {
                let limit = store.engine.store.menuAppCount
                StoryTile(title: projection.apps.count > limit ? "Top \(limit) apps" : "Apps",
                          trailing: projection.apps.count == 1 ? "1 recorded" : "\(projection.apps.count) recorded") {
                    ForEach(Array(projection.apps.prefix(limit).enumerated()), id: \.element.id) { index, app in
                        StoryAppRow(app: app, rank: index)
                    }
                }
            }
            if !notes.isEmpty {
                StoryTile(title: "Notes", trailing: nil) {
                    ForEach(notes, id: \.id) { note in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title).font(Tokens.Typography.metadata.weight(.semibold))
                            Text(note.text)
                                .font(Tokens.Typography.metadata)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private var summaryNote: String? {
        var parts: [String] = []
        if projection.tracked > 0 { parts.append("\(Tokens.duration(projection.tracked)) recorded app use") }
        if projection.longestFocusStretch > 0 {
            parts.append("longest stretch \(Tokens.preciseDuration(projection.longestFocusStretch))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Notes saved against any stretch of the day's sessions, oldest first.
    private var notes: [(id: UUID, title: String, text: String)] {
        var result: [(id: UUID, title: String, text: String)] = []
        for entry in projection.sessions {
            guard case .session(let session) = entry else { continue }
            for recordID in session.recordIDs {
                let text = (store.metadataArchive.metadata(for: recordID)?.note ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    result.append((recordID, session.workType.sessionTitle(named: session.name), text))
                }
            }
        }
        return result
    }
}

/// A session: its length and time, each stretch when there were several,
/// its apps, its note in full, and the way into its day.
struct HistorySessionRail: View {
    @ObservedObject var store: SessionStore
    let session: DaySession
    let day: Date
    let apps: [AppRank]
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            HistoryRailHeading(title: session.workType.sessionTitle(named: session.name),
                               detail: Tokens.longDate(day))
            StoryTile(title: session.workType.displayName, trailing: nil) {
                Text(durations: session.isRunning ? "In progress" : Tokens.preciseDuration(session.worked))
                    .font(Tokens.Typography.metricValue.monospacedDigit())
                Text(Tokens.timeRange(session.start, session.end))
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                if session.spans.count > 1 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(session.spans.count) stretches")
                            .font(Tokens.Typography.metadata.weight(.semibold))
                        ForEach(Array(session.spans.enumerated()), id: \.offset) { _, span in
                            Text(Tokens.timeRange(span.start, span.end))
                                .font(Tokens.Typography.metadata.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Open its day ›", action: onOpen)
                    .buttonStyle(StoryLinkStyle())
                    .accessibilityLabel("Open \(Tokens.longDate(day)) as a story")
            }
            if !apps.isEmpty {
                let limit = store.engine.store.menuAppCount
                StoryTile(title: apps.count > limit ? "Top \(limit) apps" : "Apps",
                          trailing: apps.count == 1 ? "1 recorded" : "\(apps.count) recorded") {
                    ForEach(Array(apps.prefix(limit).enumerated()), id: \.element.id) { index, app in
                        StoryAppRow(app: app, rank: index)
                    }
                }
            }
            if !notes.isEmpty {
                StoryTile(title: notes.count == 1 ? "Note" : "Notes", trailing: nil) {
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, text in
                        Text(text)
                            .font(Tokens.Typography.metadata)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var notes: [String] {
        session.recordIDs.compactMap { id in
            let text = (store.metadataArchive.metadata(for: id)?.note ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
    }
}
