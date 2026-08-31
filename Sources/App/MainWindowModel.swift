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

struct InsightReadingPosition: Equatable {
    let anchor: Date
    let pageCount: Int
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case focus
    case away
    case automatic
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

/// Attached panels plus compatibility routes for the two reading workspaces.
/// History and Insights are intercepted by `openSheet` and never presented as
/// modal sheets; Focus, Awards and Settings remain attached.
enum StorySheetKind: String, CaseIterable, Identifiable {
    case focus, history, insights, awards, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: return "Focus session"
        case .history: return "History"
        case .insights: return "Insights"
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
    @Published var reviewSection: ReviewSection = .week
    @Published var insightRange: InsightRange = .week
    @Published private var insightAnchors: [InsightRange: Date]
    @Published private var insightPageCounts: [InsightRange: Int]
    @Published var settingsSection: SettingsSection = .general
    @Published var settingsQuery: String = ""
    private weak var store: SessionStore?
    private var periodObservation: AnyCancellable?

    init(selectedTab: AppTab = .story,
         storyScope: StoryScope = .day,
         requestedDate: Date? = nil,
         store: SessionStore? = nil) {
        self.selectedTab = selectedTab
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
        case .review:
            self.workspace = .history
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
        selectedTab = tab
        switch tab {
        case .review:
            workspace = .history
            sheet = nil
            reviewSection = .history
            store?.refreshReview()
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
        if tab == .today {
            openToday(date: store?.now() ?? Date())
        }
    }

    func openToday(date: Date) {
        requestedDate = date
        selectedTab = .today
        workspace = .story
        sheet = nil
        showDay(date)
        storyScope = .day
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

    /// The only route out of Review. It is reached from a named action, never
    /// as a side effect of selecting a bar or a row.
    func openSelectedReviewDayInToday() {
        guard let reviewSelectedDate else { return }
        openToday(date: reviewSelectedDate)
    }

    func openSheet(_ kind: StorySheetKind) {
        switch kind {
        case .history: open(tab: .review)
        case .insights: open(tab: .insights)
        default:
            selectedTab = kind.tab
            sheet = kind
        }
    }

    func closeSheet() {
        sheet = nil
        selectedTab = tab(for: workspace)
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

    func clearStoryDay() {
        storySelectedDay = nil
        expandedStoryDay = nil
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
        store.setDashboardVisible(true)
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

    /// Story may deliberately inspect an empty historical date. Do not silently
    /// replace it with the earliest recorded day; only future dates are clamped.
    private func showDay(_ date: Date) {
        guard let store else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: store.now())
        let target = min(today, calendar.startOfDay(for: date))
        let offset = calendar.dateComponents([.day], from: target, to: today).day ?? 0
        store.selectDay(offset: max(0, offset))
    }

    func stepStoryPeriod(by delta: Int) {
        guard let store else { return }
        storySelectedDay = nil
        expandedStoryDay = nil
        switch storyScope {
        case .day: store.stepDay(by: delta)
        case .week, .month: store.moveReviewPeriod(by: delta)
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

    func returnToStory() {
        sheet = nil
        workspace = .story
        selectedTab = .story
    }

    func selectInsightRange(_ range: InsightRange) {
        insightRange = range
    }

    var insightPosition: InsightReadingPosition {
        InsightReadingPosition(anchor: insightAnchor, pageCount: insightPageCount)
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
        insightAnchors[insightRange] = min(
            calendar.startOfDay(for: store?.now() ?? Date()), candidate)
    }

    func showEarlierInsights() {
        let increment = insightRange == .day ? 14 : insightRange == .week ? 6 : 3
        insightPageCounts[insightRange] = min(
            insightMaximumPageCount, insightPageCount + increment)
    }

    var insightCanShowEarlier: Bool {
        insightPageCount < insightMaximumPageCount
    }

    private var insightMaximumPageCount: Int {
        insightRange == .day ? 42 : insightRange == .week ? 14 : 4
    }

    private func defaultInsightPageCount(for range: InsightRange) -> Int {
        range == .day ? 14 : range == .week ? 6 : 3
    }

    var insightAnchorLabel: String {
        let calendar = Calendar.current
        switch insightRange {
        case .day:
            return Tokens.longDate(insightAnchor)
        case .month:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_AU")
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: insightAnchor)
        case .week:
            guard let bounds = calendar.dateInterval(of: .weekOfYear, for: insightAnchor) else {
                return Tokens.longDate(insightAnchor)
            }
            let end = calendar.date(byAdding: .day, value: -1, to: bounds.end) ?? bounds.start
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_AU")
            formatter.dateFormat = "d MMM"
            return "\(formatter.string(from: bounds.start))–\(formatter.string(from: end))"
        }
    }

    func moveTab(by delta: Int) {
        open(tab: selectedTab.moved(by: delta))
    }

    private func tab(for workspace: MainReadingWorkspace) -> AppTab {
        switch workspace {
        case .story: return .story
        case .history: return .review
        case .insights: return .insights
        }
    }
}
