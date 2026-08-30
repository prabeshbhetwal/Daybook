import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case focus
    case today
    case review
    case insights
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: return "Focus"
        case .today: return "Today"
        case .review: return "Review"
        case .insights: return "Insights"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .focus: return "target"
        case .today: return "calendar"
        case .review: return "chart.bar"
        case .insights: return "sparkles"
        case .settings: return "gearshape"
        }
    }

    var commandNumber: Int {
        switch self {
        case .focus: return 1
        case .today: return 2
        case .review: return 3
        case .insights: return 4
        case .settings: return 5
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
}

@MainActor final class MainWindowModel: ObservableObject {
    @Published var selectedTab: AppTab
    @Published private(set) var requestedDate: Date?
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

    func openSettings() {
        selectedTab = .settings
    }

    func moveTab(by delta: Int) {
        selectedTab = selectedTab.moved(by: delta)
    }
}
