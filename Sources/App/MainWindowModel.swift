import SwiftUI
import AppKit

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
    @Published var storyScope: StoryScope = .day
    @Published private(set) var storySelectedDay: Date?
    @Published var reviewSection: ReviewSection = .week
    @Published var insightRange: InsightRange = .week
    @Published var settingsSection: SettingsSection = .general
    @Published var settingsQuery: String = ""

    init(selectedTab: AppTab = .focus, requestedDate: Date? = nil) {
        self.selectedTab = selectedTab
        self.requestedDate = requestedDate
    }

    func select(_ tab: AppTab) {
        selectedTab = tab
    }

    func open(tab: AppTab) {
        selectedTab = tab
    }

    func openToday(date: Date) {
        requestedDate = date
        selectedTab = .today
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

    func selectStoryDay(_ date: Date, calendar: Calendar = .current) {
        storySelectedDay = calendar.startOfDay(for: date)
    }

    func clearStoryDay() {
        storySelectedDay = nil
    }

    /// The named drill-in: the month or week hands its selected day to the day
    /// story, which is the whole point of choosing a cell.
    func openStoryDay(_ date: Date, calendar: Calendar = .current) {
        storySelectedDay = calendar.startOfDay(for: date)
        storyScope = .day
        requestedDate = calendar.startOfDay(for: date)
    }

    func openSettings() {
        selectedTab = .settings
    }

    func moveTab(by delta: Int) {
        selectedTab = selectedTab.moved(by: delta)
    }
}
