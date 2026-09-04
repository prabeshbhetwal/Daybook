import SwiftUI

/// Spacing, surfaces, palette, type and formatting. Colours are light/dark pairs
/// with a single source of truth for the warm-precision shell.
enum Tokens {

    enum Colour {
        enum Name {
            case ground
            case surface
            case elevated
            case line
            case hover
            case focus
            case onFocus
            case progress
            case attention
            case danger

            fileprivate var swatch: (light: UInt32, dark: UInt32) {
                switch self {
                // Apple's neutral system greys rather than a warm cast: the
                // shell should read as a macOS window, not as a themed one.
                case .ground: return (0xF2F2F7, 0x1C1C1E)
                case .surface: return (0xFFFFFF, 0x2C2C2E)
                case .elevated: return (0xEBEBF0, 0x3A3A3C)
                case .line: return (0x000000, 0xFFFFFF)
                case .hover: return (0x000000, 0xFFFFFF)
                // System blue, in its own light and dark variants.
                case .focus: return (0x007AFF, 0x0A84FF)
                // Near-black, not white: white on system blue is 4.02:1, which
                // fails the contrast contract this app holds itself to.
                case .onFocus: return (0x0F1115, 0x0F1115)
                case .progress: return (0x34C759, 0x30D158)
                case .attention: return (0xFF9500, 0xFF9F0A)
                case .danger: return (0xFF3B30, 0xFF453A)
                }
            }

            fileprivate var alpha: (light: CGFloat, dark: CGFloat) {
                switch self {
                case .line: return (0.08, 0.10)
                case .hover: return (0.04, 0.07)
                default: return (1, 1)
                }
            }
        }

        struct Resolved: Equatable {
            let color: Color
            let hex: UInt32
        }

        static func resolved(_ token: Name, dark: Bool) -> Resolved {
            let pair = token.swatch
            let alpha = token.alpha
            let light = token == .danger
                ? NSColor.systemRed
                : NSColor(hex: pair.light, alpha: alpha.light)
            let darkColour = token == .danger
                ? NSColor.systemRed
                : NSColor(hex: pair.dark, alpha: alpha.dark)
            return Resolved(color: Color(light: light, dark: darkColour),
                            hex: dark ? pair.dark : pair.light)
        }

        static let ground = resolved(.ground, dark: false).color
        static let surface = resolved(.surface, dark: false).color
        static let elevated = resolved(.elevated, dark: false).color
        static let line = resolved(.line, dark: false).color
        static let hover = resolved(.hover, dark: false).color
        static let focus = resolved(.focus, dark: false).color
        static let onFocus = resolved(.onFocus, dark: false).color
        static let progress = resolved(.progress, dark: false).color
        static let attention = resolved(.attention, dark: false).color
        static let danger = resolved(.danger, dark: false).color
    }

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }

    enum Radius {
        static let panel: CGFloat = 16
        static let nested: CGFloat = 12
        static let capsule: CGFloat = 999

        static let swatch: CGFloat = 5
        static let bar: CGFloat = 3
    }

    enum Typography {
        /// Every text size the product may use. Ad-hoc sizes had grown to
        /// nineteen steps, with 6/7/8/9 doing one job between them and
        /// 12/13/14/15/16 doing no perceptual work apart — a list, not a
        /// scale. Each step here earns its place, and `Size` is the only
        /// source: a font built from a number not in this set is a defect.
        enum Size {
            static let micro: CGFloat = 9
            static let smallLabel: CGFloat = 10
            static let ring: CGFloat = 11
            static let metadata: CGFloat = 12
            static let control: CGFloat = 13
            static let row: CGFloat = 15
            static let section: CGFloat = 17
            static let headline: CGFloat = 23
            static let page: CGFloat = 26
            static let metric: CGFloat = 30
            static let timer: CGFloat = 46

            /// Ascending, for the checks that hold the scale to its shape.
            static let all: [CGFloat] = [micro, smallLabel, ring, metadata, control,
                                         row, section, headline, page, metric, timer]
        }

        static let liveTimer = Font.system(size: Size.timer, weight: .semibold, design: .rounded)
            .monospacedDigit()
        static let pageTitle = Font.system(size: Size.page, weight: .semibold, design: .default)
        static let sectionTitle = Font.system(size: Size.section, weight: .semibold, design: .default)
        /// The sentence a story opens with — prose, so it wraps and breathes
        /// rather than shouting like a page title.
        static let storyHeadline = Font.system(size: Size.headline, weight: .semibold, design: .default)
        static let metricValue = Font.system(size: Size.metric, weight: .semibold, design: .rounded)
            .monospacedDigit()
        static let tabLabel = Font.system(size: Size.control, weight: .medium, design: .default)
        static let rowTitle = Font.system(size: Size.row, weight: .medium, design: .default)
        static let metadata = Font.system(size: Size.metadata, weight: .regular, design: .default)

        static let ringLabel = Font.system(size: Size.ring, weight: .semibold, design: .rounded)
        /// Decorative micro-text: legend ticks, calendar dots, axis marks.
        /// One step replaces the four ad-hoc sizes 6, 7, 8 and 9.
        static let micro = Font.system(size: Size.micro, weight: .semibold, design: .default)
        /// The smallest text a reader is expected to read: chips and badges.
        static let microLabel = Font.system(size: Size.smallLabel, weight: .semibold, design: .default)
        /// The same step for figures, so small numbers align with the rounded
        /// faces the metric values use.
        static let microValue = Font.system(size: Size.smallLabel, weight: .medium, design: .rounded)
            .monospacedDigit()
        static let menuBar = Font.system(size: NSFont.systemFontSize).monospacedDigit()
    }

    static let popoverWidth: CGFloat = 340
    /// The widest a form row should ever be: an intent field, a settings row, a
    /// primary button. Text and controls have a comfortable measure that does
    /// not grow with the window.
    static let formMeasure: CGFloat = 340
    /// `2h 15m`, `15m`, `0m`.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
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
        DurationText.precise(seconds)
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

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    /// `Wednesday`, for a sentence that names a day rather than dating it.
    static func weekdayName(_ date: Date) -> String {
        weekdayFormatter.string(from: date)
    }

    /// `2:13 PM` on its own, for a column that already means "when".
    static func timeOfDayOnly(_ date: Date) -> String {
        timeFormatter.string(from: date)
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

    // MARK: Palette

    enum Palette {
        /// The Apple system hues, in light and dark variants. Rank 0 is the
        /// busiest app, and the last entry is always the neutral "other" grey.
        private static let pairs: [(light: UInt32, dark: UInt32)] = [
            (0x007AFF, 0x0A84FF),
            (0x30B0C7, 0x40C8E0),
            (0xFF9500, 0xFF9F0A),
            (0x5E5CE6, 0x7D7AFF),
            (0xFF375F, 0xFF6482),
            (0xAF52DE, 0xBF5AF2),
            (0x8E8E93, 0x98989D)
        ]
        private static let ramp: [Color] = pairs.map { Color(lightHex: $0.light, darkHex: $0.dark) }

        static func app(rank: Int) -> Color {
            ramp[min(max(rank, 0), ramp.count - 1)]
        }

        static let untracked = ramp[ramp.count - 1]
        static let slate = Color(lightHex: 0x30B0C7, darkHex: 0x40C8E0)
        static let warmGrey = Color(lightHex: 0x8E8E93, darkHex: 0x98989D)

        /// Fixed identities, matching the approved design's composition legend:
        /// deep work indigo, meetings orange, admin teal, learning pink, rest
        /// neutral grey. Rest must never look like work.
        static func workType(_ type: WorkType) -> Color {
            switch type {
            case .deepWork: return ramp[3]
            case .meetings: return ramp[2]
            case .admin: return ramp[1]
            case .learning: return ramp[4]
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

    /// The design's motion notes as one contract. Every value is short,
    /// interruptible and explains a state change; nothing here is decorative,
    /// and `reduceMotion` collapses all of it to an instant cut.
    enum Motion {
        /// The selection pill travels rather than redrawing, so the eye follows
        /// one object across the rail.
        static let selection = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.20)
        /// Content settling into place after a view change.
        static let rise = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.22)
        /// Children enter this far apart, in order.
        static let stagger: Double = 0.06
        /// A hover is a tint, never a colour jump.
        static let hover = Animation.easeOut(duration: 0.16)
        /// Pressable things settle back from this scale.
        static let pressedScale: CGFloat = 0.97

        static func animation(_ base: Animation, reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : base
        }
    }

    /// Layout metrics for compact and comfortable density.
    enum Density {
        static let compactRowHeight: CGFloat = 44
        static let comfortableRowHeight: CGFloat = 52
    }
}

/// App-specific density in both display and settings.
extension InterfaceDensity {
    struct Layout {
        let rowHeight: CGFloat
        let panelSpacing: CGFloat
        let insetPadding: CGFloat
        let sectionSpacing: CGFloat

        static let comfortable = Layout(rowHeight: Tokens.Density.comfortableRowHeight,
                                        panelSpacing: Tokens.Space.xl,
                                        insetPadding: Tokens.Space.l,
                                        sectionSpacing: Tokens.Space.l)
        static let compact = Layout(rowHeight: Tokens.Density.compactRowHeight,
                                   panelSpacing: Tokens.Space.l,
                                   insetPadding: Tokens.Space.m,
                                   sectionSpacing: Tokens.Space.m)
    }

    var layout: Layout {
        switch self {
        case .comfortable: return .comfortable
        case .compact: return .compact
        }
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
