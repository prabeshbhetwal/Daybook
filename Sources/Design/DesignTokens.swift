import SwiftUI

/// Spacing, surfaces, palette, type and formatting. Every colour is a light/dark
/// pair; the system accent is the only accent.
enum Tokens {

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let card: CGFloat = 12
        static let control: CGFloat = 8
        static let swatch: CGFloat = 5
        static let bar: CGFloat = 3
    }

    /// Three tonal levels plus the two hairlines. Cards sit on the ground; wells
    /// sit inside cards. Values are starting points tuned on screen; the names
    /// are the contract.
    enum Surface {
        static let ground = Color(lightHex: 0xF4F4F6, darkHex: 0x1C1C1E)
        static let card = Color(lightHex: 0xFFFFFF, darkHex: 0x2A2A2D)
        static let well = Color(lightHex: 0xECECEF, darkHex: 0x141416)
        /// A secondary control's fill. Lifted above the card in dark — a control
        /// darker than its card reads as a hole, not a button — and a shade
        /// below it in light.
        static let control = Color(lightHex: 0xE6E6EA, darkHex: 0x3A3A3E)
        static let hairline = Color(light: NSColor.black.withAlphaComponent(0.08),
                                    dark: NSColor.white.withAlphaComponent(0.09))
        static let hover = Color(light: NSColor.black.withAlphaComponent(0.04),
                                 dark: NSColor.white.withAlphaComponent(0.06))
    }

    /// The data palette. Seven muted, luminance-matched hues assigned by the
    /// day's rank — busiest app first — so one app is one colour on every
    /// surface that day. Index 6 is "Other". Work types have a fixed set so a
    /// legend never has to be relearned between periods.
    enum Palette {
        private static let pairs: [(light: UInt32, dark: UInt32)] = [
            (0x4A7BE0, 0x7DA2F2),   // blue
            (0x2E9E86, 0x5CC4AB),   // teal
            (0xD08A2A, 0xE6AE5B),   // amber
            (0x8A6CD4, 0xAE97E8),   // violet
            (0xCF5F7C, 0xE58AA3),   // rose
            (0x4695B5, 0x78BBD5),   // cyan
            (0x8E8E93, 0x98989D)    // other
        ]
        private static let ramp: [Color] = pairs.map { Color(lightHex: $0.light, darkHex: $0.dark) }

        static func app(rank: Int) -> Color {
            ramp[min(max(rank, 0), ramp.count - 1)]
        }

        static let untracked = ramp[ramp.count - 1]
        static let slate = Color(lightHex: 0x6C7A93, darkHex: 0x93A1BB)
        static let warmGrey = Color(lightHex: 0xA39E98, darkHex: 0x7E7973)

        static func workType(_ type: WorkType) -> Color {
            switch type {
            case .deepWork: return .accentColor
            case .meetings: return ramp[2]
            case .admin: return slate
            case .learning: return ramp[3]
            case .breakTime: return warmGrey
            }
        }

        /// The pair's sRGB components for one appearance. For the tests, which
        /// cannot compare dynamic colours any other way.
        static func resolved(rank: Int, dark: Bool) -> (r: Double, g: Double, b: Double) {
            let pair = pairs[min(max(rank, 0), pairs.count - 1)]
            let hex = dark ? pair.dark : pair.light
            return (Double((hex >> 16) & 0xFF) / 255,
                    Double((hex >> 8) & 0xFF) / 255,
                    Double(hex & 0xFF) / 255)
        }
    }

    /// SF everywhere. Hero and stat numerals use SF Rounded with tabular digits,
    /// which reads as a product rather than a terminal; SF Mono is gone.
    enum Typography {
        static let heroTimer = Font.system(size: 34, weight: .semibold, design: .rounded)
            .monospacedDigit()
        static let stat = Font.system(size: 24, weight: .semibold, design: .rounded)
            .monospacedDigit()
        static let ringLabel = Font.system(size: 11, weight: .semibold, design: .rounded)
            .monospacedDigit()
        static let title = Font.system(size: 20, weight: .semibold)
        static let sectionLabel = Font.system(size: 11, weight: .semibold)
        static let row = Font.callout
        static let detail = Font.caption
    }

    static let popoverWidth: CGFloat = 320
    /// The widest a form row should ever be: an intent field, a settings row, a
    /// primary button. Text and controls have a comfortable measure that does
    /// not grow with the window.
    static let formMeasure: CGFloat = 340
    static let cardCorner: CGFloat = Radius.card

    /// SF Pro with monospaced digits. The menu bar uses the system font; SF Mono
    /// there reads as foreign and runs wide.
    static let menuBarFont = Font.system(size: NSFont.systemFontSize).monospacedDigit()
    /// Kept as names so older call sites compile; both now resolve to the
    /// rounded scale above.
    static let heroTimerFont = Typography.heroTimer
    static let statNumberFont = Typography.stat

    /// `2h 15m`, `15m`, `0m`.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        // "4h", not "4h 0m" — a whole number of hours reads as a clumsy
        // measurement with a zero stapled to it, and round figures are exactly
        // what goals and targets are set in.
        guard hours > 0 else { return "\(minutes)m" }
        return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
    }

    /// `01:23:45` for the live hero timer.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    /// `2 hours`, `2 hours 13 minutes`, `13 minutes`, `45 seconds` — the spoken
    /// form used in per-app history, where `2h 13m` reads as too terse.
    static func spent(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            let hourPart = hours == 1 ? "1 hour" : "\(hours) hours"
            guard minutes > 0 else { return hourPart }
            return "\(hourPart) \(minutes) min"
        }
        if minutes > 0 { return minutes == 1 ? "1 minute" : "\(minutes) minutes" }
        return "\(total) seconds"
    }

    /// `4 hours ago`, `just now`.
    static func relative(_ date: Date, from reference: Date = Date()) -> String {
        let delta = reference.timeIntervalSince(date)
        if delta < 60 { return "just now" }
        let minutes = Int(delta) / 60
        if minutes < 60 { return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago" }
        let hours = minutes / 60
        if hours < 24 { return hours == 1 ? "1 hour ago" : "\(hours) hours ago" }
        let days = hours / 24
        return days == 1 ? "yesterday" : "\(days) days ago"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    /// `2:13 PM – 4:13 PM`.
    static func timeRange(_ start: Date, _ end: Date) -> String {
        "\(timeFormatter.string(from: start)) – \(timeFormatter.string(from: end))"
    }

    /// Sub-minute stretches are common in app usage, where `duration` floors to
    /// "0m" and a real 45-second stretch renders as nothing.
    static func preciseDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        if total < 60 { return "\(total)s" }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        return "\(minutes)m"
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        return formatter
    }()

    /// `Today`, `Yesterday`, or `Wed 13 Aug`.
    /// Single letter for a dense axis. Keyed on the date, never on a formatted
    /// letter — "EEEEE" yields duplicates (T for Tuesday and Thursday), which
    /// once collapsed a seven-bar chart to five.
    static func dayInitial(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: date)
    }

    static func dayLabel(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return dayFormatter.string(from: date)
    }

    /// `since 2:13 PM`, for a launch time.
    static func timeOfDay(_ date: Date) -> String {
        "since \(timeFormatter.string(from: date))"
    }

    private static let longDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMMM"
        return formatter
    }()

    /// `Saturday 22 August`, for the dashboard's title band.
    static func longDate(_ date: Date) -> String {
        longDateFormatter.string(from: date)
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension Color {
    /// A light/dark pair without an asset catalog. `NSColor(name:dynamicProvider:)`
    /// resolves per appearance, so the pair flips with the system and with the
    /// harness's `.environment(\.colorScheme, ...)`.
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    init(lightHex: UInt32, darkHex: UInt32) {
        self.init(light: NSColor(hex: lightHex), dark: NSColor(hex: darkHex))
    }
}
