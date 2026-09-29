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

/// The window's route. `AppTab` is only the vocabulary callers use to ask for
/// a place; what is showing is `workspace`, `sheet` and the session strip.
@MainActor final class MainWindowModel: ObservableObject {
    @Published private(set) var workspace: MainReadingWorkspace = .story
    @Published private(set) var requestedDate: Date?
    /// What History's rail describes; nil reads as the current month. It is
    /// deliberately separate from `requestedDate`: picking in History explains
    /// a month, day or session in place, while `requestedDate` moves the story.
    @Published private(set) var historySelection: HistorySelection?
    /// Bumped when the journal should bring the selection into view.
    @Published private(set) var historyScrollRequest = 0

    /// The day History is inspecting: a picked day, or a picked session's day.
    var reviewSelectedDate: Date? { historySelection?.day }
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
            case .insights:
                workspace = .history
                sheet = nil
                store?.refreshInsights()
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
            showDay(date)
        }
    }

    /// Inspection, not navigation. The tab and Today's own scope are untouched;
    /// the date is normalised so one literal local day identifies the selection
    /// however the caller expressed it.
    func selectReviewDay(_ date: Date, calendar: Calendar = .current) {
        historySelection = .day(calendar.startOfDay(for: date))
    }

    func clearReviewDay() {
        historySelection = nil
    }

    func historySelectionOrDefault(calendar: Calendar = .current) -> HistorySelection {
        if let historySelection { return historySelection }
        let now = store?.now() ?? Date()
        return .month(calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now))
    }

    func selectHistory(_ selection: HistorySelection, scrolling: Bool = false) {
        animated(Tokens.Motion.selection) { historySelection = selection }
        if scrolling { historyScrollRequest &+= 1 }
    }

    /// The calendar picked a day: History selects it and scrolls to it. A day
    /// with nothing recorded has no row, so its month is selected instead.
    func jumpToHistoryDay(_ date: Date, calendar: Calendar = .current) {
        let entries = store?.historyJournal() ?? []
        selectHistory(HistoryJournalBuilder.selection(forJump: date, in: entries, calendar: calendar),
                      scrolling: true)
    }

    /// ↑ and ↓ in the journal: one row at a time, the list following.
    func stepHistorySelection(by delta: Int) {
        guard let store else { return }
        let entries = store.historyJournal()
        var only: [Date: Set<UUID>] = [:]
        for case .day(let day) in entries { if let threads = day.threads { only[day.date] = threads } }
        let next = HistoryJournalBuilder.step(from: historySelectionOrDefault(), by: delta, entries: entries,
                                              threads: { store.journalThreads(on: $0, only: only[$0]) })
        selectHistory(next, scrolling: true)
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
        if let requestedDate { showDay(requestedDate) }
        refreshStory()
    }

    /// The chrome's calendar picked a day: show it as the day's story. Story
    /// may deliberately inspect an empty historical date; only future dates
    /// are clamped.
    func jumpToDay(_ date: Date) {
        showDay(date)
    }

    /// A day found in History, opened as the front page's story.
    func openDay(_ date: Date) {
        lastPeriodStep = 0
        animated(Tokens.Motion.swap) {
            workspace = .story
            sheet = nil
            showDay(date)
            refreshStory()
        }
    }

    private func showDay(_ date: Date) {
        guard let store else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: store.now())
        let target = min(today, calendar.startOfDay(for: date))
        let offset = calendar.dateComponents([.day], from: target, to: today).day ?? 0
        store.selectDay(offset: max(0, offset))
    }

    /// Which way the reader last stepped: +1 forward, -1 back, 0 when the
    /// day was jumped to instead. The story's transition reads it.
    @Published private(set) var lastPeriodStep = 0

    func stepStoryPeriod(by delta: Int) {
        guard let store else { return }
        lastPeriodStep = delta
        animated(Tokens.Motion.swap) { store.stepDay(by: delta) }
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
