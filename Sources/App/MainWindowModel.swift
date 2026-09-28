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

/// How far back History reads. Each range is a number of periods at the one
/// grouping that suits its length, so the reader picks how much time to see
/// and never the unit it is counted in.
enum HistoryRange: String, CaseIterable {
    case days7, days30, months3, months12

    var title: String {
        switch self {
        case .days7: return "7 days"
        case .days30: return "30 days"
        case .months3: return "3 months"
        case .months12: return "12 months"
        }
    }

    var grouping: InsightRange {
        switch self {
        case .days7, .days30: return .day
        case .months3: return .week
        case .months12: return .month
        }
    }

    var count: Int {
        switch self {
        case .days7: return 7
        case .days30: return 30
        case .months3: return 13
        case .months12: return 12
        }
    }
}

/// A span picked on History's calendar, read as a count of periods at the
/// grouping its length suits.
struct HistorySpan: Equatable {
    let grouping: InsightRange
    let count: Int

    /// Up to six weeks by day, up to fourteen weeks by week, then by month,
    /// never more than twelve. The limits are what the charts can draw.
    static func covering(_ start: Date, _ end: Date, calendar: Calendar = .current) -> HistorySpan {
        let first = calendar.startOfDay(for: min(start, end))
        let last = calendar.startOfDay(for: max(start, end))
        let days = (calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 1
        if days <= 42 { return HistorySpan(grouping: .day, count: days) }
        if days <= 98,
           let a = calendar.dateInterval(of: .weekOfYear, for: first)?.start,
           let b = calendar.dateInterval(of: .weekOfYear, for: last)?.start {
            let weeks = (calendar.dateComponents([.weekOfYear], from: a, to: b).weekOfYear ?? 0) + 1
            return HistorySpan(grouping: .week, count: min(14, weeks))
        }
        let a = calendar.dateInterval(of: .month, for: first)?.start ?? first
        let b = calendar.dateInterval(of: .month, for: last)?.start ?? last
        let months = (calendar.dateComponents([.month], from: a, to: b).month ?? 0) + 1
        return HistorySpan(grouping: .month, count: min(12, months))
    }
}

/// What fills the window below the chrome: the story, or History reading
/// the past across spans.
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
    /// The day Review is inspecting, or nil when nothing is selected. It is
    /// deliberately separate from `requestedDate`: selecting evidence in Review
    /// explains a day in place, while `requestedDate` moves the user to Today.
    @Published private(set) var reviewSelectedDate: Date?
    /// The sheet over the story, if any. The story itself is always a day.
    @Published private(set) var sheet: StorySheetKind?
    /// Transient expansion belongs to navigation, not session state. A
    /// separately persisted pin may keep the strip visible across relaunch.
    @Published private(set) var sessionControlsExpanded = false
    @Published private(set) var focusRestorationRequest: MainWindowFocusTarget?
    @Published var reviewSection: ReviewSection = .week
    /// The far end of a span picked on History's map, or nil for one day.
    @Published var historySelectedPeriod: Date?
    /// Asks History's search field for the cursor (⌘F). The field is always
    /// shown; results replace the chart while a query or filter is active.
    @Published private(set) var historySearchFocusRequest = 0
    /// The range History reads, or nil while a span picked on its calendar
    /// is showing instead.
    @Published private(set) var historyRange: HistoryRange? = .days30
    @Published private var historySpan: HistorySpan?
    /// The last day History reads. Every range ends here, so changing range
    /// keeps the reader where they are.
    @Published private var insightEnd: Date
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
        self.insightEnd = Calendar.current.startOfDay(for: store?.now() ?? Date())
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
                reviewSection = .history
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

    func selectHistoryRange(_ range: HistoryRange) {
        animated(Tokens.Motion.swap) {
            historyRange = range
            historySpan = nil
        }
    }

    /// The calendar picked a span: History reads exactly it, grouped to suit.
    func setCustomHistoryRange(_ start: Date, _ end: Date, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: store?.now() ?? Date())
        animated(Tokens.Motion.swap) {
            historySpan = HistorySpan.covering(start, end, calendar: calendar)
            historyRange = nil
            insightEnd = min(today, calendar.startOfDay(for: max(start, end)))
            reviewSelectedDate = nil
        }
    }

    /// The grouping History reads at: the range's, or the picked span's.
    var insightRange: InsightRange { historySpan?.grouping ?? historyRange?.grouping ?? .day }

    /// How many periods the range asks for, before the record's start trims it.
    var insightRequestedCount: Int { historySpan?.count ?? historyRange?.count ?? 30 }

    var insightAnchor: Date {
        get { insightEnd }
        set { insightEnd = newValue }
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
        insightEnd = moved
    }

    /// The periods the column actually shows: as many as the range asks, but never one
    /// that ends before the record begins. History starts the day the app
    /// first saw anything; the blank months before that are not history, they
    /// are absence, and drawing them as empty calendars claims a record that
    /// was never kept. With nothing recorded at all there is one period — the
    /// current one — and it says so itself.
    var insightShownCount: Int {
        let fitting = insightRequestedCount
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
            insightEnd = min(today, calendar.startOfDay(for: date))
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
            else { return DateFormats.australian("MMMM yyyy").string(from: insightAnchor) }
            let first = DateFormats.australian("MMM").string(from: start)
            return "\(first) – \(DateFormats.australian("MMM yyyy").string(from: insightAnchor))"
        }
    }

    var insightAnchorLabel: String {
        let calendar = Calendar.current
        switch insightRange {
        case .day:
            // The same words the Story's period control uses for a day.
            return Tokens.dayLabel(insightAnchor)
        case .month:
            return DateFormats.australian("MMMM yyyy").string(from: insightAnchor)
        case .week:
            guard let bounds = calendar.dateInterval(of: .weekOfYear, for: insightAnchor) else {
                return Tokens.longDate(insightAnchor)
            }
            let end = calendar.date(byAdding: .day, value: -1, to: bounds.end) ?? bounds.start
            return Tokens.dateRange(bounds.start, end, now: store?.now() ?? Date(), calendar: calendar)
        }
    }
}
