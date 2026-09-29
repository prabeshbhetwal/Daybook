import SwiftUI
import AppKit

/// History below the chrome: the journal, and beside it the rail for what
/// the journal has selected.
struct HistoryWorkspace: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    var scrolls = true

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            HistoryJournal(store: store, navigation: navigation, scrolls: scrolls)
            Divider()
            Group {
                if scrolls {
                    ScrollView { HistoryJournalRail(store: store, navigation: navigation) }
                } else {
                    HistoryJournalRail(store: store, navigation: navigation)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(width: StoryLayout.railWidth)
            .background(StoryStyle.rail)
        }
        .background(Tokens.Colour.ground)
    }
}

/// History as one list, newest first, back to the first recorded day: each
/// month under its figures, each day under its total, every session on its
/// own row. The search stays above it; a search narrows the same list.
struct HistoryJournal: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    @Environment(\.focusInterfaceDensity) private var density
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Rows are buttons, and a clicked button never takes focus on macOS, so
    /// a pick in the list or the calendar hands focus to the list itself:
    /// ↑, ↓ and Return then reach it. Typing in the search changes no
    /// selection, so the search field keeps its cursor.
    @FocusState private var listFocused: Bool
    var scrolls = true

    /// Spoken on the rows that ↑, ↓ and Return act on.
    static let keyboardHint = "Up and down arrows move through the list; Return opens the selected day"

    private var isEmptyArchive: Bool { !store.historyFilter.isActive && store.historyDays.isEmpty }

    var body: some View {
        let entries = store.historyJournal()
        let selection = navigation.historySelectionOrDefault()
        let summary = store.historyFilter.isActive && !entries.isEmpty ? Self.matchSummary(entries) : nil
        let insets = StoryStyle.columnInsets(for: density)
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                HistoryFindBar(store: store, focusRequest: navigation.historySearchFocusRequest)
                    .coachAnchor(.search)
                if let summary {
                    Text(durations: summary)
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(EdgeInsets(top: insets.top, leading: insets.leading,
                                bottom: Tokens.Space.m, trailing: insets.trailing))
            Divider()
            ScrollViewReader { proxy in
                pane { content(entries, selection, insets: insets) }
                    .onChange(of: navigation.historyScrollRequest) { _ in
                        listFocused = true
                        guard let id = HistoryJournalBuilder.anchorID(
                            for: navigation.historySelectionOrDefault(), in: store.historyJournal()) else { return }
                        withAnimation(Tokens.Motion.animation(Tokens.Motion.swap, reduceMotion: reduceMotion)) {
                            proxy.scrollTo(id, anchor: .top)
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(StoryStyle.canvas)
        .announcesChanges(to: summary.map(DurationText.spoken(in:)))
        .onAppear { store.setInsightsVisible(true) }
        .onDisappear { store.setInsightsVisible(false) }
        .storyRenderEvidence(isEmptyArchive ? .historyEmpty : .historyJournal)
    }

    @ViewBuilder private func pane<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if scrolls {
            ScrollView { content() }
        } else {
            content().frame(maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private func content(_ entries: [JournalEntry], _ selection: HistorySelection,
                         insets: EdgeInsets) -> some View {
        if store.historyFilter.isActive && entries.isEmpty {
            EmptyState("No matching sessions",
                       detail: "Try a session name, a word from a note, an app, a category or a date.",
                       icon: "magnifyingglass")
                .padding(insets)
        } else if isEmptyArchive {
            emptyArchive.padding(insets)
        } else {
            list(entries, selection)
                .padding(EdgeInsets(top: Tokens.Space.s, leading: insets.leading - HistoryRowLayout.inset,
                                    bottom: insets.bottom, trailing: insets.trailing - HistoryRowLayout.inset))
        }
    }

    private func list(_ entries: [JournalEntry], _ selection: HistorySelection) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(entries) { entry in
                switch entry {
                case .month(let month):
                    HistoryMonthHeader(month: month, isSelected: selection == .month(month.start)) {
                        select(.month(month.start))
                    }
                    .padding(.top, Tokens.Space.m)
                    .id(entry.id)
                case .day(let day):
                    HistoryDayGroup(store: store, navigation: navigation, day: day, selection: selection,
                                    select: select)
                        .id(entry.id)
                case .quiet(let quiet):
                    HistoryQuietRow(quiet: quiet)
                        .id(entry.id)
                }
            }
            if !store.historyFilter.isActive, let first = store.historyArchiveFacts().firstDay {
                Text(durations: Self.footerText(store.historyArchiveFacts(), since: first))
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, HistoryRowLayout.inset)
                    .padding(.top, Tokens.Space.xl)
            }
        }
        .coachAnchor(.journal)
        // ↑ and ↓ move the selection; Return opens the selected day's story,
        // the keyboard twin of a double-click.
        .focusable()
        .focused($listFocused)
        .onMoveCommand { direction in
            switch direction {
            case .up: navigation.stepHistorySelection(by: -1)
            case .down: navigation.stepHistorySelection(by: 1)
            default: return
            }
            // The highlight moves where a sighted reader looks; the row it
            // landed on is said for everyone else.
            if let spoken = Self.spoken(navigation.historySelectionOrDefault(), store: store) {
                Announcement.post(spoken)
            }
        }
        .onCommand(#selector(NSStandardKeyBindingResponding.insertNewline(_:))) {
            if let day = navigation.historySelectionOrDefault().day { navigation.openDay(day) }
        }
    }

    private func select(_ picked: HistorySelection) {
        navigation.selectHistory(picked)
        listFocused = true
    }

    private var emptyArchive: some View {
        StoryTile(title: "Nothing recorded yet", trailing: nil) {
            Text("History fills in as you work. Each day you record appears here, newest first, "
                 + "with its sessions one click away.")
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            StartButton(title: "Start focus", fills: false) {
                navigation.performSessionControlsAction(.commandOrMenu)
            }
            .fixedSize()
            .accessibilityHint("Opens the session controls to choose an activity")
        }
        .frame(maxWidth: 520, alignment: .leading)
    }

    /// What a row says when the keyboard lands on it: the same words as its
    /// VoiceOver label.
    static func spoken(_ selection: HistorySelection, store: SessionStore) -> String? {
        switch selection {
        case .month(let start):
            let month = HistoryJournalBuilder.month(starting: start, days: store.historyDays)
            return DurationText.spoken(in: "\(HistoryMonthHeader.title(start)), \(HistoryMonthHeader.facts(month))")
        case .day(let date):
            let isToday = Calendar.current.isDate(date, inSameDayAs: store.now())
            let title = HistoryDayHeader.title(date, isToday: isToday)
            let focused = store.historyJournal().lazy.compactMap { entry -> TimeInterval? in
                guard case .day(let day) = entry, day.date == date else { return nil }
                return day.focused
            }.first ?? 0
            return focused > 0 ? "\(title), \(Tokens.spent(focused)) focused" : title
        case .session(let thread, let day):
            return store.journalSession(thread: thread, on: day).map(HistorySessionRow.spokenLabel)
        }
    }

    /// `12 sessions match · 8h 20m of focus`.
    static func matchSummary(_ entries: [JournalEntry]) -> String {
        var sessions = 0
        var worked: TimeInterval = 0
        for case .day(let day) in entries {
            sessions += day.sessions
            worked += day.focused
        }
        let noun = sessions == 1 ? "session matches" : "sessions match"
        return "\(sessions) \(noun) · \(Tokens.duration(worked)) of focus"
    }

    /// Where the journal ends: the whole record, said once.
    static func footerText(_ facts: HistoryArchiveFacts, since first: Date) -> String {
        var parts = ["On record since \(DateFormats.australian("d MMM yyyy").string(from: first))",
                     "\(Tokens.duration(facts.focused)) focused",
                     facts.dayCount == 1 ? "1 day" : "\(facts.dayCount) days",
                     facts.sessionCount == 1 ? "1 session" : "\(facts.sessionCount) sessions"]
        if facts.longestStreak > 1 { parts.append("longest streak \(facts.longestStreak) days") }
        return parts.joined(separator: " · ")
    }
}

/// A month's name, its figures, and a thin bar for each of its days.
struct HistoryMonthHeader: View {
    let month: JournalMonth
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                    Text(Self.title(month.start))
                        .font(Tokens.Typography.sectionTitle)
                    Spacer(minLength: Tokens.Space.s)
                    Text(durations: Self.facts(month))
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HistoryMonthBars(daily: month.dailyFocus)
            }
            .padding(.vertical, Tokens.Space.s)
            .padding(.horizontal, HistoryRowLayout.inset)
            .background(isSelected ? Tokens.Colour.focus.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(StoryPressStyle(hovers: true, cornerRadius: Tokens.Radius.nested))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DurationText.spoken(in: "\(Self.title(month.start)), \(Self.facts(month))"))
        .accessibilityAddTraits(isSelected ? [.isHeader, .isButton, .isSelected] : [.isHeader, .isButton])
        .accessibilityHint("Shows this month beside the list")
    }

    static func title(_ start: Date) -> String {
        DateFormats.australian("MMMM yyyy").string(from: start)
    }

    /// `14h 20m focused · 7 days · 2h 2m per focused day`.
    static func facts(_ month: JournalMonth) -> String {
        guard month.focused > 0 else { return "no focus recorded" }
        let days = month.focusedDays == 1 ? "1 day" : "\(month.focusedDays) days"
        return "\(Tokens.duration(month.focused)) focused · \(days) · "
            + "\(Tokens.duration(month.averagePerFocusedDay)) per focused day"
    }
}

/// One bar per calendar day, height by focus. The dates are in the rows
/// below, so the bars carry no labels.
struct HistoryMonthBars: View {
    let daily: [TimeInterval]

    var body: some View {
        let peak = max(daily.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(daily.enumerated()), id: \.offset) { _, seconds in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(seconds > 0 ? AnyShapeStyle(Tokens.Colour.focus) : AnyShapeStyle(StoryStyle.line))
                    .frame(maxWidth: .infinity)
                    .frame(height: seconds > 0 ? max(3, 18 * seconds / peak) : 2)
            }
        }
        .frame(height: 18, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// A day's header and its rows: sessions newest first, breaks between them.
struct HistoryDayGroup: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    let day: JournalDay
    let selection: HistorySelection
    let select: (HistorySelection) -> Void

    var body: some View {
        let isToday = Calendar.current.isDate(day.date, inSameDayAs: store.now())
        let projection = store.storyDayProjection(on: day.date)
        let rows = HistoryJournalBuilder.rows(projection, only: day.threads)
        return VStack(alignment: .leading, spacing: 0) {
            HistoryDayHeader(day: day, isToday: isToday, isSelected: selection == .day(day.date),
                             showsTotal: HistoryDayHeader.showsTotal(day: day, rows: rows),
                             onSelect: { select(.day(day.date)) },
                             onOpen: { navigation.openDay(day.date) })
            if let line = Self.line(day: day, rows: rows, isToday: isToday) {
                Text(durations: line)
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, HistoryRowLayout.inset)
                    .padding(.bottom, Tokens.Space.xs)
            }
            ForEach(rows) { entry in
                switch entry {
                case .session(let session):
                    let picked = HistorySelection.session(thread: session.threadID, day: day.date)
                    HistorySessionRow(session: session,
                                      apps: (projection.sessionDetails[session.id]?.apps ?? []).map(\.appName),
                                      note: store.journalNote(for: session)
                                          .flatMap { $0.split(whereSeparator: \.isNewline).first.map(String.init) },
                                      isSelected: selection == picked,
                                      onSelect: { select(picked) },
                                      onOpen: { navigation.openDay(day.date) })
                case .rest(let rest):
                    HistoryBreakRow(rest: rest)
                }
            }
        }
    }

    /// The line under a day header with no session: its app use, which a
    /// break beside it does not replace, or that nothing was recorded.
    static func line(day: JournalDay, rows: [DayEntry], isToday: Bool) -> String? {
        if day.isAppUseOnly { return "Recorded app use only · \(Tokens.duration(day.tracked))" }
        guard rows.isEmpty else { return nil }
        return isToday ? "Nothing recorded yet today" : "Nothing recorded"
    }
}

/// `Mon 28 Sep` and the day's focus: a heading, and the way into the day.
struct HistoryDayHeader: View {
    let day: JournalDay
    let isToday: Bool
    let isSelected: Bool
    /// False when the one row beneath already carries the day's figure.
    let showsTotal: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                // Selection is the tint, as on the month and session rows:
                // system blue on its own tint was 3.3:1.
                Text(Self.title(day.date, isToday: isToday))
                    .font(Tokens.Typography.metadata.weight(.bold))
                Spacer(minLength: Tokens.Space.s)
                if showsTotal {
                    Text(durations: Tokens.duration(day.focused))
                        .font(Tokens.Typography.metadata.weight(.semibold).monospacedDigit())
                }
            }
            .padding(.top, Tokens.Space.m)
            .padding(.bottom, Tokens.Space.xs)
            .padding(.horizontal, HistoryRowLayout.inset)
            .background(isSelected ? Tokens.Colour.focus.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(StoryPressStyle(hovers: true, cornerRadius: Tokens.Radius.nested))
        .simultaneousGesture(TapGesture(count: 2).onEnded { onOpen() })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DurationText.spoken(in: showsTotal
            ? "\(Self.title(day.date, isToday: isToday)), \(Tokens.duration(day.focused)) focused"
            : Self.title(day.date, isToday: isToday)))
        .accessibilityAddTraits(isSelected ? [.isHeader, .isButton, .isSelected] : [.isHeader, .isButton])
        .accessibilityHint(HistoryJournal.keyboardHint)
        .accessibilityAction(named: "Open as a story", onOpen)
    }

    /// The day's focus, unless the day is one finished session and nothing else
    /// and its row shows the same figure: then the header would say it twice.
    /// A running session's row says "in progress", so the header keeps the figure.
    static func showsTotal(day: JournalDay, rows: [DayEntry]) -> Bool {
        guard day.focused > 0 else { return false }
        if rows.count == 1, case .session(let session) = rows[0], !session.isRunning,
           Tokens.duration(day.focused) == Tokens.duration(session.worked) { return false }
        return true
    }

    static func title(_ date: Date, isToday: Bool) -> String {
        isToday ? "Today" : DateFormats.australian("EEE d MMM").string(from: date)
    }
}

/// One session: when, what, which category, how long; then the apps it used
/// and the first line of its note.
struct HistorySessionRow: View {
    let session: DaySession
    let apps: [String]
    let note: String?
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                Circle()
                    .fill(Tokens.Palette.workType(session.workType))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                        Text(Tokens.timeRange(session.start, session.end))
                            .font(Tokens.Typography.metadata.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(session.workType.sessionTitle(named: session.name))
                            .font(Tokens.Typography.rowTitle.weight(.medium))
                            .lineLimit(1)
                        // An unnamed session's title is its category already.
                        if !session.name.isEmpty { WorkTypeChip(workType: session.workType) }
                        Spacer(minLength: Tokens.Space.s)
                        Text(durations: session.isRunning ? "in progress" : Tokens.duration(session.worked))
                            .font(Tokens.Typography.metadata.weight(.semibold).monospacedDigit())
                    }
                    if let detail = Self.detail(apps: apps, note: note) {
                        Text(detail)
                            .font(Tokens.Typography.metadata)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, Tokens.Space.xs)
            .padding(.horizontal, HistoryRowLayout.inset)
            .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
            .background(isSelected ? Tokens.Colour.focus.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(StoryPressStyle(hovers: true, cornerRadius: Tokens.Radius.nested))
        .simultaneousGesture(TapGesture(count: 2).onEnded { onOpen() })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spokenLabel(session))
        .accessibilityValue(Self.detail(apps: apps, note: note) ?? "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(HistoryJournal.keyboardHint)
        .accessibilityAction(named: "Open its day's story", onOpen)
    }

    /// `8:30 am – 11:35 am, Refactor, Deep work, 2 hours 5 minutes`.
    static func spokenLabel(_ session: DaySession) -> String {
        var parts = [Tokens.timeRange(session.start, session.end)]
        if !session.name.isEmpty { parts.append(session.name) }
        parts.append(session.workType.displayName)
        parts.append(session.isRunning ? "in progress" : Tokens.spent(session.worked))
        return parts.joined(separator: ", ")
    }

    /// `Xcode, Terminal, Safari · “fixed the parser”`.
    static func detail(apps: [String], note: String?) -> String? {
        var parts: [String] = []
        if !apps.isEmpty { parts.append(apps.prefix(3).joined(separator: ", ")) }
        if let note, !note.isEmpty { parts.append("“\(note)”") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// A recorded break between sessions, named when it was named.
struct HistoryBreakRow: View {
    let rest: RestEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
            Circle()
                .fill(Tokens.Palette.warmGrey.opacity(0.55))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(Tokens.timeRange(rest.start, rest.end))
                .font(Tokens.Typography.metadata.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(rest.name.isEmpty ? "Break" : rest.name)
                .font(Tokens.Typography.metadata)
            Spacer(minLength: Tokens.Space.s)
            Text(durations: Tokens.duration(rest.length))
                .font(Tokens.Typography.metadata.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, HistoryRowLayout.inset)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Tokens.timeRange(rest.start, rest.end)), \(RestEntryRow.label(rest.name)), "
                            + Tokens.spent(rest.length))
    }
}

/// Days with nothing recorded, as one line.
struct HistoryQuietRow: View {
    let quiet: JournalQuiet

    var body: some View {
        Text(Self.text(quiet))
            .font(Tokens.Typography.metadata)
            .foregroundStyle(.secondary)
            .padding(.vertical, Tokens.Space.s)
            .padding(.horizontal, HistoryRowLayout.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `Tue 22 Sep · nothing recorded`, or `23 – 27 Sep · nothing recorded`.
    /// `DateFormats` formatters are shared and cached: read them, never set them.
    static func text(_ quiet: JournalQuiet) -> String {
        if quiet.isSingleDay {
            return "\(DateFormats.australian("EEE d MMM").string(from: quiet.last)) · nothing recorded"
        }
        return "\(DateFormats.australian("d").string(from: quiet.first)) – "
            + "\(DateFormats.australian("d MMM").string(from: quiet.last)) · nothing recorded"
    }
}
