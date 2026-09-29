import SwiftUI
import AppKit
import Combine

enum AppTab: String, CaseIterable, Identifiable {
    case focus
    case today
    case story
    case review
    case insights
    case awards
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: return "Focus"
        case .today: return "Today"
        case .review: return "Review"
        case .story: return "Story"
        case .insights: return "Insights"
        case .awards: return "Awards"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .focus: return "target"
        case .today: return "calendar"
        case .review: return "chart.bar"
        case .story: return "book.pages"
        case .insights: return "sparkles"
        case .awards: return "rosette"
        case .settings: return "gearshape"
        }
    }

    var commandNumber: Int {
        switch self {
        case .focus: return 1
        case .today: return 2
        case .story: return 3
        case .review: return 4
        case .insights: return 5
        case .awards: return 6
        case .settings: return 7
        }
    }

    func moved(by delta: Int) -> AppTab {
        let tabs = Array(Self.allCases)
        guard !tabs.isEmpty else { return self }
        let index = tabs.firstIndex(of: self) ?? 0
        let offset = ((index + (delta % tabs.count)) + tabs.count) % tabs.count
        return tabs[offset]
    }
}

enum ReviewSection: String, CaseIterable {
    case week
    case month
    case history
}

/// The groupings the period projections read at. There is no Year: a year is
/// twelve months, so a separate grouping would have been the same evidence at
/// lower resolution under a second name.
enum InsightRange: String, CaseIterable {
    case day
    case week
    case month
}

/// What fills the window below the chrome: the story, or History's journal
/// of the past.
enum MainReadingWorkspace: String, CaseIterable {
    case story
    case history
}

enum MainWindowFocusTarget: Equatable {
    case sessionControls
    case settings
}

enum SessionControlsAction {
    case timerPill
    case commandOrMenu
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case focus
    case categories
    case away
    case automatic
    case activities
    case tracking
    case appearance
    case data
    case advanced

    var id: String { rawValue }
}

enum InterfaceDensity: String, CaseIterable {
    case comfortable
    case compact
}

enum AppearancePreference: String, CaseIterable {
    case system
    case light
    case dark

    /// Light and Dark are intentional application-wide overrides. System is
    /// represented by nil so the app returns to AppKit's inherited appearance
    /// and continues following a live macOS appearance change.
    func apply(to application: NSApplication) {
        let appearanceName: NSAppearance.Name?
        switch self {
        case .system: appearanceName = nil
        case .light: appearanceName = .aqua
        case .dark: appearanceName = .darkAqua
        }
        application.appearance = appearanceName.flatMap(NSAppearance.init(named:))
    }
}

/// The panels attached over the story. History is a reading workspace and
/// session controls are an in-window strip, so neither is a sheet.
enum StorySheetKind: String, CaseIterable, Identifiable {
    case awards, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .awards: return "Awards"
        case .settings: return "Settings"
        }
    }
}

/// A session picked in History: its thread on that day.
struct HistorySessionPick: Hashable {
    let thread: UUID
    let day: Date
}

/// The window's route. `AppTab` is only the vocabulary callers use to ask for
/// a place; what is showing is `workspace`, `sheet` and the session strip.
@MainActor final class MainWindowModel: ObservableObject {
    @Published private(set) var workspace: MainReadingWorkspace = .story
    @Published private(set) var requestedDate: Date?
    /// Bumped when the journal should bring the selection into view.
    @Published private(set) var historyScrollRequest = 0
    /// The rows open in History, root first. One row per level; opening a
    /// sibling folds the row that was open there.
    @Published private(set) var historyOpen: [HistoryPlace] = []
    /// The session the rail describes, under an open day.
    @Published private(set) var historySession: HistorySessionPick?
    /// The row the keyboard stands on.
    @Published private(set) var historyFocus: HistoryFocus?
    /// The row to bring into view when `historyScrollRequest` bumps.
    @Published private(set) var historyScrollTarget: String?
    private var historyPrepared = false

    var historyDeepestOpen: HistoryPlace? { historyOpen.last }

    /// The day History is inspecting: an open day, or a picked session's day.
    var reviewSelectedDate: Date? {
        historySession?.day ?? historyOpen.last(where: { $0.level == .day })?.start
    }
    /// The sheet over the story, if any. The story itself is always a day.
    @Published private(set) var sheet: StorySheetKind?
    /// Transient expansion belongs to navigation, not session state. A
    /// separately persisted pin may keep the strip visible across relaunch.
    @Published private(set) var sessionControlsExpanded = false
    @Published private(set) var focusRestorationRequest: MainWindowFocusTarget?
    /// Asks History's search field for the cursor (⌘F). The field is always
    /// shown; the journal narrows to matches while a query or filter is active.
    @Published private(set) var historySearchFocusRequest = 0
    @Published var settingsSection: SettingsSection = .general
    /// The most recent ask to open a category for editing, or a blank form.
    /// A counter travels with it so the same ask made twice — Add, close,
    /// Add — is two events and not one.
    @Published private(set) var categoryEditorRequest: CategoryEditorTicket?
    /// The session whose full report is open over the story, or nil.
    @Published private(set) var reportSession: DaySession?
    @Published var settingsQuery: String = ""
    private weak var store: SessionStore?

    init(opening route: AppTab = .story,
         requestedDate: Date? = nil,
         store: SessionStore? = nil) {
        self.requestedDate = requestedDate
        // A model built on a sheet's route is already presenting that sheet, or
        // restoring one would show the story with no sign of what was asked for.
        switch route {
        case .focus:
            self.workspace = .story
            self.sheet = nil
            self.sessionControlsExpanded = true
        case .review, .insights:
            self.workspace = .history
            self.sheet = nil
        case .awards:
            self.workspace = .story
            self.sheet = .awards
        case .settings:
            self.workspace = .story
            self.sheet = .settings
        case .story, .today:
            self.workspace = .story
            self.sheet = nil
        }
        if let store { connect(to: store) }
    }

    func open(tab: AppTab) {
        if tab == .focus {
            performSessionControlsAction(.commandOrMenu)
            return
        }
        animated(Tokens.Motion.swap) {
            switch tab {
            case .review:
                // History is the reading page across spans; the archive's
                // days feed its search.
                workspace = .history
                sheet = nil
                store?.refreshReview()
                store?.refreshInsights()
                prepareHistory()
            case .insights:
                workspace = .history
                sheet = nil
                store?.refreshInsights()
                prepareHistory()
            case .story:
                workspace = .story
                sheet = nil
            case .awards:
                sheet = .awards
            case .settings:
                sheet = .settings
            case .today, .focus:
                sheet = nil
            }
        }
        if tab == .today {
            openToday(date: store?.now() ?? Date())
        }
    }

    func openToday(date: Date) {
        requestedDate = date
        animated(Tokens.Motion.swap) {
            workspace = .story
            sheet = nil
            store?.selectDay(offset: 0)
        }
    }

    // MARK: - History's tree

    /// The first time History shows: unfold to this week. Later openings
    /// keep whatever the reader left open, as does a day opened before
    /// History was ever shown, by a search or a Jump to date.
    func prepareHistory() {
        guard !historyPrepared else { return }
        historyPrepared = true
        guard historyOpen.isEmpty, let store else { return }
        historyOpen = HistoryTreeBuilder.pathToToday(top: store.historyTop(), calendar: SessionStore.historyCalendar)
    }

    private func historyDepth(of place: HistoryPlace) -> Int? {
        guard let store else { return nil }
        let depth = place.level.rawValue - store.historyTop().rootLevel.rawValue
        // A row is only on screen when every level above it is open.
        return depth >= 0 && depth <= historyOpen.count ? depth : nil
    }

    /// Click or Return on a row: open it, folding the sibling that was open
    /// at its level; or fold it and everything under it.
    func toggleHistory(_ place: HistoryPlace) {
        guard let store, let depth = historyDepth(of: place) else { return }
        let parent = depth == 0 ? nil : historyOpen[depth - 1]
        guard let row = store.historyRows(under: parent).first(where: { $0.place == place }), !row.isEmpty else { return }
        animated(Tokens.Motion.reveal) {
            historySession = nil
            if historyOpen.indices.contains(depth), historyOpen[depth] == place {
                historyOpen = Array(historyOpen.prefix(depth))
            } else {
                historyOpen = Array(historyOpen.prefix(depth)) + [place]
                historyScrollTarget = place.id
                historyScrollRequest &+= 1
            }
            historyFocus = .row(place)
        }
    }

    /// Escape: fold the deepest open row. False when nothing was open.
    @discardableResult
    func foldDeepestHistory() -> Bool {
        guard let last = historyOpen.last else { return false }
        animated(Tokens.Motion.dismiss) {
            historySession = nil
            historyOpen.removeLast()
            historyFocus = .row(last)
        }
        return true
    }

    /// Jump to date and search: unfold down to the day and open it.
    func openHistory(day: Date) {
        let calendar = SessionStore.historyCalendar
        let path: [HistoryPlace]
        if let store {
            path = HistoryTreeBuilder.path(to: day, top: store.historyTop(), calendar: calendar)
        } else {
            // No store yet: the day is still the one History is inspecting.
            let start = calendar.startOfDay(for: day)
            path = [HistoryPlace(level: .day, span: DateInterval(start: start,
                                                                   end: HistoryTreeBuilder.dayAfter(start, calendar: calendar)))]
        }
        animated(Tokens.Motion.reveal) {
            historySession = nil
            historyOpen = path
            if let last = path.last {
                historyFocus = .row(last)
                historyScrollTarget = last.id
                historyScrollRequest &+= 1
            }
        }
    }

    /// A session row clicked: the rail describes it. Its day is opened if
    /// it was not, so the row is on screen.
    func selectHistory(session thread: UUID, on day: Date) {
        let day = SessionStore.historyCalendar.startOfDay(for: day)
        if historyOpen.last?.level != .day || historyOpen.last?.start != day { openHistory(day: day) }
        animated(Tokens.Motion.selection) {
            historySession = HistorySessionPick(thread: thread, day: day)
            historyFocus = .session(thread: thread, day: day)
        }
    }

    private func historyVisible() -> [HistoryFocus] {
        guard let store else { return [] }
        return HistoryTreeBuilder.visible(open: historyOpen, rows: { store.historyRows(under: $0) },
                                          threads: { store.journalThreads(on: $0, only: nil) })
    }

    /// ↑ and ↓: one visible row at a time. With no focus, ↓ lands on the
    /// first row and ↑ on the last.
    func stepHistoryFocus(by delta: Int) {
        let stops = historyVisible()
        guard !stops.isEmpty else { return }
        let next: HistoryFocus
        if let current = historyFocus, let index = stops.firstIndex(of: current) {
            next = stops[max(0, min(stops.count - 1, index + delta))]
        } else {
            next = delta > 0 ? stops[0] : stops[stops.count - 1]
        }
        animated(Tokens.Motion.selection) {
            historyFocus = next
            if case .session(let thread, let day) = next { historySession = HistorySessionPick(thread: thread, day: day) }
            switch next {
            case .row(let place): historyScrollTarget = place.id
            case .session(let thread, _): historyScrollTarget = "session-\(thread.uuidString)"
            }
            historyScrollRequest &+= 1
        }
    }

    /// Return: open or fold the focused row; select the focused session.
    func activateHistoryFocus() {
        switch historyFocus {
        case .row(let place): toggleHistory(place)
        case .session(let thread, let day): selectHistory(session: thread, on: day)
        case nil: stepHistoryFocus(by: 1)
        }
    }

    /// → opens a folded row; ← folds an open one, or moves to its parent.
    func moveHistoryFocus(open: Bool) {
        guard case .row(let place) = historyFocus, let depth = historyDepth(of: place) else {
            if !open, case .session(_, let day) = historyFocus,
               let dayPlace = historyOpen.last, dayPlace.level == .day, dayPlace.start == day {
                animated(Tokens.Motion.selection) { historyFocus = .row(dayPlace) }
            }
            return
        }
        let isOpen = historyOpen.indices.contains(depth) && historyOpen[depth] == place
        if open, !isOpen { toggleHistory(place) }
        if !open {
            if isOpen { toggleHistory(place) } else if depth > 0 {
                animated(Tokens.Motion.selection) { historyFocus = .row(historyOpen[depth - 1]) }
            }
        }
    }

    /// Surfaces transition on these values, and a transition runs only
    /// inside an animated transaction. A value animation on a container
    /// animates properties; it does not animate one view being replaced by
    /// another. Every button, key command and AppKit callback that changes
    /// these values comes through here, so the transaction is made here.
    private func animated(_ animation: Animation, _ body: () -> Void) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            body()
        } else {
            withAnimation(animation) { body() }
        }
    }

    func openSheet(_ kind: StorySheetKind) {
        sheet = kind
    }

    func closeSheet() {
        if sheet == .settings { focusRestorationRequest = .settings }
        sheet = nil
    }

    /// One source-typed boundary for every session-controls invocation. The
    /// pill is a disclosure and therefore toggles; commands and menu routes are
    /// idempotent reveals and can never hide an already-visible strip.
    func performSessionControlsAction(_ action: SessionControlsAction) {
        animated(sessionControlsExpanded ? Tokens.Motion.dismiss : Tokens.Motion.reveal) {
            switch action {
            case .timerPill: sessionControlsExpanded.toggle()
            case .commandOrMenu: sessionControlsExpanded = true
            }
        }
    }

    func dismissSessionControls() {
        animated(Tokens.Motion.dismiss) { sessionControlsExpanded = false }
        focusRestorationRequest = .sessionControls
    }

    func consumeFocusRestorationRequest() {
        focusRestorationRequest = nil
    }

    func revealApplication() {
        // A generic window-open action keeps the visible reading workspace.
        // It only dismisses an attached panel such as Settings.
        closeSheet()
    }

    /// The navigation model owns the route, while SessionStore owns the day.
    /// Bind once at the production composition root; deferred requests from a
    /// menu before the window exists are consumed here as well.
    func connect(to store: SessionStore) {
        guard self.store !== store else { return }
        self.store = store
        if store.period != .day { store.period = .day }
        // Binding happens at launch, before any window exists. Visibility is
        // the story canvas's to claim when it appears; claiming it here kept
        // the dashboard rebuilding every second behind a window never opened.
        refreshStory()
    }

    /// History's search reads the archive's day index, so the review read
    /// model stays live only while History is showing.
    private func refreshStory() {
        guard let store else { return }
        store.setReviewVisible(workspace == .history)
        store.refreshDashboard()
    }

    func openSettings() {
        openSheet(.settings)
    }

    /// Settings, on the Categories section, with the editor already open. The
    /// pickers open the floating `CategoryEditorPanel` instead; this is the
    /// deep link for anything that wants the full list.
    func openReport(for session: DaySession) {
        animated(Tokens.Motion.reveal) { reportSession = session }
    }

    func closeReport() {
        animated(Tokens.Motion.dismiss) { reportSession = nil }
    }

    func openCategoryEditor(_ request: CategoryEditorRequest) {
        settingsSection = .categories
        settingsQuery = ""
        categoryEditorRequest = CategoryEditorTicket(id: (categoryEditorRequest?.id ?? 0) &+ 1,
                                                     request: request)
        openSheet(.settings)
    }

    func returnToStory() {
        animated(Tokens.Motion.swap) {
            sheet = nil
            workspace = .story
        }
    }

    /// History, with the cursor in its search field.
    func findInHistory() {
        open(tab: .review)
        historySearchFocusRequest &+= 1
    }
}
