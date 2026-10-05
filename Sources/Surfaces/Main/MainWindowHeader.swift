import SwiftUI
import AppKit

/// Pure context for the one-row window chrome. It keeps the visible title and
/// live status in the same visual band as the application tabs.
enum MainWindowChrome {
    static let trafficLightClearance: CGFloat = 76

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

