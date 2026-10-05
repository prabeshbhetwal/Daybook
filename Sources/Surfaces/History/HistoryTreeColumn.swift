import SwiftUI
import AppKit

/// History's column: the top period's headline, the search, and the tree
/// of rows that unfolds in place. A search replaces the tree with the days
/// that matched, each open to its matching sessions.
struct HistoryTree: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    @Environment(\.focusInterfaceDensity) private var density
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Rows are buttons, and a clicked button never takes focus on macOS,
    /// so a click hands focus to the tree itself: ↑, ↓, ←, →, Return and
    /// Escape then reach it. The search field keeps its own cursor.
    @FocusState private var treeFocused: Bool
    var scrolls = true

    static let keyboardHint = "Up and down arrows move through the rows; Return opens or folds one; "
        + "left and right fold and open; Escape folds the deepest open row"

    private var isEmptyArchive: Bool { !store.historyFilter.isActive && store.historyDays.isEmpty }

    var body: some View {
        let insets = StoryStyle.columnInsets(for: density)
        let searched = store.historyFilter.isActive ? store.historyJournal() : nil
        let lens = searched == nil ? nil : store.historyAppLens()
        let summary = searched.map { $0.isEmpty ? nil : Self.matchSummary($0) } ?? nil
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                // The count is in the field; the headline below adds it up.
                HistoryFindBar(store: store, focusRequest: navigation.historySearchFocusRequest,
                               matchCount: searched.map { Self.fieldCount($0, lens: lens) })
                    .coachAnchor(.search)
                // A search replaces the tree, so there is no path to show; and
                // with nothing open the path is only the headline's own name.
                if searched == nil, !isEmptyArchive, crumbs.count > 1 {
                    HistoryPathBar(crumbs: crumbs) { crumb in
                        switch crumb.focus {
                        case .row(let place): navigation.navigateHistory(to: place)
                        case nil: navigation.navigateHistory(to: nil)
                        // The session is the place already; bring it back into view.
                        case .session: navigation.revealHistory(target: crumb.target, focus: crumb.focus)
                        }
                    }
                }
            }
            .padding(EdgeInsets(top: insets.top, leading: insets.leading,
                                bottom: Tokens.Space.m, trailing: insets.trailing))
            Divider()
            ScrollViewReader { proxy in
                pane { content(searched: searched, lens: lens, insets: insets) }
                    .onChange(of: navigation.historyScrollRequest) { _ in
                        treeFocused = true
                        guard let target = navigation.historyScrollTarget else { return }
                        // A frame later, once the rows that opened or folded are
                        // laid out: measured against the old layout, a scroll after
                        // a long day folded stopped where the day had been, below
                        // the end of the list, and the column showed blank.
                        DispatchQueue.main.async {
                            withAnimation(Tokens.Motion.animation(Tokens.Motion.swap, reduceMotion: reduceMotion)) {
                                proxy.scrollTo(target, anchor: .top)
                            }
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(StoryStyle.canvas)
        .announcesChanges(to: summary.map(DurationText.spoken(in:)))
        .onAppear { navigation.prepareHistory() }
        // Midnight re-clips the rows holding today, and a longer record can
        // step the top up: the open path is re-read as the rows now drawn.
        .onChange(of: store.historyTop()) { _ in navigation.reconcileHistory() }
        .storyRenderEvidence(isEmptyArchive ? .historyEmpty : .historyTree)
    }

    @ViewBuilder private func pane<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if scrolls {
            ScrollView { content() }
        } else {
            content().frame(maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private func content(searched: [JournalEntry]?, lens: HistoryAppLens?, insets: EdgeInsets) -> some View {
        // An app used only outside sessions has no matching session, but
        // still has a story to tell.
        if let searched, searched.isEmpty, lens?.days.isEmpty ?? true {
            EmptyState("No matching sessions",
                       detail: "Try fewer words, or a session name, an old name, a word from a note, "
                           + "a named break, an app, a category, a date or a time of day.",
                       icon: "magnifyingglass")
                .padding(insets)
        } else if isEmptyArchive {
            emptyArchive.padding(insets)
        } else {
            VStack(alignment: .leading, spacing: Tokens.Space.xl) {
                if let searched {
                    // The record's headline describes the record, not the
                    // matches: a search opens with its own.
                    HistorySearchColumn(store: store, navigation: navigation, entries: searched, lens: lens)
                } else {
                    headline
                    overviewChart
                    tree
                }
            }
            .padding(EdgeInsets(top: insets.top, leading: insets.leading - HistoryRowLayout.inset,
                                bottom: insets.bottom, trailing: insets.trailing - HistoryRowLayout.inset))
        }
    }

    private var crumbs: [HistoryCrumb] {
        let session = navigation.historySession.flatMap { pick in
            store.journalSession(thread: pick.thread, on: pick.day).map {
                (thread: pick.thread, day: pick.day, title: $0.workType.sessionTitle(named: $0.name))
            }
        }
        return HistoryPath.crumbs(top: store.historyTop(), open: navigation.historyOpen, session: session,
                                  today: store.now(), calendar: SessionStore.historyCalendar)
    }

    private var headline: some View {
        let line = HistoryRowText.headline(top: store.historyTop(), summary: store.historySummary(),
                                           calendar: SessionStore.historyCalendar)
        return StoryHeadline(eyebrow: line.eyebrow, sentence: line.sentence, facts: line.facts,
                             highlight: Tokens.duration(store.historySummary().focused))
            .padding(.horizontal, HistoryRowLayout.inset)
            .id(HistoryPath.topID)
    }

    /// Every day on record as a bar in its main category's colour, against
    /// the average focused day. A day clicked opens in the tree below.
    private var overviewChart: some View {
        let top = store.historyTop()
        let summary = store.historySummary()
        let calendar = Calendar.current
        var values: [Date: HistoryResultChart.Value] = [:]
        for day in store.historyDays where day.focused > 0 {
            let main = day.focusByWorkType.max { $0.value == $1.value ? $0.key.rawValue > $1.key.rawValue : $0.value < $1.value }?.key
            values[calendar.startOfDay(for: day.date)] = HistoryResultChart.Value(
                primary: day.focused, secondary: 0, colour: main.map(Tokens.Palette.workType))
        }
        return HistoryResultChart(firstDay: top.firstDay, today: top.today, values: values, isLens: false,
                                  onPick: { navigation.openHistory(day: $0) },
                                  average: summary.focusedDays > 0 ? summary.focused / Double(summary.focusedDays) : nil,
                                  hint: "Click a day to open it")
            .padding(.horizontal, HistoryRowLayout.inset)
    }

    private var tree: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(store.historyRows(under: nil)) { row in
                HistoryTreeRow(store: store, navigation: navigation, row: row, depth: 0)
            }
        }
        // The spine the top cards hang from, through their dots.
        .background(alignment: .leading) {
            Rectangle()
                .fill(StoryStyle.line)
                .frame(width: 2)
                .padding(.leading, HistoryRowLayout.inset + HistoryTreeRow.dotSize / 2 - 1)
                .padding(.vertical, Tokens.Space.l)
                .accessibilityHidden(true)
        }
        .coachAnchor(.journal)
        // Key focus lives on a point-sized proxy off the left edge: the arrow,
        // Return and Escape handlers below still receive it, and macOS draws
        // its focus ring around nothing. On the list itself, the ring framed
        // the whole tree after every click.
        .overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: 0, height: 0)
                .offset(x: -4_000)
                .focusable()
                .focused($treeFocused)
                .accessibilityHidden(true)
        }
        .onMoveCommand { direction in
            switch direction {
            case .up: navigation.stepHistoryFocus(by: -1)
            case .down: navigation.stepHistoryFocus(by: 1)
            case .left: navigation.moveHistoryFocus(open: false)
            case .right: navigation.moveHistoryFocus(open: true)
            @unknown default: return
            }
            if let spoken = Self.spoken(navigation.historyFocus, store: store, open: navigation.historyOpen) {
                Announcement.post(spoken)
            }
        }
        .onCommand(#selector(NSStandardKeyBindingResponding.insertNewline(_:))) {
            navigation.activateHistoryFocus()
        }
        .onExitCommand { navigation.foldDeepestHistory() }
    }

    /// `12 sessions match · 8h 20m of focus`, then `· 2 breaks` when breaks
    /// matched too; `2 breaks match` when only breaks did.
    static func matchSummary(_ entries: [JournalEntry]) -> String {
        let (sessions, breaks, worked) = tally(entries)
        let breakCount = breaks == 1 ? "1 break" : "\(breaks) breaks"
        if sessions == 0 && breaks > 0 { return breakCount + (breaks == 1 ? " matches" : " match") }
        let noun = sessions == 1 ? "session matches" : "sessions match"
        let summary = "\(sessions) \(noun) · \(Tokens.duration(worked)) of focus"
        return breaks > 0 ? summary + " · " + breakCount : summary
    }

    /// `12 sessions`, `12 sessions · 2 breaks`, `2 breaks` or `No matches`:
    /// the count in the field while a search runs.
    static func matchCount(_ entries: [JournalEntry]) -> String {
        let (sessions, breaks, _) = tally(entries)
        let sessionCount = sessions == 1 ? "1 session" : "\(sessions) sessions"
        let breakCount = breaks == 1 ? "1 break" : "\(breaks) breaks"
        switch (sessions, breaks) {
        case (0, 0): return "No matches"
        case (0, _): return breakCount
        case (_, 0): return sessionCount
        default: return sessionCount + " · " + breakCount
        }
    }

    /// The field's count. A picked app counts the sessions its story lists,
    /// the running one included, and one used only outside sessions says so
    /// rather than "No matches" over its own story.
    static func fieldCount(_ entries: [JournalEntry], lens: HistoryAppLens?) -> String {
        guard let lens else { return matchCount(entries) }
        switch lens.sessions.count {
        case 0: return lens.outsideTotal > 0 ? "Outside sessions only" : "No sessions"
        case 1: return "1 session"
        case let count: return "\(count) sessions"
        }
    }

    static func tally(_ entries: [JournalEntry]) -> (sessions: Int, breaks: Int, worked: TimeInterval) {
        var sessions = 0
        var breaks = 0
        var worked: TimeInterval = 0
        for case .day(let day) in entries {
            sessions += day.sessions
            breaks += day.breaks
            worked += day.focused
        }
        return (sessions, breaks, worked)
    }

    /// What a row says when the keyboard lands on it: its VoiceOver label,
    /// with whether it is open. Nothing for a place the tree no longer draws.
    static func spoken(_ focus: HistoryFocus?, store: SessionStore, open: [HistoryPlace]) -> String? {
        switch focus {
        case .row(let place):
            let top = store.historyTop()
            let depth = place.level.rawValue - top.rootLevel.rawValue
            guard depth >= 0 else { return nil }
            var parent: HistoryPlace?
            if depth > 0 {
                let path = HistoryTreeBuilder.path(to: place.start, top: top, calendar: SessionStore.historyCalendar)
                guard path.indices.contains(depth - 1) else { return nil }
                parent = path[depth - 1]
            }
            guard let row = store.historyRows(under: parent).first(where: { $0.place == place }) else { return nil }
            let isOpen = open.indices.contains(depth) && open[depth] == place
            return DurationText.spoken(in: HistoryRowText.spoken(row, today: store.now(), isOpen: isOpen, depth: depth,
                                                                calendar: SessionStore.historyCalendar))
        case .session(let thread, let day):
            return store.journalSession(thread: thread, on: day).map(HistorySessionRow.spokenLabel)
        case nil:
            return nil
        }
    }

    private var emptyArchive: some View {
        StoryTile(title: "Nothing recorded yet", trailing: nil) {
            Text("History fills in as you work. Each day you record appears here, newest first, "
                 + "with its sessions one click away.")
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            StartButton(title: "Start focus", fills: false) {
                navigation.focusSessionControls()
            }
            .fixedSize()
            .accessibilityHint("Returns to the story, with the cursor in the activity field")
        }
        .frame(maxWidth: 520, alignment: .leading)
    }
}
