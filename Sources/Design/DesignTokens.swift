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
                // One neutral family. In light appearance every background is
                // the Story canvas's warm neutral (`StoryStyle.canvas`,
                // `rail`, `well`); the cool system grey (#F2F2F7, #EBEBF0)
                // made a sheet, the popover and Awards look like a different
                // app beside the main window. Ground sits one step under the
                // rail and keeps the old grey's separation from a white card
                // (1.12:1); supporting ink is 9.8:1 on it, 9.4:1 on elevated.
                // The dark values are already neutral on both sides.
                case .ground: return (0xF3F2EF, 0x1C1C1E)
                case .surface: return (0xFFFFFF, 0x2C2C2E)
                case .elevated: return (0xECEBE8, 0x3A3A3C)
                case .line: return (0x000000, 0xFFFFFF)
                case .hover: return (0x000000, 0xFFFFFF)
                // The app's one accent, the same blue as links and text
                // actions: a shade under system blue so white text on it
                // reads (5.4:1), and a lighter blue in the dark.
                case .focus: return (0x0068D1, 0x75B5FF)
                // White on the light accent, near-black on the dark one.
                case .onFocus: return (0xFFFFFF, 0x0F1115)
                case .progress: return (0x34C759, 0x30D158)
                case .attention: return (0xFF9500, 0xFF9F0A)
                // A red deep enough to be read: danger is mostly error text
                // and the Remove label, and system red on white is 3.5:1.
                // These clear 4.5:1 on every surface the app draws them on.
                case .danger: return (0xC60B00, 0xFF7B73)
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
            let light = NSColor(hex: pair.light, alpha: alpha.light)
            let darkColour = NSColor(hex: pair.dark, alpha: alpha.dark)
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
        static var xs: CGFloat { 4.zoomed }
        static var s: CGFloat { 8.zoomed }
        static var m: CGFloat { 12.zoomed }
        static var l: CGFloat { 16.zoomed }
        static var xl: CGFloat { 24.zoomed }
        static var xxl: CGFloat { 32.zoomed }
    }

    /// Every corner the product draws. Ten literals were in use — 1, 2, 3, 4,
    /// 5, 6, 7, 8, 9, 13 — where five steps do the work: a bar's end, a small
    /// mark, a control, a well inside a card, a nested panel. The entry card
    /// and rail tile keep their reference radii in `StoryStyle`.
    enum Radius {
        static var panel: CGFloat { 16.zoomed }
        static var nested: CGFloat { 12.zoomed }
        /// Larger than any shape, not a length: it does not follow the zoom.
        static let capsule: CGFloat = 999
        /// A well inside a card: the scope control, a notice, a month cell.
        static var well: CGFloat { 9.zoomed }
        /// A button. The reference's 7-point control corner.
        static var control: CGFloat { 7.zoomed }
        static var swatch: CGFloat { 5.zoomed }
        /// A small mark: a hover tint behind a row, a chart's clip.
        static var mark: CGFloat { 4.zoomed }
        static var bar: CGFloat { 3.zoomed }
    }

    /// The height of the menu bar panel's controls: the activity field, the
    /// category menu and Start. Each set its own, and Start stood 6pt shorter
    /// than the two beside it.
    enum Control {
        static var compactHeight: CGFloat { 34.zoomed }
        /// The label inside every Settings pop-up (`RowMenu`), so they share
        /// one width; "While the window is open", the longest choice, fits.
        /// Text stops shrinking before the zoom does, so the width has a
        /// floor: at 80% that choice read "While the window is op…".
        static var rowMenuLabelWidth: CGFloat { max(172, 180.zoomed) } // zoom: fixed
    }

    static var popoverWidth: CGFloat { 340.zoomed }
    /// The widest a form row should ever be: an intent field, a settings row, a
    /// primary button. Text and controls have a comfortable measure that does
    /// not grow with the window.
    static var formMeasure: CGFloat { 340.zoomed }
    /// `2h 15m`, `15m`, `0m`.
    static func duration(_ seconds: TimeInterval) -> String {
        DurationText.compact(seconds)
    }

    /// `01:23:45` for the live hero timer.
    static func clock(_ seconds: TimeInterval) -> String {
        guard let total = DurationText.wholeSeconds(seconds) else { return "—" }
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    /// `2 hours`, `2 hours 13 minutes`, `13 minutes`, `45 seconds` — the spoken
    /// form used in per-app history, where `2h 13m` reads as too terse.
    static func spent(_ seconds: TimeInterval) -> String {
        guard let total = DurationText.wholeSeconds(seconds) else { return "—" }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let minutePart = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        if hours > 0 {
            let hourPart = hours == 1 ? "1 hour" : "\(hours) hours"
            return minutes > 0 ? "\(hourPart) \(minutePart)" : hourPart
        }
        if minutes > 0 { return minutePart }
        return total == 1 ? "1 second" : "\(total) seconds"
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

    /// `2:13 pm – 4:13 pm`, or `14:13 – 16:13` on a 24-hour clock, each time
    /// unbreakable so a wrapped line cannot end on "2:13" and begin on
    /// "pm – 4:13 pm".
    static func timeRange(_ start: Date, _ end: Date, locale: Locale = .current) -> String {
        DateFormats.clockRange(start, end, locale: locale)
    }

    /// Sub-minute stretches are common in app usage, where `duration` floors to
    /// "0m" and a real 45-second stretch renders as nothing.
    static func preciseDuration(_ seconds: TimeInterval) -> String {
        DurationText.precise(seconds)
    }

    /// `Today`, `Yesterday`, or `Wed, 13 Aug`: the day as the locale writes it.
    static func dayLabel(_ date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return DateFormats.shortDay(date, locale: locale)
    }

    /// `since 2:13 pm`, for a launch time.
    static func timeOfDay(_ date: Date, locale: Locale = .current) -> String {
        "since \(DateFormats.clockTime(date, locale: locale))"
    }

    /// `Wednesday`, for a sentence that names a day rather than dating it.
    static func weekdayName(_ date: Date, locale: Locale = .current) -> String {
        DateFormats.localized("EEEE", locale: locale).string(from: date)
    }

    /// `2:13 pm` on its own, for a column that already means "when".
    static func timeOfDayOnly(_ date: Date, locale: Locale = .current) -> String {
        DateFormats.clockTime(date, locale: locale)
    }

    /// `Saturday 22 August`, for the dashboard's title band.
    static func longDate(_ date: Date, locale: Locale = .current) -> String {
        DateFormats.longDate(date, locale: locale)
    }

    /// A span of days the way the chrome writes one: `24 – 30 Aug`,
    /// `31 Aug – 6 Sep`, and the year only when it is not this year —
    /// `28 Dec 2025 – 3 Jan 2026`. Story wrote `31 Aug–6 September 2026` and
    /// Insights wrote `31 Aug–6 Sep` for the same week, and the longer one
    /// cost the bar twenty points at its minimum width.
    static func dateRange(_ start: Date, _ end: Date, now: Date = Date(),
                          calendar: Calendar = .current, locale: Locale = .current) -> String {
        DateFormats.dateRange(start, end, now: now, calendar: calendar, locale: locale)
    }

    // MARK: Palette

    enum Palette {
        /// The Apple system hues, in light and dark variants.
        private static func pair(_ hue: WorkTypeHue) -> (light: UInt32, dark: UInt32) {
            switch hue {
            case .blue: return (0x007AFF, 0x0A84FF)
            case .teal: return (0x30B0C7, 0x40C8E0)
            case .orange: return (0xFF9500, 0xFF9F0A)
            case .indigo: return (0x5E5CE6, 0x7D7AFF)
            case .pink: return (0xFF375F, 0xFF6482)
            case .purple: return (0xAF52DE, 0xBF5AF2)
            case .green: return (0x34C759, 0x30D158)
            case .yellow: return (0xFFCC00, 0xFFD60A)
            case .red: return (0xFF3B30, 0xFF453A)
            case .brown: return (0xA2845E, 0xAC8E68)
            case .grey: return (0x8E8E93, 0x98989D)
            }
        }

        /// The neutral grey of an aggregated "Other" bucket, never of one app.
        static let untracked = Color(lightHex: 0x8E8E93, darkHex: 0x98989D)
        static let warmGrey = Color(lightHex: 0x8E8E93, darkHex: 0x98989D)
        /// Every app mark: bar, strip, swatch and dot. Apps are told apart by
        /// icon and name, never by colour, so no two collide.
        static let appUse = Tokens.Colour.focus

        /// Fixed identities, matching the approved design's composition legend:
        /// deep work indigo, meetings orange, admin teal, learning pink, rest
        /// neutral grey. Rest must never look like work. A category the user
        /// makes wears whichever hue they chose for it.
        static func workType(_ type: WorkType) -> Color { hue(type.hue) }

        static func hue(_ hue: WorkTypeHue) -> Color {
            let colours = pair(hue)
            return Color(lightHex: colours.light, darkHex: colours.dark)
        }
    }

    /// The design's motion notes as one contract. Every value is short,
    /// interruptible and explains a state change; nothing here is decorative,
    /// and `reduceMotion` collapses all of it to an instant cut.
    enum Motion {
        /// One curve family — ease-out quint — so everything that settles in
        /// this app decelerates the same way. No bounce, no overshoot: motion
        /// here says what changed, never that it is animating.
        private static func out(_ duration: Double) -> Animation {
            .timingCurve(0.22, 1, 0.36, 1, duration: duration)
        }

        /// The way down. Faster than a click, or a click never shows it.
        static let press = out(0.08)
        /// The way back up: a critically damped spring, so a released control
        /// settles in one smooth arc and never travels past its rest size.
        static let release = Animation.spring(response: 0.32, dampingFraction: 1.0)
        /// A hover is a tint, never a colour jump.
        static let hover = out(0.16)
        /// The selection pill travels rather than redrawing, so the eye follows
        /// one object across the row.
        static let selection = out(0.20)
        /// A live figure rolling to its next value: a timer's seconds.
        static let tick = out(0.20)
        /// Content settling into place after a view change.
        static let rise = out(0.22)
        /// One reading replacing another: a scope or period change.
        static let swap = out(0.24)
        /// Something opening — the strip, a disclosure, a fold.
        static let reveal = out(0.26)
        /// Something closing. Exits are quicker than entrances.
        static let dismiss = out(0.19)
        /// A measurement moving to its next measurement — a ring, a bar.
        /// Critically damped: it arrives, it does not spring past.
        static let settle = Animation.spring(response: 0.45, dampingFraction: 0.92)

        static func animation(_ base: Animation, reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : base
        }

        static func transition(_ base: AnyTransition, reduceMotion: Bool) -> AnyTransition {
            reduceMotion ? .identity : base
        }

        /// Something arriving from beneath an edge: the session strip under
        /// the chrome.
        static let slideDown: AnyTransition = .move(edge: .top).combined(with: .opacity)
        /// Disclosed content: it grows from where its header sits and fades
        /// straight out.
        static let unfold: AnyTransition = .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)),
            removal: .opacity)
        /// One reading replacing another, nudged the way the reader stepped.
        /// A nudge, not a page turn: 28 points, so the movement reads as
        /// direction without the content leaving the window.
        static func slide(from edge: Edge) -> AnyTransition {
            let distance = edge == .trailing ? 28.zoomed : -28.zoomed
            return .asymmetric(
                insertion: .modifier(active: Nudge(x: distance, opacity: 0),
                                     identity: Nudge(x: 0, opacity: 1)),
                removal: .modifier(active: Nudge(x: -distance, opacity: 0),
                                   identity: Nudge(x: 0, opacity: 1)))
        }
    }

    /// Layout metrics for compact and comfortable density.
    enum Density {
        static var compactRowHeight: CGFloat { 44.zoomed }
        static var comfortableRowHeight: CGFloat { 52.zoomed }
    }
}

/// App-specific density in both display and settings.
extension InterfaceDensity {
    struct Layout {
        let rowHeight: CGFloat
        let panelSpacing: CGFloat
        let insetPadding: CGFloat
        let sectionSpacing: CGFloat

        static var comfortable: Layout {
            Layout(rowHeight: Tokens.Density.comfortableRowHeight,
                   panelSpacing: Tokens.Space.xl,
                   insetPadding: Tokens.Space.l,
                   sectionSpacing: Tokens.Space.l)
        }
        static var compact: Layout {
            Layout(rowHeight: Tokens.Density.compactRowHeight,
                   panelSpacing: Tokens.Space.l,
                   insetPadding: Tokens.Space.m,
                   sectionSpacing: Tokens.Space.m)
        }
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

private struct Nudge: ViewModifier {
    let x: CGFloat
    let opacity: Double
    func body(content: Content) -> some View { content.offset(x: x).opacity(opacity) }
}
