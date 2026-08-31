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
    case week
    case month
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

/// The surfaces that arrive over the story rather than replacing it.
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
    @Published private(set) var requestedDate: Date?
    /// The day Review is inspecting, or nil when nothing is selected. It is
    /// deliberately separate from `requestedDate`: selecting evidence in Review
    /// explains a day in place, while `requestedDate` moves the user to Today.
    @Published private(set) var reviewSelectedDate: Date?
    /// Which span the Story surface is telling, and the day drilled into from
    /// a week bar or a month cell. The selection is inspection: it never leaves
    /// the surface, and `openStoryDay` is the one action that changes scope.
    /// The surfaces the story links to rather than contains. Nil is the story
    /// itself, which is what the window shows.
    @Published private(set) var sheet: StorySheetKind?
    @Published var storyScope: StoryScope = .day {
        didSet {
            guard storyScope != oldValue else { return }
            storySelectedDay = nil
            refreshStoryScope()
        }
    }
    @Published private(set) var storySelectedDay: Date?
    @Published var reviewSection: ReviewSection = .week
    @Published var insightRange: InsightRange = .week
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
        // Construction and selection must agree: a model built on a sheet-backed
        // tab is already presenting that sheet, or restoring one would show the
        // story with no sign of the surface that was asked for.
        self.sheet = StorySheetKind(tab: selectedTab)
        if let store { connect(to: store) }
    }

    func select(_ tab: AppTab) {
        open(tab: tab)
    }

    func open(tab: AppTab) {
        selectedTab = tab
        sheet = StorySheetKind(tab: tab)
        if tab == .today {
            openToday(date: store?.now() ?? Date())
        } else if tab == .review {
            reviewSection = .history
            store?.refreshReview()
        }
    }

    func openToday(date: Date) {
        requestedDate = date
        selectedTab = .today
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
        open(tab: kind.tab)
    }

    func closeSheet() {
        sheet = nil
        selectedTab = .story
    }

    func selectStoryDay(_ date: Date, calendar: Calendar = .current) {
        storySelectedDay = calendar.startOfDay(for: date)
    }

    func clearStoryDay() {
        storySelectedDay = nil
    }

    /// The named drill-in: the month or week hands its selected day to the day
    /// story, which is the whole point of choosing a cell.
    func openStoryDay(_ date: Date, calendar: Calendar = .current) {
        openToday(date: calendar.startOfDay(for: date))
        storySelectedDay = nil
        selectedTab = .story
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
            guard let self, let selected = self.storySelectedDay else { return }
            if !days.contains(where: { Calendar.current.isDate($0.date, inSameDayAs: selected) }) {
                self.storySelectedDay = nil
            }
        }
        refreshStoryScope()
    }

    func selectScope(_ scope: StoryScope) {
        if scope != storyScope, let store {
            let anchor = storyScope == .day ? store.selectedDay
                : storySelectedDay ?? store.reviewAnchor ?? store.now()
            if scope == .day {
                showDay(anchor)
            } else {
                store.reviewAnchor = Calendar.current.startOfDay(for: anchor)
            }
        }
        closeSheet()
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
            store.setReviewVisible(sheet == .history)
            store.refreshDashboard()
        }
    }

    func openSettings() {
        openSheet(.settings)
    }

    func moveTab(by delta: Int) {
        open(tab: selectedTab.moved(by: delta))
    }
}
