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
        let summary = searched.map { $0.isEmpty ? nil : Self.matchSummary($0) } ?? nil
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
                pane { content(searched: searched, insets: insets) }
                    .onChange(of: navigation.historyScrollRequest) { _ in
                        treeFocused = true
                        guard let target = navigation.historyScrollTarget else { return }
                        withAnimation(Tokens.Motion.animation(Tokens.Motion.swap, reduceMotion: reduceMotion)) {
                            proxy.scrollTo(target, anchor: .top)
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
    private func content(searched: [JournalEntry]?, insets: EdgeInsets) -> some View {
        if let searched, searched.isEmpty {
            EmptyState("No matching sessions",
                       detail: "Try a session name, a word from a note, an app, a category or a date.",
                       icon: "magnifyingglass")
                .padding(insets)
        } else if isEmptyArchive {
            emptyArchive.padding(insets)
        } else {
            VStack(alignment: .leading, spacing: Tokens.Space.xl) {
                headline
                if let searched {
                    HistorySearchResults(store: store, navigation: navigation, entries: searched)
                } else {
                    tree
                }
            }
            .padding(EdgeInsets(top: insets.top, leading: insets.leading - HistoryRowLayout.inset,
                                bottom: insets.bottom, trailing: insets.trailing - HistoryRowLayout.inset))
        }
    }

    private var headline: some View {
        let line = HistoryRowText.headline(top: store.historyTop(), summary: store.historySummary(),
                                           calendar: SessionStore.historyCalendar)
        return StoryHeadline(eyebrow: line.eyebrow, sentence: line.sentence, facts: line.facts,
                             highlight: Tokens.duration(store.historySummary().focused))
            .padding(.horizontal, HistoryRowLayout.inset)
    }

    private var tree: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(store.historyRows(under: nil)) { row in
                HistoryTreeRow(store: store, navigation: navigation, row: row, depth: 0)
            }
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

/// The days a search matched, newest first, each open to its matching
/// sessions, with the month named between months.
struct HistorySearchResults: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    let entries: [JournalEntry]

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(entries) { entry in
                switch entry {
                case .month(let month):
                    Text(HistoryMonthHeader.title(month.start))
                        .font(Tokens.Typography.metadata.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, HistoryRowLayout.inset)
                        .padding(.top, Tokens.Space.m)
                        .accessibilityAddTraits(.isHeader)
                case .day(let day):
                    Text(HistoryDayHeader.title(day.date, isToday: Calendar.current.isDate(day.date, inSameDayAs: store.now())))
                        .font(Tokens.Typography.metadata.weight(.semibold))
                        .padding(.horizontal, HistoryRowLayout.inset)
                        .padding(.top, Tokens.Space.s)
                        .accessibilityAddTraits(.isHeader)
                    HistoryDaySessions(store: store, navigation: navigation, day: day.date, only: day.threads)
                }
            }
        }
    }
}
