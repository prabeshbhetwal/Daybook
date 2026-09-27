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

/// The spans History is read at. There is no Year: a year is twelve months,
/// and Month reaches twelve, so a separate span would have been the same
/// evidence at lower resolution under a second name.
enum InsightRange: String, CaseIterable {
    case day
    case week
    case month
}

enum MainReadingWorkspace: String, CaseIterable {
    case story
    case history
    case insights
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

/// Attached panels plus compatibility routes. History and Insights are reading
/// workspaces; Focus is intercepted into the in-window strip; Awards and
/// Settings remain attached sheets.
enum StorySheetKind: String, CaseIterable, Identifiable {
    case focus, history, insights, awards, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: return "Focus session"
        case .history: return "History"
        case .insights: return "History"
        case .awards: return "Awards"
        case .settings: return "Settings"
        }
    }

    var tab: AppTab {
        switch self {
        case .focus: return .focus
        case .history: return .review
        case .insights: return .insights
        case .awards: return .awards
        case .settings: return .settings
        }
    }

    init?(tab: AppTab) {
        switch tab {
        case .focus: self = .focus
        case .review: self = .history
        case .insights: self = .insights
        case .awards: self = .awards
        case .settings: self = .settings
        default: return nil
        }
    }
}

@MainActor final class MainWindowModel: ObservableObject {
    @Published var selectedTab: AppTab
    @Published private(set) var workspace: MainReadingWorkspace = .story
    @Published private(set) var requestedDate: Date?
    /// The day Review is inspecting, or nil when nothing is selected. It is
    /// deliberately separate from `requestedDate`: selecting evidence in Review
    /// explains a day in place, while `requestedDate` moves the user to Today.
    @Published private(set) var reviewSelectedDate: Date?
    /// Which span the Story surface is telling, the selected period day and the
    /// independently toggled inline child. Attached-panel state is separate.
    @Published private(set) var sheet: StorySheetKind?
    @Published var storyScope: StoryScope = .day {
        didSet {
            guard storyScope != oldValue else { return }
            storySelectedDay = nil
            expandedStoryDay = nil
            refreshStoryScope()
        }
    }
    @Published private(set) var storySelectedDay: Date?
    @Published private(set) var expandedStoryDay: Date?
    /// Transient expansion belongs to navigation, not session state. A
    /// separately persisted pin may keep the strip visible across relaunch.
    @Published private(set) var sessionControlsExpanded = false
    @Published private(set) var focusRestorationRequest: MainWindowFocusTarget?
    @Published var reviewSection: ReviewSection = .week
    /// The far end of a span picked on History's map, or nil for one day.
    @Published var historySelectedPeriod: Date?
    /// Whether History's search field is open (⌘F). Results replace the
    /// chart while a query or filter is active.
    @Published var historySearchShown = false
    @Published var insightRange: InsightRange = .week
    @Published private var insightAnchors: [InsightRange: Date]
    @Published private var insightPageCounts: [InsightRange: Int]
    @Published var settingsSection: SettingsSection = .general
    /// The most recent ask to open a category for editing, or a blank form.
    /// A counter travels with it so the same ask made twice — Add, close,
    /// Add — is two events and not one.
    @Published private(set) var categoryEditorRequest: CategoryEditorTicket?
    /// The session whose full report is open over the story, or nil.
    @Published private(set) var reportSession: DaySession?
    @Published var settingsQuery: String = ""
    private weak var store: SessionStore?
    private var periodObservation: AnyCancellable?

    init(selectedTab: AppTab = .story,
         storyScope: StoryScope = .day,
         requestedDate: Date? = nil,
         store: SessionStore? = nil) {
        self.selectedTab = selectedTab == .focus ? .story : selectedTab
        self.storyScope = storyScope
        self.requestedDate = requestedDate
        let insightToday = Calendar.current.startOfDay(for: store?.now() ?? Date())
        self.insightAnchors = Dictionary(uniqueKeysWithValues:
            InsightRange.allCases.map { ($0, insightToday) })
        self.insightPageCounts = [.day: 14, .week: 6, .month: 3]
        // Construction and selection must agree: a model built on a sheet-backed
        // tab is already presenting that sheet, or restoring one would show the
        // story with no sign of the surface that was asked for.
        switch selectedTab {
        case .focus:
            self.workspace = .story
            self.sheet = nil
            self.sessionControlsExpanded = true
        case .review:
            self.workspace = .insights
            self.sheet = nil
        case .insights:
            self.workspace = .insights
            self.sheet = nil
        default:
            self.workspace = .story
            self.sheet = StorySheetKind(tab: selectedTab)
        }
        if let store { connect(to: store) }
    }

    func select(_ tab: AppTab) {
        open(tab: tab)
    }

    func open(tab: AppTab) {
        if tab == .focus {
            performSessionControlsAction(.commandOrMenu)
            return
        }
        selectedTab = tab
        animated(Tokens.Motion.swap) {
            switch tab {
            case .review:
                // History is the reading page across spans; the archive's
                // days feed its Year span and its search.
                workspace = .insights
                sheet = nil
                reviewSection = .history
                store?.refreshReview()
                store?.refreshInsights()
            case .insights:
                workspace = .insights
                sheet = nil
                store?.refreshInsights()
            case .story:
                workspace = .story
                sheet = nil
            default:
                sheet = StorySheetKind(tab: tab)
            }
        }
        if tab == .today {
            openToday(date: store?.now() ?? Date())
        }
    }

    func openToday(date: Date) {
        requestedDate = date
        selectedTab = .today
        animated(Tokens.Motion.swap) {
            workspace = .story
            sheet = nil
            showDay(date)
            storyScope = .day
        }
    }

    /// Inspection, not navigation. The tab and Today's own scope are untouched;
    /// the date is normalised so one literal local day identifies the selection
    /// however the caller expressed it.
    func selectReviewDay(_ date: Date, calendar: Calendar = .current) {
        reviewSelectedDate = calendar.startOfDay(for: date)
    }

    func clearReviewDay() {
        reviewSelectedDate = nil
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
        switch kind {
        case .focus: performSessionControlsAction(.commandOrMenu)
        case .history: open(tab: .review)
        case .insights: open(tab: .insights)
        default:
            selectedTab = kind.tab
            sheet = kind
        }
    }

    func closeSheet() {
        if sheet == .settings { focusRestorationRequest = .settings }
        sheet = nil
        selectedTab = tab(for: workspace)
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

    func selectStoryDay(_ date: Date, calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: date)
        storySelectedDay = day
        if expandedStoryDay != nil { expandedStoryDay = day }
    }

    func toggleExpandedStoryDay(_ date: Date, calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: date)
        if let expandedStoryDay, calendar.isDate(expandedStoryDay, inSameDayAs: day) {
            self.expandedStoryDay = nil
        } else {
            storySelectedDay = day
            expandedStoryDay = day
        }
    }

    /// Compatibility action for existing period callers. A period day opens
    /// inline; only an already-Day-scoped caller changes the global Day date.
    func openStoryDay(_ date: Date, calendar: Calendar = .current) {
        if storyScope == .day {
            workspace = .story
            showDay(calendar.startOfDay(for: date))
            selectedTab = .story
        } else {
            toggleExpandedStoryDay(date, calendar: calendar)
        }
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
        periodObservation = store.$reviewDays.sink { [weak self] days in
            guard let self else { return }
            if let selected = self.storySelectedDay,
               !days.contains(where: { Calendar.current.isDate($0.date, inSameDayAs: selected) }) {
                self.storySelectedDay = nil
                self.expandedStoryDay = nil
            }
        }
        refreshStoryScope()
    }

    func selectScope(_ scope: StoryScope) {
        lastPeriodStep = 0
        animated(Tokens.Motion.swap) {
            workspace = .story
            sheet = nil
            selectedTab = .story
            if scope != storyScope, let store {
                let anchor = storyScope == .day ? store.selectedDay
                    : storySelectedDay ?? store.reviewAnchor ?? store.now()
                if scope == .day {
                    showDay(anchor)
                } else {
                    store.reviewAnchor = Calendar.current.startOfDay(for: anchor)
                }
            }
            storyScope = scope
            refreshStoryScope()
        }
    }

    /// Story may deliberately inspect an empty historical date. Do not silently
    /// replace it with the earliest recorded day; only future dates are clamped.
    /// The chrome's calendar picked a day: show it as the day's story,
    /// whichever span was showing. A week or month is a place to spot a day;
    /// the day is where it is read.
    func jumpToDay(_ date: Date) {
        if storyScope != .day { selectScope(.day) }
        showDay(date)
    }

    /// Insights and History point at a period; this opens it as its own story,
    /// at the span it was shown in.
    func openStory(_ scope: StoryScope, containing date: Date) {
        guard let store else { return }
        lastPeriodStep = 0
        animated(Tokens.Motion.swap) {
            workspace = .story
            sheet = nil
            selectedTab = .story
            storySelectedDay = nil
            expandedStoryDay = nil
            if scope == .day {
                showDay(date)
            } else {
                store.reviewAnchor = Calendar.current.startOfDay(for: date)
            }
            storyScope = scope
            refreshStoryScope()
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
    /// scope changed instead. The story's transition reads it.
    @Published private(set) var lastPeriodStep = 0

    func stepStoryPeriod(by delta: Int) {
        guard let store else { return }
        lastPeriodStep = delta
        storySelectedDay = nil
        expandedStoryDay = nil
        animated(Tokens.Motion.swap) {
            switch storyScope {
            case .day: store.stepDay(by: delta)
            case .week, .month: store.moveReviewPeriod(by: delta)
            }
        }
    }

    private func refreshStoryScope() {
        guard let store else { return }
        if let period = storyScope.period {
            store.setReviewVisible(true)
            store.refreshReview(period: period)
        } else {
            store.setReviewVisible(workspace == .history)
            store.refreshDashboard()
        }
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
            selectedTab = .story
        }
    }

    func selectInsightRange(_ range: InsightRange) {
        animated(Tokens.Motion.swap) { insightRange = range }
    }

    var insightAnchor: Date {
        get { insightAnchors[insightRange] ?? Calendar.current.startOfDay(for: store?.now() ?? Date()) }
        set { insightAnchors[insightRange] = newValue }
    }

    var insightPageCount: Int {
        insightPageCounts[insightRange] ?? defaultInsightPageCount(for: insightRange)
    }

    func stepInsightPeriod(by delta: Int, calendar: Calendar = .current) {
        guard delta != 0 else { return }
        let component: Calendar.Component
        switch insightRange {
        case .day: component = .day
        case .week: component = .weekOfYear
        case .month: component = .month
        }
        guard let candidate = calendar.date(byAdding: component, value: delta,
                                            to: insightAnchor) else { return }
        var moved = min(calendar.startOfDay(for: store?.now() ?? Date()), candidate)
        // Never page to a window that ends before the record begins.
        if delta < 0, let earliest = store?.earliestSelectableDay {
            let floor = calendar.startOfDay(for: earliest)
            if moved < floor { moved = max(floor, min(moved, insightAnchor)) }
        }
        insightAnchors[insightRange] = moved
    }

    /// How many periods the Insights column can show at its current width.
    /// The view measures and reports it; paging moves by it.
    @Published private var insightVisibleCounts: [InsightRange: Int] = [:]

    var insightVisibleCount: Int {
        insightVisibleCounts[insightRange] ?? defaultInsightPageCount(for: insightRange)
    }

    func setInsightVisibleCount(_ count: Int, for range: InsightRange) {
        let clamped = max(1, count)
        guard insightVisibleCounts[range] != clamped else { return }
        insightVisibleCounts[range] = clamped
    }

    /// The periods the column actually shows: as many as fit, but never one
    /// that ends before the record begins. History starts the day the app
    /// first saw anything; the blank months before that are not history, they
    /// are absence, and drawing them as empty calendars claims a record that
    /// was never kept. With nothing recorded at all there is one period — the
    /// current one — and it says so itself.
    var insightShownCount: Int {
        let fitting = insightVisibleCount
        guard let earliest = store?.earliestSelectableDay else { return 1 }
        let calendar = Calendar.current
        let component: Calendar.Component
        switch insightRange {
        case .day: component = .day
        case .week: component = .weekOfYear
        case .month: component = .month
        }
        guard let floor = calendar.dateInterval(of: component, for: earliest)?.start,
              let anchorStart = calendar.dateInterval(of: component, for: insightAnchor)?.start,
              let apart = calendar.dateComponents([component], from: floor, to: anchorStart)
                .value(for: component)
        else { return fitting }
        return max(1, min(fitting, apart + 1))
    }

    /// One page of periods at a time: as many as are shown, not one at a time.
    func pageInsights(by delta: Int) {
        stepInsightPeriod(by: delta * insightShownCount)
    }

    var insightCanPageForward: Bool {
        !Calendar.current.isDate(insightAnchor, inSameDayAs: store?.now() ?? Date())
    }

    /// History begins where the record begins: no paging into the empty time
    /// before the first day the app ever saw.
    var insightCanPageBack: Bool {
        guard let earliest = store?.earliestSelectableDay,
              let window = insightWindow else { return true }
        return window.start > Calendar.current.startOfDay(for: earliest)
    }

    /// The span of time the column currently shows.
    var insightWindow: DateInterval? {
        let calendar = Calendar.current
        let count = insightShownCount
        let component: Calendar.Component
        switch insightRange {
        case .day: component = .day
        case .week: component = .weekOfYear
        case .month: component = .month
        }
        guard let end = calendar.dateInterval(of: component == .day ? .day : component, for: insightAnchor)?.end,
              let start = calendar.date(byAdding: component, value: -(count - 1),
                                        to: calendar.dateInterval(of: component == .day ? .day : component,
                                                                  for: insightAnchor)?.start ?? insightAnchor)
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// The calendar picked a day: the window ends there.
    func jumpInsights(to date: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: store?.now() ?? Date())
        animated(Tokens.Motion.swap) {
            insightAnchors[insightRange] = min(today, calendar.startOfDay(for: date))
            reviewSelectedDate = nil
            historySelectedPeriod = nil
        }
    }

    /// The window the column shows: "4 – 17 Sep", "Jul – Sep 2026".
    var insightWindowLabel: String {
        let calendar = Calendar.current
        let now = store?.now() ?? Date()
        let count = insightShownCount
        switch insightRange {
        case .day:
            guard count > 1, let start = calendar.date(byAdding: .day, value: -(count - 1), to: insightAnchor)
            else { return Tokens.dayLabel(insightAnchor) }
            return Tokens.dateRange(start, insightAnchor, now: now, calendar: calendar)
        case .week:
            guard let bounds = calendar.dateInterval(of: .weekOfYear, for: insightAnchor),
                  let start = calendar.date(byAdding: .weekOfYear, value: -(count - 1), to: bounds.start)
            else { return Tokens.longDate(insightAnchor) }
            let end = calendar.date(byAdding: .day, value: -1, to: bounds.end) ?? bounds.start
            return Tokens.dateRange(start, end, now: now, calendar: calendar)
        case .month:
            guard count > 1, let start = calendar.date(byAdding: .month, value: -(count - 1), to: insightAnchor)
            else { return Tokens.australianDate("MMMM yyyy").string(from: insightAnchor) }
            let first = Tokens.australianDate("MMM").string(from: start)
            return "\(first) – \(Tokens.australianDate("MMM yyyy").string(from: insightAnchor))"
        }
    }

    func showEarlierInsights() {
        let increment = insightRange == .day ? 14 : insightRange == .week ? 6 : 3
        insightPageCounts[insightRange] = min(
            insightMaximumPageCount, insightPageCount + increment)
    }

    /// Month reaches a full year — three at a time, up to twelve. This is what
    /// makes Month the year view rather than only the quarter one.
    private var insightMaximumPageCount: Int {
        insightRange == .day ? 42 : insightRange == .week ? 14 : 12
    }

    private func defaultInsightPageCount(for range: InsightRange) -> Int {
        switch range {
        case .day: return 14
        case .week: return 6
        case .month: return 3
        }
    }

    var insightAnchorLabel: String {
        let calendar = Calendar.current
        switch insightRange {
        case .day:
            // The same words the Story's period control uses for a day.
            return Tokens.dayLabel(insightAnchor)
        case .month:
            return Tokens.australianDate("MMMM yyyy").string(from: insightAnchor)
        case .week:
            guard let bounds = calendar.dateInterval(of: .weekOfYear, for: insightAnchor) else {
                return Tokens.longDate(insightAnchor)
            }
            let end = calendar.date(byAdding: .day, value: -1, to: bounds.end) ?? bounds.start
            return Tokens.dateRange(bounds.start, end, now: store?.now() ?? Date(), calendar: calendar)
        }
    }

    private func tab(for workspace: MainReadingWorkspace) -> AppTab {
        switch workspace {
        case .story: return .story
        case .history: return .review
        case .insights: return .insights
        }
    }
}
