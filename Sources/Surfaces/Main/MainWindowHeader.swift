import SwiftUI
import AppKit

/// Pure context for the one-row window chrome. It keeps the visible title and
/// live status in the same visual band as the application tabs.
enum MainWindowChrome {
    /// The system's window buttons do not follow the interface zoom.
    static let trafficLightClearance: CGFloat = 76 // zoom: fixed

    /// The room the chrome leaves at its leading edge: the window buttons are
    /// there, except in full screen, where the system hides them.
    static func clearance(fullScreen: Bool) -> CGFloat {
        fullScreen ? 0 : trafficLightClearance
    }

    /// What the window is called, which is what the Window menu, Mission
    /// Control and the Dock menu list it by. The title bar is hidden, so
    /// nothing else on screen shows it.
    struct WindowTitle: Equatable {
        let title: String
        let subtitle: String
    }

    /// The window follows the workspace: "Today" for the story, "History" for
    /// the journal. The date goes in the subtitle where the page shows one: the
    /// story's day, or the day open in History (none when no day is open). A
    /// story that is not on today's date keeps the workspace's own name.
    static func windowTitle(
        workspace: MainReadingWorkspace,
        storyDay: Date,
        historyDay: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> WindowTitle {
        switch workspace {
        case .story:
            let isToday = calendar.isDate(storyDay, inSameDayAs: now)
            return WindowTitle(title: isToday ? "Today" : AppTab.story.title,
                               subtitle: DateFormats.fullDay(storyDay, now: now, calendar: calendar))
        case .history:
            return WindowTitle(title: "History",
                               subtitle: historyDay.map { DateFormats.fullDay($0, now: now, calendar: calendar) } ?? "")
        }
    }

    struct Context: Equatable {
        let title: String
        let subtitle: String
        let status: String
    }

    static func context(
        tab: AppTab,
        state: SessionState,
        threadElapsed: TimeInterval,
        todayTotal: TimeInterval
    ) -> Context {
        let status: String
        switch state {
        case .running:
            status = "Focus active · \(Tokens.duration(threadElapsed))"
        case .paused:
            status = "Focus paused · \(Tokens.duration(threadElapsed))"
        case .awaitingUserDecision:
            status = "Focus needs an answer · \(Tokens.duration(threadElapsed))"
        case .idle:
            status = "Today · \(Tokens.duration(todayTotal)) focused"
        }
        return Context(title: tab.title, subtitle: "Daybook", status: status)
    }
}

