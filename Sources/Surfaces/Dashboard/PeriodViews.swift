import SwiftUI
import Charts

extension PeriodChartPoint {
    /// Full spoken evidence for one chart point. The formatter follows the
    /// supplied calendar's locale and time zone so date and value cannot drift
    /// apart around local midnight.
    func accessibilitySummary(calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE d MMMM"
        return "\(formatter.string(from: date)), \(Self.spoken(seconds)) tracked"
    }

    private static func spoken(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        var parts: [String] = []
        if hours > 0 { parts.append(hours == 1 ? "1 hour" : "\(hours) hours") }
        if minutes > 0 { parts.append(minutes == 1 ? "1 minute" : "\(minutes) minutes") }
        if parts.isEmpty {
            parts.append(seconds == 1 ? "1 second" : "\(seconds) seconds")
        }
        return parts.joined(separator: " ")
    }
}

/// One headline figure with its context line and an optional tint for it.
struct StatFigure: Identifiable, Equatable {
    let label: String
    let value: String
    var detail: String?
    var tint: Color?
    /// One value per day for the card's sparkline; empty draws none.
    var spark: [Double] = []
    var sparkTint: Color?
    /// An SF Symbol beside the label, and a short qualifier pinned top-right —
    /// a compact status-grid anatomy: label · badge / value / chart /
    /// footer, so every card is read the same way.
    var symbol: String?
    var badge: String?
    var badgeTint: Color?
    var id: String { label }
}

