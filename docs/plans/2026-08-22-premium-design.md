# Premium Design (Direction A) Implementation Plan

**Goal:** Re-skin and restructure the menu-bar popover, the dashboard and the menu-bar item to the native-premium direction — tonal surfaces, one accent, a curated data palette, SF Rounded numerals, a goal ring — and move Settings into a standard macOS Settings window.

**Architecture:** All colour, type and radius decisions move into `DesignTokens.swift` (`Surface`, `Palette`, `Type`, `Radius`); a small set of plain-value components (`GoalRing`, `StatCard`, `DataBar`, `AppSwatch`, `IconButton`, `.card()`) is built once and used by every surface. The popover splits into a folder (`Surfaces/Popover/`), loses its settings form, and gains a hero card; the dashboard becomes a title band, a stat band and cards; a `SettingsModel` wraps `PersistenceStore` for a `Settings` scene; `MenuBarGlyph` rasterises a goal ring for the status item inside the existing tick.

**Tech Stack:** Swift 5, SwiftUI, AppKit where macOS requires it; `swiftc` via `./build.sh`; no SPM, no Xcode project, no packages. macOS 13.0 target.

**Spec:** `docs/specs/2026-08-22-premium-design-design.md`

## Global Constraints

- **Not a git repository.** Commit steps are recorded but skipped. Do not run `git init`.
- **No Xcode on this machine.** `@State` and `@Observable` do not compile — the SDK ships no `SwiftUIMacros` plugin. All view state lives in `ObservableObject` + `@Published`, consumed via `@StateObject` / `@ObservedObject` / `@EnvironmentObject`. `@Binding`, `@Environment`, `@FocusState` and `@AppStorage` work normally.
- **`Sources/Core/` imports Foundation and CoreGraphics only** — never SwiftUI or AppKit. (Now fully true; keep it so.)
- **Exactly one repeating `Timer` in the app**: the one-second ticker in `SessionStore.startTicker()`. Do not add another.
- **No new TCC permissions.** No third-party packages. No `-warnings-as-errors` violations: `./build.sh` must print no warnings.
- **Files under 500 lines**; nothing written to the project root; never delete — move to `_trash/` preserving the filename; confirm-before-move is already granted for the moves this plan names (spec §9).
- **Snapshot harness** (`--snapshot`, `ImageRenderer`) cannot draw `TextField`, `Toggle`, `Picker`, `DisclosureGroup`, `.borderless` buttons, materials or `ScrollView`. Those are verified in the live app; every other change is checked by rendering and *looking at* the PNG.
- **Copy:** sentence case; no punctuation on labels; explanatory footers end with a period.
- Test commands throughout: `./build.sh 2>&1 | grep -E "error|warning|Build succeeded"` then `./FocusContinuity.app/Contents/MacOS/FocusContinuity --selftest 2>&1 | grep -E "FAIL|passed"`. Snapshot: `./FocusContinuity.app/Contents/MacOS/FocusContinuity --snapshot /private/tmp/claude-501/-Users-prabeshbhetwal-Desktop-Files-Development-Project-FocusContinuity/d9e74462-42ba-4aac-8014-68ac6cc6464b/scratchpad/snaps` then open the PNGs.
- Relaunch after a task that changes what the live app shows: `pkill -x FocusContinuity; sleep 1; open FocusContinuity.app`.

---

## File structure

| File | Responsibility |
|---|---|
| `Sources/Design/DesignTokens.swift` (modify) | `Tokens.Surface`, `Tokens.Palette`, `Tokens.Typography`, `Tokens.Radius`, `Color(light:dark:)`, formatters |
| `Sources/Design/Components/AppIcon.swift` (modify) | `TimelinePalette` becomes a forwarder to `Tokens.Palette` so every existing call site re-skins at once |
| `Sources/Design/Components/Cards.swift` (create) | `.card()` modifier, `StatCard`, `DataBar`, `AppSwatch`, `IconButton` |
| `Sources/Design/Components/GoalRing.swift` (create) | `GoalRing` |
| `Sources/Design/MenuBarGlyph.swift` (create) | ring → template `NSImage` |
| `Sources/Design/Components/Components.swift` (modify) | `StartButton`, `ResolveCard`, `MenuBarLabel` restyle |
| `Sources/Surfaces/Dashboard/DashboardSections.swift` (modify) | `SectionHeader` restyle; lists become card-ready, day-aware titles |
| `Sources/App/SettingsModel.swift` (create) | settings bridge for the Settings scene |
| `Sources/Surfaces/Settings/SettingsView.swift` (create) | four-tab grouped form |
| `Sources/App/FocusContinuityApp.swift`, `AppCoordinator.swift` (modify) | `Settings` scene; `settings` model |
| `Sources/Surfaces/Popover/PopoverView.swift` (move+modify), `HeroCard.swift`, `GlanceCards.swift`, `PopoverFooter.swift` (create) | the popover, split |
| `Sources/Surfaces/GoalBar.swift` → `_trash/` | superseded by `GoalRing` |
| `Sources/Surfaces/Dashboard/DashboardView.swift`, `PeriodViews.swift`, `DayTimelineView.swift` (modify) | title band, stat band, cards, palette |
| `Sources/Core/PeriodStats.swift` (modify) | `previousPeriodTracked` |
| `Sources/Core/DashboardStats.swift` (modify) | insight headline without "today" |
| `Sources/App/SessionStore.swift` (modify) | settings accessors out; `trackedYesterday`, `previousPeriodTracked` in |
| `Sources/Surfaces/Snapshotter.swift`, `GalleryView.swift` (modify) | harness follows the new views |
| `Sources/SelfTest.swift` (modify) | tests 80–84 |

---

### Task 1: Foundations — tokens and the palette forwarder

**Files:**
- Modify: `Sources/Design/DesignTokens.swift`
- Modify: `Sources/Design/Components/AppIcon.swift:83-108` (`TimelinePalette`)
- Test: `Sources/SelfTest.swift`

**Interfaces:**
- Produces: `Tokens.Surface.{ground,card,well,hairline,hover}: Color`; `Tokens.Palette.app(rank: Int) -> Color`, `Tokens.Palette.workType(_: WorkType) -> Color`, `Tokens.Palette.untracked: Color`, `Tokens.Palette.resolved(rank: Int, dark: Bool) -> (r: Double, g: Double, b: Double)`; `Tokens.Typography.{heroTimer,stat,ringLabel,title,sectionLabel,row,detail}: Font`; `Tokens.Radius.{card,control,swatch,bar}: CGFloat`; `Tokens.Space.xxl`; `Tokens.longDate(_:)`; `Color(light:dark:)`, `Color(lightHex:darkHex:)`, `NSColor(hex:alpha:)`.
- `TimelinePalette.color(_:)` and `.color(for:)` keep their signatures and now return the new palette.

- [ ] **Step 1: Write the failing test**

Add to `Sources/SelfTest.swift`, immediately before `    // MARK: - 60`:

```swift
    // MARK: - 80

    /// Seven distinct app colours in both appearances, clamped past the end,
    /// and a total work-type mapping. Pins the palette so a later edit cannot
    /// quietly give two apps one colour or leave a work type on a default.
    private static func testPalette() -> [String] {
        var problems: [String] = []
        for dark in [false, true] {
            var seen: Set<String> = []
            for rank in 0..<7 {
                let c = Tokens.Palette.resolved(rank: rank, dark: dark)
                seen.insert(String(format: "%.3f-%.3f-%.3f", c.r, c.g, c.b))
            }
            expect(seen.count == 7,
                   "seven distinct app colours in \(dark ? "dark" : "light"), got \(seen.count)",
                   &problems)
        }
        let light0 = Tokens.Palette.resolved(rank: 0, dark: false)
        let dark0 = Tokens.Palette.resolved(rank: 0, dark: true)
        expect(light0 != dark0, "the pair flips with the appearance", &problems)
        let beyond = Tokens.Palette.resolved(rank: 42, dark: false)
        let other = Tokens.Palette.resolved(rank: 6, dark: false)
        expect(beyond == other, "ranks past the end read as Other", &problems)
        let negative = Tokens.Palette.resolved(rank: -1, dark: false)
        let first = Tokens.Palette.resolved(rank: 0, dark: false)
        expect(negative == first, "a negative rank clamps to the first", &problems)
        for type in WorkType.allCases {
            _ = Tokens.Palette.workType(type)   // total: every case compiles to a colour
        }
        return problems
    }
```

Register it after the `testDayScopedSessionFigures` entry:

```swift
            ("Palette: seven distinct app colours, both appearances, total work types",
             testPalette)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./build.sh 2>&1 | grep -E "error" | head -3`
Expected: `error: type 'Tokens' has no member 'Palette'`

- [ ] **Step 3: Add the tokens**

In `Sources/Design/DesignTokens.swift`, replace the whole `enum Tokens {` opening through `static let statNumberFont = ...` (the block ending just before `/// \`2h 15m\`, \`15m\`, \`0m\`.`) with:

```swift
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
    enum Type {
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
    static let heroTimerFont = Type.heroTimer
    static let statNumberFont = Type.stat
```

Then append, after `static func timeOfDay(_ date: Date) -> String { ... }` and before the closing `}` of `enum Tokens`:

```swift

    private static let longDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMMM"
        return formatter
    }()

    /// `Saturday 22 August`, for the dashboard's title band.
    static func longDate(_ date: Date) -> String {
        longDateFormatter.string(from: date)
    }
```

And append at the very end of the file (outside `enum Tokens`):

```swift

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
```

- [ ] **Step 4: Point `TimelinePalette` at the new palette**

In `Sources/Design/Components/AppIcon.swift`, replace the whole `enum TimelinePalette { ... }` with:

```swift
/// Forwarder. Every timeline, bar and chart already asks this by rank or by work
/// type; routing it through `Tokens.Palette` re-skins all of them at once and
/// leaves one definition of each colour.
enum TimelinePalette {
    static func color(_ index: Int) -> Color { Tokens.Palette.app(rank: index) }
    static func color(for workType: WorkType) -> Color { Tokens.Palette.workType(workType) }
    /// Time inside a tracked app but outside any focus session.
    static let untrackedLabel = "Untracked work"
    static let untracked = Tokens.Palette.untracked
}
```

- [ ] **Step 5: Build, run the test, look at a snapshot**

Run the build and selftest commands.
Expected: `Build succeeded`, `80/80 passed`.

Run the snapshot command and open `dashboard-running-dark.png` and `running-light.png`. Expected: bars, timeline segments and the period chart now use the muted palette (blue/teal/amber/violet…), darker tones in light mode and lighter in dark. If the dark render shows the *light* hex values, the dynamic provider is not honouring the harness's colour scheme — in that case change `Color(light:dark:)` to read `NSAppearance.currentDrawing()` and add `.environment(\.colorScheme, scheme)` is already present; report it and stop.

- [ ] **Step 6: Commit** *(recorded, skipped — not a git repository)*

```bash
git add Sources/Design/DesignTokens.swift Sources/Design/Components/AppIcon.swift Sources/SelfTest.swift
git commit -m "design: surfaces, palette, type and radius tokens; palette forwarder"
```

---

### Task 2: Components — card, ring, stat card, bar, swatch, icon button

**Files:**
- Create: `Sources/Design/Components/Cards.swift`
- Create: `Sources/Design/Components/GoalRing.swift`
- Modify: `Sources/Design/Components/Components.swift` (`StartButton`, `ResolveCard`)
- Modify: `Sources/Surfaces/Dashboard/DashboardSections.swift:5-24` (`SectionHeader`)

**Interfaces:**
- Produces: `View.card(padding: CGFloat = Tokens.Space.l, surface: Color = Tokens.Surface.card) -> some View`; `StatCard(label: String, value: String, context: String? = nil, contextTint: Color? = nil)`; `DataBar(share: Double, tint: Color)`; `AppSwatch(rank: Int, bundleID: String?, appName: String = "", size: CGFloat = 18)`; `IconButton(systemImage: String, help: String, prominent: Bool = false, action: @escaping () -> Void)`; `GoalRing(progress: Double, diameter: CGFloat = 64, lineWidth: CGFloat = 7, label: String? = nil, isMet: Bool = false)`.
- `SectionHeader(title:trailing:)` keeps its signature (this is the spec's `SectionLabel`).

- [ ] **Step 1: Create `Cards.swift`**

```swift
import SwiftUI

// The card vocabulary shared by the popover and the dashboard. Plain values in,
// so the gallery can drive every one of these from fixtures.

private struct CardModifier: ViewModifier {
    let padding: CGFloat
    let surface: Color

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card,
                                                      style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                    .strokeBorder(Tokens.Surface.hairline, lineWidth: 1)
            )
    }
}

extension View {
    /// A lifted surface on the ground: `Surface.card`, continuous 12pt corners,
    /// one hairline. Cards size to their content; the ground between them is
    /// the layout.
    func card(padding: CGFloat = Tokens.Space.l,
              surface: Color = Tokens.Surface.card) -> some View {
        modifier(CardModifier(padding: padding, surface: surface))
    }
}

/// One headline figure with the line that gives it meaning. A bare number is
/// what the old stat row showed; the context line is what makes it a card.
struct StatCard: View {
    let label: String
    let value: String
    var context: String?
    var contextTint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            SectionHeader(title: label)
            Text(value)
                .font(Tokens.Typography.stat)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(context ?? " ")
                .font(Tokens.Typography.detail)
                .foregroundStyle(contextTint.map(AnyShapeStyle.init)
                                 ?? AnyShapeStyle(.secondary))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: Tokens.Space.m)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)\(context.map { ", \($0)" } ?? "")")
    }
}

/// Share of something, as a 6pt bar in a well. The number beside it carries
/// the fact; this carries the shape.
struct DataBar: View {
    let share: Double
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Tokens.Surface.well)
                Capsule()
                    .fill(tint)
                    .frame(width: max(3, geometry.size.width * min(1, max(0, share))))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// An app's icon with its palette colour beside it, so the row is its own
/// legend. Falls back to a rounded square in the colour when the app has no
/// icon on this machine.
struct AppSwatch: View {
    let rank: Int
    var bundleID: String?
    var appName: String = ""
    var size: CGFloat = 18

    var body: some View {
        HStack(spacing: Tokens.Space.xs) {
            if let bundleID,
               AppIconProvider.shared.icon(for: bundleID, size: size) != nil {
                AppIcon(bundleID: bundleID, size: size, appName: appName)
            } else {
                RoundedRectangle(cornerRadius: Tokens.Radius.swatch, style: .continuous)
                    .fill(Tokens.Palette.app(rank: rank))
                    .frame(width: size, height: size)
                    .overlay(
                        Text(appName.first.map(String.init)?.uppercased() ?? "")
                            .font(.system(size: size * 0.55, weight: .semibold))
                            .foregroundStyle(.white)
                    )
            }
            Circle()
                .fill(Tokens.Palette.app(rank: rank))
                .frame(width: 6, height: 6)
        }
        .accessibilityHidden(true)
    }
}

/// A round 28pt button for the places a word would be louder than the action
/// deserves. Always carries a tooltip, because a glyph alone is a guess.
struct IconButton: View {
    let systemImage: String
    let help: String
    var prominent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 28, height: 28)
                .background(prominent ? AnyShapeStyle(Color.accentColor.opacity(0.15))
                                      : AnyShapeStyle(Tokens.Surface.well),
                            in: Circle())
                .foregroundStyle(prominent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
```

- [ ] **Step 2: Create `GoalRing.swift`**

```swift
import SwiftUI

/// The app's signature element: the day's goal as a ring. Accent fill over a
/// well track, round caps, a label in the middle — the share, or a check once
/// the goal is met. Animates on change and nowhere else.
struct GoalRing: View {
    let progress: Double
    var diameter: CGFloat = 64
    var lineWidth: CGFloat = 7
    var label: String?
    var isMet: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Tokens.Surface.well, lineWidth: lineWidth)
            Circle()
                // Drawn clamped; `progress` itself may exceed 1 so the figures
                // beside it can say "160%" honestly.
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(Color.accentColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progress)
            if isMet {
                Image(systemName: "checkmark")
                    .font(.system(size: diameter * 0.3, weight: .bold))
                    .foregroundStyle(.tint)
            } else if let label {
                Text(label)
                    .font(Tokens.Typography.ringLabel)
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, lineWidth + 2)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int((progress * 100).rounded())) percent of today's goal")
    }
}
```

- [ ] **Step 3: Restyle `SectionHeader`, `StartButton` and `ResolveCard`**

In `Sources/Surfaces/Dashboard/DashboardSections.swift`, replace the `SectionHeader` struct body with:

```swift
struct SectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(Tokens.Typography.sectionLabel)
                .kerning(0.7)
                .foregroundStyle(.secondary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(Tokens.Typography.detail)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
```

In `Sources/Design/Components/Components.swift`, replace `StartButton`'s `body` with:

```swift
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "play.fill")
                .font(.callout.weight(.semibold))
                .frame(maxWidth: fills ? .infinity : nil)
                .padding(.horizontal, Tokens.Space.m)
                .padding(.vertical, 7)
                .background(Color.accentColor,
                            in: RoundedRectangle(cornerRadius: Tokens.Radius.control,
                                                 style: .continuous))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
```

Replace `ResolveCard`'s `body` with:

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Label("Away \(Tokens.duration(away))", systemImage: "moon.zzz.fill")
                .font(.headline)
                .symbolRenderingMode(.hierarchical)
            Text("Not counted. Your session is still running.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            // Two rows. The first holds the two answers to the question; the
            // second holds the options that restructure instead. "I was
            // working" must never truncate — it is the answer that changes the
            // numbers.
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                HStack(spacing: Tokens.Space.s) {
                    if let onRest {
                        Button("It was a break", action: onRest)
                            .buttonStyle(.borderedProminent)
                            .help("Not counted, and written down as "
                                  + "\(Tokens.duration(away)) of rest")
                    }
                    Button("I was working", action: onMerge)
                        .help("Count the \(Tokens.duration(away)) as work on this session")
                    Spacer(minLength: 0)
                }
                HStack(spacing: Tokens.Space.m) {
                    Button("I was away", action: onBreak)
                        .help("Not counted, and nothing recorded for it")
                    Button("Start fresh instead", action: onDiscard)
                        .help("End that session where you left off and begin a new one")
                    Spacer(minLength: 0)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .lineLimit(1)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: Tokens.Space.m)
    }
```

Also in `Components.swift`, replace `StatTile`'s `.background(.regularMaterial, in: RoundedRectangle(cornerRadius: Tokens.cardCorner))` line with `.card(padding: 0)` and remove its `.padding(Tokens.Space.m)` line, replacing both with a single `.card(padding: Tokens.Space.m)` — i.e. the `StatTile` body ends:

```swift
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: Tokens.Space.m)
        .accessibilityElement(children: .combine)
```

- [ ] **Step 4: Build and snapshot**

Run the build and selftest commands. Expected: `Build succeeded`, `80/80 passed`.
Run the snapshot command; open `needsResolution-dark.png`. Expected: the away card is now a lifted card with a hairline; the Start button in `idleWithHistory-light.png` is an accent-filled rounded rectangle that does not stretch.

- [ ] **Step 5: Commit** *(recorded, skipped)*

```bash
git add Sources/Design/Components/Cards.swift Sources/Design/Components/GoalRing.swift Sources/Design/Components/Components.swift Sources/Surfaces/Dashboard/DashboardSections.swift
git commit -m "design: card vocabulary, goal ring, stat card, bar, swatch, icon button"
```

---

### Task 3: Menu-bar glyph

**Files:**
- Create: `Sources/Design/MenuBarGlyph.swift`
- Modify: `Sources/Design/Components/Components.swift` (`MenuBarLabelView`, `MenuBarLabel`)
- Test: `Sources/SelfTest.swift`

**Interfaces:**
- Produces: `enum MenuBarGlyph { @MainActor static func image(progress: Double, paused: Bool, attention: Bool, isMet: Bool) -> NSImage? }`
- `MenuBarLabel(state:elapsed:needsAttention:goal:)` gains `goal: GoalProgress`.

- [ ] **Step 1: Write the failing test**

Add before `    // MARK: - 60`:

```swift
    // MARK: - 81

    /// The status-item ring renders for every state it can be in. A nil image
    /// would fall back to the infinity glyph silently, which is exactly the
    /// kind of quiet regression a test exists to shout about.
    private static func testMenuBarGlyph() -> [String] {
        var problems: [String] = []
        let states: [(Double, Bool, Bool, Bool)] = [
            (0, false, false, false), (0.63, false, false, false),
            (0.63, true, false, false), (0.63, false, true, false),
            (1.0, false, false, true)
        ]
        for (progress, paused, attention, met) in states {
            let image = MainActor.assumeIsolated {
                MenuBarGlyph.image(progress: progress, paused: paused,
                                   attention: attention, isMet: met)
            }
            expect(image != nil, "glyph renders for progress \(progress) paused \(paused) "
                   + "attention \(attention) met \(met)", &problems)
            expect(image?.isTemplate == true, "and is a template image", &problems)
            expect(image.map { $0.size.width == 16 && $0.size.height == 16 } == true,
                   "at 16×16 points", &problems)
        }
        return problems
    }
```

Register after `testPalette`:

```swift
            ("Menu-bar glyph renders a template ring for every state", testMenuBarGlyph)
```

- [ ] **Step 2: Run to verify it fails**

Run the build. Expected: `error: cannot find 'MenuBarGlyph' in scope`.

- [ ] **Step 3: Create `MenuBarGlyph.swift`**

```swift
import SwiftUI
import AppKit

/// The status item's ring: the day's goal progress, drawn as a 16pt template
/// image so it takes the menu bar's own tint. Rasterised on demand inside the
/// existing tick — the label view re-evaluates whenever `elapsed` or `goal`
/// publishes, which is what drives this — so there is no timer here.
enum MenuBarGlyph {

    private struct Ring: View {
        let progress: Double
        let paused: Bool
        let attention: Bool
        let isMet: Bool

        var body: some View {
            ZStack {
                Circle().stroke(Color.black.opacity(0.28), lineWidth: 2.2)
                Circle()
                    .trim(from: 0, to: min(1, max(0, progress)))
                    .stroke(Color.black, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if isMet {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(.black)
                } else if paused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 6.5, weight: .heavy))
                        .foregroundStyle(.black)
                }
                if attention {
                    Circle()
                        .fill(Color.black)
                        .frame(width: 5, height: 5)
                        .offset(x: 5.5, y: -5.5)
                }
            }
            .frame(width: 16, height: 16)
            .padding(1)
        }
    }

    @MainActor
    static func image(progress: Double, paused: Bool, attention: Bool,
                      isMet: Bool) -> NSImage? {
        let renderer = ImageRenderer(content: Ring(progress: progress, paused: paused,
                                                   attention: attention, isMet: isMet))
        renderer.scale = 2
        guard let image = renderer.nsImage else { return nil }
        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = true
        return image
    }
}
```

- [ ] **Step 4: Use it in the label**

In `Components.swift`, replace `MenuBarLabelView` and `MenuBarLabel` with:

```swift
/// Observing wrapper for the menu bar label. A `Scene` body does not observe
/// an `ObservableObject`, so the label must be a `View` holding
/// `@ObservedObject` or it renders once, at launch, and never again.
struct MenuBarLabelView: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        MenuBarLabel(state: store.state,
                     elapsed: store.elapsed,
                     needsAttention: store.pendingAway != nil,
                     goal: store.goal)
            .accessibilityLabel(store.state == .idle
                                ? "FocusContinuity, \(Int((store.goal.share * 100).rounded())) "
                                  + "percent of today's goal, no session running"
                                : "Current session \(Tokens.spent(store.elapsed))")
    }
}

/// The menu bar's ambient state: a goal ring always, elapsed while a session
/// runs, a pause mark when paused, a dot when a question is waiting.
struct MenuBarLabel: View {
    let state: SessionState
    let elapsed: TimeInterval
    let needsAttention: Bool
    var goal = GoalProgress(goal: FocusConstants.defaultDailyGoal, achieved: 0, typical: nil)

    var body: some View {
        HStack(spacing: Tokens.Space.xs) {
            if let glyph = MenuBarGlyph.image(progress: goal.share,
                                              paused: state.isPaused,
                                              attention: needsAttention,
                                              isMet: goal.isMet) {
                Image(nsImage: glyph)
            } else {
                Image(systemName: needsAttention ? "exclamationmark.circle.fill" : "infinity")
            }
            if state != .idle {
                Text(Tokens.duration(elapsed))
                    .font(Tokens.menuBarFont)
            }
        }
        .foregroundStyle(state.isPaused ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
    }
}
```

`MenuBarLabel` is a `View` evaluated on the main actor, so the `@MainActor` call compiles there. If the compiler objects, mark `struct MenuBarLabel: View` `@MainActor`.

- [ ] **Step 5: Build, test, relaunch, look at the menu bar**

Run build and selftest. Expected: `81/81 passed`. Relaunch the app. Expected in the menu bar: a ring glyph (partly filled) and, with a session running, the elapsed beside it; pause the session from the popover and the glyph shows a pause mark.

- [ ] **Step 6: Commit** *(recorded, skipped)*

```bash
git add Sources/Design/MenuBarGlyph.swift Sources/Design/Components/Components.swift Sources/SelfTest.swift
git commit -m "menubar: goal ring glyph as a template image"
```

---

### Task 4: Settings window and `SettingsModel`; settings leave the popover

**Files:**
- Create: `Sources/App/SettingsModel.swift`
- Create: `Sources/Surfaces/Settings/SettingsView.swift`
- Modify: `Sources/App/FocusContinuityApp.swift`
- Modify: `Sources/App/AppCoordinator.swift` (a `settings` model)
- Modify: `Sources/App/SessionStore.swift` (settings accessors out)
- Modify: `Sources/Surfaces/PopoverView.swift` (settings section out; gear in the footer)
- Modify: `Sources/Surfaces/Snapshotter.swift` (`settingsAlwaysOpen` argument removed)
- Test: `Sources/SelfTest.swift`

**Interfaces:**
- Produces: `final class SettingsModel: ObservableObject` with settable `dailyGoal: TimeInterval`, `autoSessionsEnabled: Bool`, `rewardsEnabled: Bool`, `remindersEnabled: Bool`, `breakThreshold: TimeInterval`, `longAwayCap: TimeInterval`, `breakLength: TimeInterval`, `menuSessionCount: Int`, `isTrackingEnabled: Bool`; `init(store: PersistenceStore, isTrackingEnabled: Bool, onChange: @escaping () -> Void, onTrackingChanged: @escaping (Bool) -> Void)`; `static func openWindow()`.
- `SessionStore` keeps read-only `menuSessionCount`, `remindersEnabled`, `breakThreshold`, `longAwayCap` (used by views) and `setTrackingEnabled(_:)`; loses the setters for `dailyGoal`, `autoSessionsEnabled`, `rewardsEnabled`, `breakLength`.

- [ ] **Step 1: Write the failing test**

Add before `    // MARK: - 60`:

```swift
    // MARK: - 82

    /// Every settings write lands in the store and fires `onChange` exactly
    /// once, so the surfaces that read the store refresh, and a tracking toggle
    /// reaches the owner of the tracker rather than only the preference.
    private static func testSettingsModel() -> [String] {
        var problems: [String] = []
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let store = PersistenceStore(defaults: defaults)
        store.removeAll()
        var changes = 0
        var tracking: [Bool] = []
        let model = SettingsModel(store: store, isTrackingEnabled: true,
                                  onChange: { changes += 1 },
                                  onTrackingChanged: { tracking.append($0) })

        model.dailyGoal = 2 * 3_600
        expectClose(store.dailyGoal, 2 * 3_600, "daily goal writes through", &problems)
        model.autoSessionsEnabled = false
        expect(store.autoSessionsEnabled == false, "auto sessions write through", &problems)
        model.rewardsEnabled = false
        expect(store.rewardsEnabled == false, "rewards write through", &problems)
        model.remindersEnabled = false
        expect(store.remindersEnabled == false, "reminders write through", &problems)
        model.breakThreshold = 1_800
        expectClose(store.breakThreshold, 1_800, "ask-me-after writes through", &problems)
        model.longAwayCap = 2 * 3_600
        expectClose(store.longAwayCap, 2 * 3_600, "end-after writes through", &problems)
        model.breakLength = 15 * 60
        expectClose(store.breakLength, 15 * 60, "auto-session gap writes through", &problems)
        model.menuSessionCount = 7
        expect(store.menuSessionCount == 7, "sessions per app writes through", &problems)
        expect(changes == 8, "one change notification per write, got \(changes)", &problems)

        model.isTrackingEnabled = false
        expect(tracking == [false], "tracking goes to the tracker's owner", &problems)
        expect(model.isTrackingEnabled == false, "and the model remembers it", &problems)
        expect(changes == 8, "tracking does not double-fire onChange", &problems)
        return problems
    }
```

Register after `testMenuBarGlyph`:

```swift
            ("Settings model writes through and notifies once per change", testSettingsModel)
```

- [ ] **Step 2: Run to verify it fails**

Run the build. Expected: `error: cannot find 'SettingsModel' in scope`.

- [ ] **Step 3: Create `SettingsModel.swift`**

```swift
import SwiftUI
import AppKit

/// The Settings window's model. Wraps the `PersistenceStore` properties the
/// window edits and tells the session store to refresh after each write, so a
/// changed goal moves the ring and a changed threshold moves the away ladder
/// without either surface holding a reference to the other.
///
/// Properties are plain computed settables rather than `@Published`: the truth
/// lives in `UserDefaults`, and `ObservedObject`'s projected bindings work on
/// any settable property. `objectWillChange` is sent by hand before each write.
final class SettingsModel: ObservableObject {

    private let store: PersistenceStore
    private let onChange: () -> Void
    private let onTrackingChanged: (Bool) -> Void
    /// Mirrored here because the tracker — not the preference — is the truth
    /// about whether recording is on, and the tracker lives with the store.
    private var trackingEnabled: Bool

    init(store: PersistenceStore,
         isTrackingEnabled: Bool,
         onChange: @escaping () -> Void,
         onTrackingChanged: @escaping (Bool) -> Void) {
        self.store = store
        self.trackingEnabled = isTrackingEnabled
        self.onChange = onChange
        self.onTrackingChanged = onTrackingChanged
    }

    private func write(_ body: () -> Void) {
        objectWillChange.send()
        body()
        onChange()
    }

    var dailyGoal: TimeInterval {
        get { store.dailyGoal }
        set { write { store.dailyGoal = newValue } }
    }

    var autoSessionsEnabled: Bool {
        get { store.autoSessionsEnabled }
        set { write { store.autoSessionsEnabled = newValue } }
    }

    var rewardsEnabled: Bool {
        get { store.rewardsEnabled }
        set { write { store.rewardsEnabled = newValue } }
    }

    var remindersEnabled: Bool {
        get { store.remindersEnabled }
        set { write { store.remindersEnabled = newValue } }
    }

    var breakThreshold: TimeInterval {
        get { store.breakThreshold }
        set { write { store.breakThreshold = newValue } }
    }

    var longAwayCap: TimeInterval {
        get { store.longAwayCap }
        set { write { store.longAwayCap = newValue } }
    }

    var breakLength: TimeInterval {
        get { store.breakLength }
        set { write { store.breakLength = newValue } }
    }

    var menuSessionCount: Int {
        get { store.menuSessionCount }
        set { write { store.menuSessionCount = newValue } }
    }

    var isTrackingEnabled: Bool {
        get { trackingEnabled }
        set {
            objectWillChange.send()
            trackingEnabled = newValue
            onTrackingChanged(newValue)
        }
    }

    /// Opens the Settings scene. `SettingsLink` is macOS 14; on 13 the scene is
    /// reached through the responder chain, and the app must be frontmost first
    /// or the window opens behind whatever was.
    static func openWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
```

- [ ] **Step 4: Create `SettingsView.swift`**

```swift
import SwiftUI

/// Four tabs of grouped forms. The explanatory copy that used to crowd the
/// popover lives here as footers, where it has room to be read.
struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        TabView {
            goal.tabItem { Label("Goal", systemImage: "target") }
            away.tabItem { Label("Away and breaks", systemImage: "moon.zzz") }
            automatic.tabItem { Label("Automatic", systemImage: "wand.and.stars") }
            display.tabItem { Label("Display", systemImage: "macwindow") }
        }
        .frame(width: 480)
        .frame(minHeight: 300)
    }

    private var goal: some View {
        Form {
            Section {
                Picker("Daily goal", selection: $model.dailyGoal) {
                    ForEach(FocusConstants.dailyGoalOptions, id: \.self) {
                        Text(Tokens.duration($0)).tag($0)
                    }
                }
            } footer: {
                Text("Counts only focus sessions while you were actually using the Mac. "
                     + "Your usual pace compares today with the same hour on your last "
                     + "\(FocusConstants.goalMedianWindowDays) working days.")
            }
        }
        .formStyle(.grouped)
    }

    private var away: some View {
        Form {
            Section {
                Picker("Ask me after", selection: $model.breakThreshold) {
                    ForEach(FocusConstants.thresholdOptions, id: \.self) {
                        Text(Tokens.duration($0)).tag($0)
                    }
                }
                Picker("End session after", selection: $model.longAwayCap) {
                    ForEach(FocusConstants.longAwayCapOptions, id: \.self) {
                        Text(Tokens.duration($0)).tag($0)
                    }
                }
            } header: {
                Text("Stepping away")
            } footer: {
                Text("Under 5 seconds is ignored. Up to "
                     + "\(Tokens.duration(model.breakThreshold)) is left out of the session "
                     + "without interrupting you. Up to \(Tokens.duration(model.longAwayCap)) "
                     + "you are asked what it was, whether the screen locked or you simply "
                     + "stopped. Past that the session ends where you left.")
            }
            Section {
                Toggle("Remind me to take breaks", isOn: $model.remindersEnabled)
            } header: {
                Text("Breaks")
            } footer: {
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    ForEach(BreakTier.allCases, id: \.rawValue) { tier in
                        Text("\(Int(tier.workThreshold / 60)) minutes working → "
                             + "\(BreakPrompt.phrase(tier.breakLength)) off. \(tier.reason)")
                    }
                    Text("Timed from continuous use, not from sessions. A short break "
                         + "resets the short timer only; the longer ones keep running.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var automatic: some View {
        Form {
            Section {
                Toggle("Start sessions for me", isOn: $model.autoSessionsEnabled)
                Picker("Auto-session gap", selection: $model.breakLength) {
                    ForEach(FocusConstants.breakLengthOptions, id: \.self) {
                        Text(Tokens.duration($0)).tag($0)
                    }
                }
                Toggle("Celebrate milestones", isOn: $model.rewardsEnabled)
            } footer: {
                Text("Sessions the app starts can be undone from the notice, and one it "
                     + "ends on its own ends where the work stopped. The gap is how long "
                     + "a pause must be before such a session is treated as over.")
            }
        }
        .formStyle(.grouped)
    }

    private var display: some View {
        Form {
            Section {
                Picker("Sessions per app", selection: $model.menuSessionCount) {
                    ForEach([3, 5, 7, 10], id: \.self) { Text("\($0)").tag($0) }
                }
                Toggle("Record app usage", isOn: $model.isTrackingEnabled)
            } footer: {
                Text("Recording is local and keeps app names and bundle identifiers only — "
                     + "never window titles, addresses, or anything you type.")
            }
        }
        .formStyle(.grouped)
    }
}
```

- [ ] **Step 5: Wire the scene and the coordinator**

In `AppCoordinator.swift`, after `private(set) lazy var store = SessionStore(engine: engine)` add:

```swift
    /// The Settings window's model. Writes go to the same preferences the
    /// engine reads; `onChange` refreshes every surface that shows them.
    private(set) lazy var settings = SettingsModel(
        store: engine.store,
        isTrackingEnabled: engine.store.isUsageTrackingEnabled,
        onChange: { [weak self] in self?.store.refresh() },
        onTrackingChanged: { [weak self] in self?.store.setTrackingEnabled($0) })
```

In `FocusContinuityApp.swift`, inside `var body: some Scene`, after the `Window("Dashboard", ...)` block add:

```swift

        Settings {
            SettingsView(model: coordinator.settings)
        }
```

- [ ] **Step 6: Remove the settings from the store and the popover**

In `SessionStore.swift`:
- Replace the `dailyGoal` property (get/set) with nothing — delete it.
- Delete `autoSessionsEnabled`, `rewardsEnabled` (both get/set).
- Replace `var remindersEnabled: TimeInterval { get set }` with a getter only: `var remindersEnabled: Bool { engine.store.remindersEnabled }`.
- Delete `breakLength`.
- Replace `breakThreshold` and `longAwayCap` with getters only: `var breakThreshold: TimeInterval { engine.breakThreshold }` and `var longAwayCap: TimeInterval { engine.store.longAwayCap }`.
- Replace `menuSessionCount` with a getter only: `var menuSessionCount: Int { engine.store.menuSessionCount }`.
- Keep `setTrackingEnabled(_:)` and `isTrackingEnabled`.

In `PopoverView.swift`:
- Delete the `settingsAlwaysOpen` property and its doc comment.
- In `scrollingBody`, delete the trailing `Divider()` and `settingsRow` lines.
- Delete everything from `// MARK: - Settings` through the end of `settingsColumns`, `goalSettings`, `automaticSettings`, `awaySettings`, `breakSettings`, `displaySettings`, and the `// MARK: - Bindings` block; delete the private structs `SettingRow`, `AwayLadderNote`, `BreakTierNote`, `SettingGroup`.
- Replace `footer` with:

```swift
    private var footer: some View {
        HStack(spacing: Tokens.Space.s) {
            Label(store.breakLabel,
                  systemImage: store.isBreakDue ? "figure.walk" : "eye")
                .font(.caption)
                .foregroundStyle(store.isBreakDue ? AnyShapeStyle(.tint)
                                                  : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .explains("break", "Next break", breakDetail)
            Spacer(minLength: Tokens.Space.s)
            IconButton(systemImage: "rectangle.grid.2x2", help: "Open Dashboard",
                       action: onOpenDashboard)
            IconButton(systemImage: "gearshape", help: "Settings…") {
                SettingsModel.openWindow()
            }
            IconButton(systemImage: "power", help: "Quit FocusContinuity") {
                NSApp.terminate(nil)
            }
        }
    }
```

In `Snapshotter.swift`, remove `settingsAlwaysOpen: true,` from the `PopoverView(...)` call. In `GalleryView.swift` nothing references it.

- [ ] **Step 7: Build, test, relaunch, verify live**

Run build and selftest. Expected: `Build succeeded`, `82/82 passed`. If the build reports unused bindings or dead code left behind in `PopoverView.swift`, delete the lines it names.

Relaunch. Live checks: the popover footer shows the break label and three round buttons; the gear opens a Settings window with four tabs; ⌘, opens the same window; changing the daily goal moves the goal figure in the popover; toggling *Record app usage* off makes the popover's header read `At the Mac` unchanged but the timeline stop growing.

- [ ] **Step 8: Commit** *(recorded, skipped)*

```bash
git add Sources/App/SettingsModel.swift Sources/Surfaces/Settings/SettingsView.swift Sources/App/FocusContinuityApp.swift Sources/App/AppCoordinator.swift Sources/App/SessionStore.swift Sources/Surfaces/PopoverView.swift Sources/Surfaces/Snapshotter.swift Sources/SelfTest.swift
git commit -m "settings: standard Settings window; settings model; popover loses its form"
```

---

### Task 5: Popover hero card, footer file, and the folder split

**Files:**
- Move: `Sources/Surfaces/PopoverView.swift` → `Sources/Surfaces/Popover/PopoverView.swift`
- Create: `Sources/Surfaces/Popover/HeroCard.swift`
- Create: `Sources/Surfaces/Popover/PopoverFooter.swift`
- Move: `Sources/Surfaces/GoalBar.swift` → `_trash/GoalBar.swift`
- Modify: `Sources/Surfaces/Popover/PopoverView.swift`

**Interfaces:**
- Produces: `HeroCard(store: SessionStore, intentFocused: FocusState<Bool>.Binding, dense: Bool, twoColumn: Bool)`; `PopoverFooter(store: SessionStore, onOpenDashboard: @escaping () -> Void)`.
- Consumes: `GoalRing`, `IconButton`, `StartButton`, `ResolveCard`, `.card()`, `Tokens.Typography`.

- [ ] **Step 1: Move the files**

```bash
mkdir -p Sources/Surfaces/Popover
mv Sources/Surfaces/PopoverView.swift Sources/Surfaces/Popover/PopoverView.swift
mv Sources/Surfaces/GoalBar.swift _trash/GoalBar.swift
```

- [ ] **Step 2: Create `HeroCard.swift`**

```swift
import SwiftUI

/// The popover's hero: the goal ring beside the thing the user is doing — a
/// running timer, the start form, or the away question. One card, so the
/// figures that belong together sit together.
struct HeroCard: View {
    @ObservedObject var store: SessionStore
    var intentFocused: FocusState<Bool>.Binding
    var dense: Bool = false
    var twoColumn: Bool = true

    private var ringDiameter: CGFloat { dense ? 56 : 64 }

    var body: some View {
        HStack(alignment: .center, spacing: Tokens.Space.l) {
            GoalRing(progress: store.goal.share,
                     diameter: ringDiameter,
                     lineWidth: dense ? 6 : 7,
                     label: "\(Int((min(store.goal.share, 9.99) * 100).rounded()))%",
                     isMet: store.goal.isMet)
                .explains("goal", "Focus time towards today's goal", goalDetail)
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                if let away = store.pendingAway {
                    ResolveCard(away: away,
                                onMerge: { store.resolve(.mergeTime) },
                                onBreak: { store.resolve(.continueSession) },
                                onDiscard: { store.resolve(.resetTimer) },
                                onRest: { store.resolve(.tookBreak) })
                } else if store.isIdle {
                    idleBody
                } else {
                    runningBody
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .card(padding: dense ? Tokens.Space.m : Tokens.Space.l)
    }

    // MARK: - Idle

    private var idleBody: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Text("Ready when you are")
                .font(Tokens.Typography.title)
            IntentField(text: $store.intent) { store.start() }
                .focused(intentFocused)
                .frame(maxWidth: Tokens.formMeasure, alignment: .leading)
            HStack(spacing: Tokens.Space.s) {
                WorkTypePicker(selection: $store.workType)
                StartButton(fills: false) { store.start() }
            }
            goalCaption
        }
    }

    // MARK: - Running

    private var runningBody: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text(Tokens.clock(store.elapsed))
                .font(Tokens.Typography.heroTimer)
                .contentTransition(.numericText())
                .foregroundStyle(store.isPaused ? AnyShapeStyle(.secondary)
                                                : AnyShapeStyle(.primary))
                .accessibilityLabel("Elapsed \(Tokens.duration(store.elapsed))")
                .explains("timer", "This session, not today",
                          "Time since this focus session began — one stretch of work, "
                          + "not the day's total. It pauses itself after "
                          + "\(Int(FocusConstants.idlePauseThreshold / 60)) minutes without "
                          + "a keypress and asks what happened when you come back, so "
                          + "thinking time counts and lunch does not.")
            Text(store.isPaused ? "Paused · \(store.activeIntent)" : store.activeIntent)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            goalCaption
            HStack(spacing: Tokens.Space.s) {
                if store.isAway {
                    Button("I'm back") { store.endAway() }
                        .buttonStyle(.borderedProminent)
                    Button("Stop") { store.stop() }
                } else {
                    IconButton(systemImage: store.isPaused ? "play.fill" : "pause.fill",
                               help: store.isPaused ? "Resume" : "Pause") {
                        store.togglePause()
                    }
                    IconButton(systemImage: "door.right.hand.open",
                               help: "Away — stop the session and recording until you return") {
                        store.markAway()
                    }
                    Button("Stop") { store.stop() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                }
                if store.isAutoSession {
                    Button("Undo") { store.undoAutoSession() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .help("Discard this automatic session without recording it")
                }
            }
            .padding(.top, Tokens.Space.xs)
            if store.isAutoSession {
                Text("Started automatically")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: Tokens.Space.s) {
                    IntentField(text: $store.intent) { store.start() }
                        .focused(intentFocused)
                    WorkTypePicker(selection: $store.workType)
                    StartButton(title: store.startWouldContinue ? "Continue this" : "Start new",
                                fills: false) { store.start() }
                }
            }
        }
    }

    // MARK: - Goal caption

    /// `2h 31m of 4h · 1h 42m behind usual`. The ring shows the share; this
    /// names the figures, and the tooltip on the ring explains them.
    private var goalCaption: some View {
        HStack(spacing: Tokens.Space.xs) {
            Text(Tokens.duration(store.goal.achieved))
                .font(.caption.weight(.medium).monospacedDigit())
            Text("of \(Tokens.duration(store.goal.goal))")
                .font(.caption)
                .foregroundStyle(.secondary)
            if store.goal.isMet {
                Text("· Goal met")
                    .font(.caption)
                    .foregroundStyle(.tint)
            } else if let pace = paceNote {
                Text("· \(pace)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
    }

    private var paceNote: String? {
        guard let ahead = store.goal.aheadBy else { return nil }
        if ahead >= 60 { return "\(Tokens.duration(ahead)) ahead of usual" }
        if ahead <= -60 { return "\(Tokens.duration(-ahead)) behind usual" }
        return "on your usual pace"
    }

    private var goalDetail: String {
        let base = "The ring fills as your focus sessions add up towards the goal you "
            + "set, counting only the minutes you were actually using the Mac inside "
            + "a session. Pausing, going Away or sitting idle stops it. "
        guard let typical = store.goal.typicalByNow else {
            return base + "Once there are a couple of weeks of history, the caption "
                + "compares today with a normal day."
        }
        return base + "On a normal day you would have about "
            + "\(Tokens.duration(typical)) done by this hour, which is what the caption "
            + "compares you with. 'Normal' means the middle day out of your last "
            + "\(FocusConstants.goalMedianWindowDays) that had any focus on them."
    }
}
```

- [ ] **Step 3: Create `PopoverFooter.swift`**

```swift
import SwiftUI
import AppKit

/// Break countdown on the left; the three places to go on the right. Icons
/// with tooltips rather than words — the footer is reached for, not read.
struct PopoverFooter: View {
    @ObservedObject var store: SessionStore
    var onOpenDashboard: () -> Void

    var body: some View {
        HStack(spacing: Tokens.Space.s) {
            Label(store.breakLabel,
                  systemImage: store.isBreakDue ? "figure.walk" : "eye")
                .font(.caption)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(store.isBreakDue ? AnyShapeStyle(.tint)
                                                  : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .explains("break", "Next break", breakDetail)
            Spacer(minLength: Tokens.Space.s)
            IconButton(systemImage: "rectangle.grid.2x2", help: "Open Dashboard",
                       action: onOpenDashboard)
            IconButton(systemImage: "gearshape", help: "Settings…") {
                SettingsModel.openWindow()
            }
            IconButton(systemImage: "power", help: "Quit FocusContinuity") {
                NSApp.terminate(nil)
            }
        }
    }

    private var breakDetail: String {
        let base = "Counts unbroken use of the Mac, not focus sessions, so it runs "
            + "whether or not you pressed Start. When it reaches zero a panel appears "
            + "in the corner and a notification is posted; neither takes focus and "
            + "neither pauses anything.\n\nPause and Stop do not reset it — you are "
            + "still sitting at the screen. Away does, and so does actually stepping "
            + "away for a few minutes. "
        guard let tier = store.nextBreakTier else { return base + "Nothing is due." }
        return base + "Next: after \(Int(tier.workThreshold / 60)) minutes at the machine, "
            + "\(BreakPrompt.phrase(tier.breakLength)) away. \(tier.reason)"
    }
}
```

- [ ] **Step 4: Rewrite `PopoverView.swift` around them**

Replace the file's contents with:

```swift
import SwiftUI
import AppKit

/// The whole day at a glance, without opening the dashboard. A hero card, then
/// the glance cards, then a footer. Sized by `PopoverMetrics`; the middle
/// scrolls only on screens too short to hold it.
struct PopoverView: View {
    @ObservedObject var store: SessionStore
    @FocusState private var intentFocused: Bool
    @StateObject private var tips = TipCenter()
    /// Measured height of the scrolling middle. A `ScrollView` reports no
    /// intrinsic height, and this panel is sized to its content, so without
    /// measuring it collapsed to nothing.
    @StateObject private var middleHeight = HeightBox()
    var onOpenDashboard: () -> Void = {}

    /// Overridden by the snapshot harness so its output does not depend on the
    /// display the build machine happens to have attached.
    var metricsOverride: PopoverMetrics?

    private var metrics: PopoverMetrics {
        metricsOverride
            ?? PopoverMetrics.fitting(NSScreen.main?.visibleFrame.size
                                      ?? CGSize(width: 1_440, height: 900))
    }

    /// `ScrollView` has no intrinsic content under `ImageRenderer`, so the
    /// snapshot harness renders the panel unscrolled. Same views either way.
    var scrolls: Bool = true

    var body: some View {
        let metrics = self.metrics
        return VStack(alignment: .leading, spacing: metrics.stackSpacing) {
            header
            HeroCard(store: store, intentFocused: $intentFocused,
                     dense: metrics.dense, twoColumn: metrics.twoColumn)
            middle(cap: metrics.scrollCap, twoColumn: metrics.twoColumn)
            PopoverFooter(store: store, onOpenDashboard: onOpenDashboard)
        }
        .padding(metrics.outerPadding)
        .frame(width: metrics.width)
        .background(Tokens.Surface.ground)
        .background(.regularMaterial)
        .tipLayer(tips)
        .onAppear {
            store.refresh()
            intentFocused = store.isIdle
        }
    }

    @ViewBuilder private func middle(cap: CGFloat, twoColumn: Bool) -> some View {
        let content = GlanceCards(store: store, metrics: metrics)
            .frame(maxWidth: .infinity, alignment: .leading)

        if scrolls {
            ScrollView {
                content
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: ContentHeightKey.self,
                                               value: proxy.size.height)
                    })
            }
            .frame(height: min(max(middleHeight.value, 1), cap))
            .onPreferenceChange(ContentHeightKey.self) { middleHeight.value = $0 }
        } else {
            content
        }
    }

    /// At the Mac on the left, the streak on the right. The two day figures that
    /// are not the goal.
    private var header: some View {
        HStack(spacing: Tokens.Space.s) {
            Text("At the Mac today \(Tokens.duration(store.trackedToday))")
                .foregroundStyle(.secondary)
                .explains("atTheMac", "Hands on the keyboard today",
                          "Time you spent actually working the machine since midnight — "
                          + "typing, clicking, scrolling. It stops after "
                          + "\(Int(AppUsageTracker.idleCutoff / 60)) minutes without a "
                          + "keypress or a click, and picks up again the moment you touch "
                          + "it.\n\nThis is not the same as the focus time in the ring, and "
                          + "either one can be the larger. A session runs on the clock from "
                          + "Start to Stop; this number only counts the minutes your hands "
                          + "were busy.")
            Spacer()
            StreakBadge(days: store.streak)
                .explains("streak", "Days in a row",
                          "How many days running you have focused for at least "
                          + "\(Int(FocusConstants.streakMinimum / 60)) minutes. Today joins "
                          + "the count as soon as you pass that. Miss a day and it starts "
                          + "again from one.")
        }
        .font(.caption)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("At the Mac \(Tokens.spent(store.trackedToday)), "
                            + "\(store.streak) day streak")
    }
}
```

`GlanceCards` is created in Task 6; to keep this task building on its own, create `Sources/Surfaces/Popover/GlanceCards.swift` now with the *existing* sections wrapped, and Task 6 restyles it:

```swift
import SwiftUI

/// The scrolling middle of the popover: today's timeline, then top apps and
/// continue-today side by side when the panel is wide, stacked when narrow.
struct GlanceCards: View {
    @ObservedObject var store: SessionStore
    let metrics: PopoverMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.stackSpacing) {
            if store.isIdle && !store.quickStarts.isEmpty {
                QuickStartRow(items: store.quickStarts) { store.startQuick($0) }
            }
            timelineCard
            if metrics.twoColumn {
                HStack(alignment: .top, spacing: metrics.stackSpacing) {
                    topAppsCard.frame(maxWidth: .infinity, alignment: .topLeading)
                    continueCard.frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                topAppsCard
                continueCard
            }
        }
    }

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            SectionHeader(title: "Today")
            DayTimelineView(store: store, compact: true, layoutOverride: store.glanceLayout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: metrics.dense ? Tokens.Space.m : Tokens.Space.l)
        .explains("timeline", "Your day, left to right",
                  "Each coloured block is a stretch in one app, in the order it "
                  + "happened. Colours match the app list. Empty space is time away "
                  + "from the Mac. A wide block means a long unbroken stretch; lots of "
                  + "thin stripes means you were switching often.")
    }

    private var topAppsCard: some View {
        Group {
            if store.glanceApps.isEmpty {
                VStack(alignment: .leading, spacing: Tokens.Space.s) {
                    SectionHeader(title: "Top apps")
                    Text("Tracking starts when you switch apps.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                TopAppsList(apps: Array(store.glanceApps.prefix(metrics.topAppCount)),
                            sessionsToday: store.sessionsToday,
                            compact: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: metrics.dense ? Tokens.Space.m : Tokens.Space.l)
        .explains("topApps", "Where your time went",
                  "Each row is one app: how long it was the window in front today, and "
                  + "what share of your app time that was. Leaving an app and coming "
                  + "back adds to the same row. The share is out of your tracked app "
                  + "time, not out of the whole day.")
    }

    private var continueCard: some View {
        ContinueTodaySection(store: store, limit: store.menuSessionCount)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: metrics.dense ? Tokens.Space.m : Tokens.Space.l)
            .explains("continue", "Pick up where you left off",
                      "Work you were doing in the last few hours. Choosing one carries on "
                      + "with that same piece of work instead of beginning a new one, so "
                      + "an afternoon split by lunch still reads as one job.")
    }
}
```

The old `glanceLines` (`Now: … · +5 more` and the first insight) are gone: the hero and the cards carry the same facts, and the insight lives in the dashboard's Insights card.

- [ ] **Step 5: Build, test, snapshot, look**

Run build and selftest. Expected: `Build succeeded`, `82/82 passed`. If `LiveTimer` is now unused, leave it — the gallery does not reference it; if the compiler warns of an unused `twoColumn` parameter in `HeroCard`, keep it (it is read in Task 6's dense layout) by using it: in `HeroCard.body` change `spacing: Tokens.Space.l` to `spacing: twoColumn ? Tokens.Space.l : Tokens.Space.m`.

Run the snapshot command and open `running-dark.png`, `idleWithHistory-light.png`, `needsResolution-dark.png`. Expected: a hero card with a ring at left and the timer / start form / away card at right; the three cards below on a darker ground; the footer with three round buttons. Nothing stretched to fill width; no collapsed band.

Relaunch and open the popover on the 14" screen: confirm it fits with the away card up. If `.background(.regularMaterial)` shows no translucency, that is the opaque-window limit from the spec — leave it; the ground colour is the fallback.

- [ ] **Step 6: Commit** *(recorded, skipped)*

```bash
git add Sources/Surfaces/Popover _trash/GoalBar.swift
git commit -m "popover: hero card with goal ring, icon footer, folder split"
```

---

### Task 6: Glance cards restyle — rows, bars, swatches, timeline band

**Files:**
- Modify: `Sources/Surfaces/Dashboard/DashboardSections.swift` (`TopAppsList`, `EarlierTodayList`, `RunningNowList`, `InsightsList`)
- Modify: `Sources/Surfaces/ContinueTodaySection.swift`
- Modify: `Sources/Surfaces/Dashboard/DayTimelineView.swift` (band colours and gap wells)

**Interfaces:**
- `EarlierTodayList` gains `var title: String = "Earlier today"`.
- Row visuals: `AppSwatch` + `DataBar` everywhere a bar or icon was.

- [ ] **Step 1: `TopAppsList.row` uses the swatch and the bar**

In `DashboardSections.swift`, replace the body of `private func row(_ app: AppRank, rank: Int) -> some View` in `TopAppsList` with:

```swift
        HStack(spacing: compact ? Tokens.Space.s : Tokens.Space.m) {
            AppSwatch(rank: min(rank, 6), bundleID: app.bundleID, appName: app.appName,
                      size: compact ? 16 : 20)
            Text(app.appName)
                .font(compact ? .caption : Tokens.Typography.row)
                .lineLimit(1)
                .frame(width: compact ? 72 : 120, alignment: .leading)
            DataBar(share: app.share, tint: Tokens.Palette.app(rank: min(rank, 6)))
                .frame(minWidth: compact ? 48 : 80, idealWidth: 120, maxWidth: .infinity)
            Text(Tokens.preciseDuration(app.total))
                .font((compact ? Font.caption : Tokens.Typography.row).monospacedDigit())
                .frame(width: compact ? 50 : 66, alignment: .trailing)
            Text("\(Int((app.share * 100).rounded()))%")
                .font(Tokens.Typography.detail.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: compact ? 30 : 38, alignment: .trailing)
        }
        .padding(.vertical, Tokens.Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(app.appName), \(Tokens.spent(app.total)), "
                            + "\(Int((app.share * 100).rounded()))% of tracked time")
```

Also in `TopAppsList.body`, delete the `if !apps.isEmpty && !compact { Text("Share of tracked time. Colours match the timeline above.") ... }` block — the swatch is the legend now.

- [ ] **Step 2: `EarlierTodayList` takes a title; rows use the swatch**

Replace `struct EarlierTodayList` declaration lines through `var expandedApps: Set<String> = []` with:

```swift
struct EarlierTodayList: View {
    let apps: [AppDayHistory]
    var store: SessionStore?
    /// `Earlier today` on today, `Earlier that day` when the dashboard browses
    /// history. The section used to say "today" about yesterday.
    var title: String = "Earlier today"
    /// Passed as a VALUE, never read back through `store`; see `TopAppsList`.
    var expandedApps: Set<String> = []
```

and in its `body` change `SectionHeader(title: "Earlier today",` to `SectionHeader(title: title,`. In `row(_:)` replace `AppIcon(bundleID: app.bundleID, size: 16, appName: app.appName)` with `AppSwatch(rank: app.colorIndex, bundleID: app.bundleID, appName: app.appName, size: 16)`.

- [ ] **Step 3: `RunningNowList` and `InsightsList` typography**

In `RunningNowList`, change `Text(app.appName).font(.callout)` to `.font(Tokens.Typography.row)` and the launch-time line to `.font(Tokens.Typography.detail)`. In `InsightsList`, change `Image(systemName: insight.symbolName).foregroundStyle(.tint)` to add `.symbolRenderingMode(.hierarchical)`, the headline to `.font(Tokens.Typography.row)`, the detail to `.font(Tokens.Typography.detail)`.

- [ ] **Step 4: `ContinueTodaySection` rows**

In `ContinueTodaySection.swift`, in `ThreadRow.body`, replace `Button("Continue", action: onContinue).buttonStyle(.borderless).font(.caption)` with:

```swift
                    Button("Continue", action: onContinue)
                        .buttonStyle(.plain)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tint)
                        .padding(.horizontal, Tokens.Space.s)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .accessibilityLabel("Continue \(title)")
```

and the `.font(.callout.weight(.medium))` on the title to `.font(Tokens.Typography.row.weight(.medium))`.

- [ ] **Step 5: Timeline band — wells for gaps, palette for segments**

In `DayTimelineView.swift`, inside `band(_:)`'s `Canvas`:
- Replace `context.fill(Path(rect), with: .color(.secondary.opacity(0.08)))` and the whole hatch block (from `var hatch = Path()` through the closing `}` of `context.drawLayer { ... }`) with:

```swift
                    context.fill(Path(roundedRect: rect, cornerRadius: Tokens.Radius.swatch),
                                 with: .color(Tokens.Surface.well))
```

- Replace the segment fill `Path(roundedRect: rect, cornerRadius: 2)` (both occurrences) with `Path(roundedRect: rect, cornerRadius: Tokens.Radius.swatch)`, and `.opacity(isFocused ? 1 : 0.82)` with `.opacity(isFocused ? 1 : 0.92)`.
- Replace the hour-column stroke colour `.color(.secondary.opacity(0.18))` with `.color(Tokens.Surface.hairline)`.

- [ ] **Step 5b: Row hover (spec §7)**

`@State` is unavailable, so a hovered row needs an object. Add to `Sources/Design/Components/InfoTip.swift`, after `final class BoolBox`:

```swift
/// Which row the pointer is over, for lists that highlight on hover. One per
/// list; `@State` is unavailable on this toolchain.
final class HoverBox: ObservableObject {
    @Published var id: String?
}
```

In `TopAppsList`, add `@StateObject private var hover = HoverBox()` beside the other properties, and in `expandableRow(_:rank:)` append after `.contentShape(Rectangle())`:

```swift
        .background(hover.id == app.bundleID ? Tokens.Surface.hover : Color.clear,
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.control, style: .continuous))
        .onHover { hover.id = $0 ? app.bundleID : nil }
```

Do the same in `SessionLogList.appRow` (add `@StateObject private var hover = HoverBox()` to `SessionLogList`, and the two modifiers after the row's `.contentShape(Rectangle())` — there the key is `group.bundleID`). The gallery drives these views with no store; `@StateObject` with a default value needs none.

- [ ] **Step 6: Build, test, snapshot, look**

Run build and selftest. Expected: `Build succeeded`, `82/82 passed`. Snapshot; open `running-light.png` and `dashboard-running-dark.png`. Expected: rows show icon + palette dot, bars in the palette on a well; the timeline's gaps are flat wells with rounded corners and no hatching; `Continue` is a tinted pill. Live: hovering a Top apps row or a log row tints it.

- [ ] **Step 7: Commit** *(recorded, skipped)*

```bash
git add Sources/Surfaces/Dashboard/DashboardSections.swift Sources/Surfaces/ContinueTodaySection.swift Sources/Surfaces/Dashboard/DayTimelineView.swift Sources/Surfaces/Popover/GlanceCards.swift
git commit -m "design: rows, bars, swatches and the timeline band on the palette"
```

---

### Task 7: Dashboard title band and stat band; previous-period total

**Files:**
- Modify: `Sources/Core/PeriodStats.swift`
- Modify: `Sources/App/SessionStore.swift` (`trackedYesterday`, `previousPeriodTracked`, `statFigures`)
- Modify: `Sources/Surfaces/Dashboard/PeriodViews.swift` (`StatFigure`, `StatRow` → `StatBand`)
- Modify: `Sources/Surfaces/Dashboard/DashboardView.swift` (title band, stat band)
- Test: `Sources/SelfTest.swift`

**Interfaces:**
- Produces: `PeriodStats.previousPeriodTracked(for: TrackingPeriod, containing: Date) -> TimeInterval`; `StatFigure` gains `var tint: Color? = nil`; `StatBand(figures: [StatFigure], goal: GoalProgress?)`; `SessionStore.trackedYesterday: TimeInterval`, `SessionStore.previousPeriodTracked: TimeInterval`.

- [ ] **Step 1: Write the failing test**

Add before `    // MARK: - 60`:

```swift
    // MARK: - 83

    /// "vs last week" needs last week. The figure is the same rollup the chart
    /// uses, one period back, so it can never disagree with the bars.
    private static func testPreviousPeriodTracked() -> [String] {
        var problems: [String] = []
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = Clock(base)
        let calendar = Calendar.current
        let usage = AppUsageArchive(directory: directory, now: { clock.value })
        let stats = PeriodStats(sessions: SessionArchive(directory: directory,
                                                         now: { clock.value }),
                                usage: usage, now: { clock.value })

        let thisWeek = stats.bounds(for: .week, containing: clock.value)
        guard let lastWeekDay = calendar.date(byAdding: .day, value: -3, to: thisWeek.start),
              let twoWeeksDay = calendar.date(byAdding: .day, value: -10, to: thisWeek.start)
        else { return ["could not build the weeks"] }
        func record(_ day: Date, minutes: Double) {
            let start = calendar.startOfDay(for: day).addingTimeInterval(10 * 3_600)
            usage.record(AppUsageSession(bundleID: "com.a", appName: "Alpha",
                                         start: start,
                                         end: start.addingTimeInterval(minutes * 60)))
        }
        record(clock.value, minutes: 30)       // this week
        record(lastWeekDay, minutes: 45)       // last week
        record(twoWeeksDay, minutes: 70)       // the week before — must not count

        expectClose(stats.previousPeriodTracked(for: .week, containing: clock.value),
                    45 * 60, "last week's tracked total", &problems)
        expectClose(stats.previousPeriodTracked(for: .week, containing: lastWeekDay),
                    70 * 60, "and the week before that, one step back", &problems)
        expectClose(PeriodStats(sessions: SessionArchive(directory: scratchDirectory(),
                                                         now: { clock.value }),
                                usage: AppUsageArchive(directory: scratchDirectory(),
                                                       now: { clock.value }),
                                now: { clock.value })
                        .previousPeriodTracked(for: .month, containing: clock.value),
                    0, "nothing recorded reads as zero", &problems)
        return problems
    }
```

Register after `testSettingsModel`:

```swift
            ("Previous-period total is the same rollup one period back",
             testPreviousPeriodTracked)
```

- [ ] **Step 2: Run to verify it fails**

Run the build. Expected: `error: value of type 'PeriodStats' has no member 'previousPeriodTracked'`.

- [ ] **Step 3: Add it to `PeriodStats`**

In `Sources/Core/PeriodStats.swift`, after `func bounds(for:containing:)` add:

```swift
    /// Tracked total for the period before the one containing `day` — the
    /// baseline behind "vs last week". Walks the same day slices the chart
    /// does, so the comparison can never drift from the bars.
    func previousPeriodTracked(for period: TrackingPeriod, containing day: Date) -> TimeInterval {
        let (start, _) = bounds(for: period, containing: day)
        guard let previousDay = calendar.date(byAdding: .second, value: -1, to: start) else {
            return 0
        }
        let (previousStart, previousEnd) = bounds(for: period, containing: previousDay)
        let stats = DashboardStats(sessions: sessions, usage: usage,
                                   calendar: calendar, now: now)
        var total: TimeInterval = 0
        var cursor = previousStart
        var guardRail = 0
        while cursor < previousEnd && guardRail < 40 {
            guardRail += 1
            total += stats.trackedTotal(for: cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return total
    }
```

- [ ] **Step 4: Publish the two baselines and rebuild the figures in the store**

In `SessionStore.swift`, beside `@Published private(set) var trackedForSelectedDay` add:

```swift
    /// Baselines for the stat band's context lines: the day before the selected
    /// day, and the period before the selected period.
    @Published private(set) var trackedYesterday: TimeInterval = 0
    @Published private(set) var previousPeriodTracked: TimeInterval = 0
```

In `refreshDashboard()`, after `trackedForSelectedDay = stats.trackedTotal(for: day)` add:

```swift
        trackedYesterday = Calendar.current.date(byAdding: .day, value: -1, to: day)
            .map { stats.trackedTotal(for: $0) } ?? 0
```

and after `periodSummary = rollup.summary` add:

```swift
        previousPeriodTracked = PeriodStats(sessions: engine.archive, usage: usage)
            .previousPeriodTracked(for: period, containing: day)
```

Replace the whole `var statFigures: [StatFigure]` with:

```swift
    /// Figures for the stat band, shaped by the selected period. Every card
    /// carries a context line; a bare number was the old row's failure.
    var statFigures: [StatFigure] {
        switch period {
        case .day:
            let sessions = isToday ? sessionsToday : sessionsForSelectedDay
            let focused = isToday ? todayTotal : focusedForSelectedDay
            let longest = isToday ? longestToday : longestForSelectedDay
            let longestName = isToday ? longestNameToday : longestNameForSelectedDay
            let tracked = trackedForSelectedDay
            let delta = SessionStore.deltaLine(tracked, against: trackedYesterday,
                                               label: "yesterday")
            let insideShare = focusQuality.insideSessionShare
            let top = focusQuality.byWorkType.first
            return [
                StatFigure(label: "Tracked", value: Tokens.duration(tracked),
                           detail: delta?.text, tint: delta?.up == true ? Tokens.Palette.app(rank: 1) : nil),
                StatFigure(label: "Sessions", value: "\(sessions)",
                           detail: longest > 0
                               ? "longest \(Tokens.preciseDuration(longest))"
                                 + (longestName.map { " · \($0)" } ?? "")
                               : nil),
                StatFigure(label: "Focused", value: Tokens.duration(focused),
                           detail: tracked > 0 && focused > 0
                               ? "\(Int((insideShare * 100).rounded()))% of tracked" : nil),
                StatFigure(label: "Quality",
                           value: top.map {
                               "\($0.workType.displayName) \(Int(($0.share * 100).rounded()))%"
                           } ?? "—",
                           detail: focusQuality.sessionCount > 0
                               ? String(format: "%.1f switches / session",
                                        focusQuality.switchesPerSession)
                               : nil)
            ]
        case .week, .month:
            let delta = SessionStore.deltaLine(periodSummary.tracked,
                                               against: previousPeriodTracked,
                                               label: period == .week ? "last week" : "last month")
            return [
                StatFigure(label: "Tracked", value: Tokens.duration(periodSummary.tracked),
                           detail: delta?.text, tint: delta?.up == true ? Tokens.Palette.app(rank: 1) : nil),
                StatFigure(label: "Active days",
                           value: "\(periodSummary.activeDays) of \(periodSummary.totalDays)"),
                StatFigure(label: "Average / day",
                           value: Tokens.duration(periodSummary.averagePerActiveDay),
                           detail: "across active days"),
                StatFigure(label: "Longest stretch",
                           value: periodSummary.longest.map {
                               Tokens.preciseDuration($0.attended)
                           } ?? "—",
                           detail: periodSummary.longest?.appName)
            ]
        }
    }

    /// `+3h 5m vs yesterday`, or nil when there is no baseline — a delta
    /// against nothing is not information.
    static func deltaLine(_ value: TimeInterval, against baseline: TimeInterval,
                          label: String) -> (text: String, up: Bool)? {
        guard baseline > 0, value > 0 else { return nil }
        let delta = value - baseline
        guard abs(delta) >= 60 else { return ("same as \(label)", false) }
        return ((delta > 0 ? "+" : "−") + Tokens.duration(abs(delta)) + " vs \(label)",
                delta > 0)
    }
```

- [ ] **Step 5: The stat band view**

In `PeriodViews.swift`, replace `struct StatFigure` and `struct StatRow` with:

```swift
/// One headline figure with its context line and an optional tint for it.
struct StatFigure: Identifiable, Equatable {
    let label: String
    let value: String
    var detail: String?
    var tint: Color?
    var id: String { label }
}

/// The stat cards and, on the day view, the ring beside them.
struct StatBand: View {
    let figures: [StatFigure]
    var goal: GoalProgress?

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Space.s) {
            ForEach(figures) { figure in
                StatCard(label: figure.label, value: figure.value,
                         context: figure.detail, contextTint: figure.tint)
            }
            if let goal {
                VStack(spacing: Tokens.Space.xs) {
                    GoalRing(progress: goal.share, diameter: 56, lineWidth: 6,
                             label: Tokens.duration(goal.achieved), isMet: goal.isMet)
                    Text("of \(Tokens.duration(goal.goal))")
                        .font(Tokens.Typography.detail)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 96)
                .frame(maxHeight: .infinity)
                .card(padding: Tokens.Space.s)
                .accessibilityElement(children: .combine)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
```

- [ ] **Step 6: Title band and stat band in `DashboardView`**

In `DashboardView.swift`, replace `leftColumn` with:

```swift
    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.l) {
            titleBand
            if !store.isIdle { activeSession }
            StatBand(figures: store.statFigures,
                     goal: store.period == .day && store.isToday ? store.goal : nil)
            sessionLogSection
            periodChart
            FocusQualityBar(quality: store.focusQuality, dayScopeLabel: dayScopeLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
        }
        .padding(Tokens.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The day, the date, the streak and the goal in one line; the scope
    /// controls beside them because they govern everything beneath.
    private var titleBand: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.dayLabel)
                    .font(Tokens.Typography.title)
                Text(subtitle)
                    .font(Tokens.Typography.detail)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            periodControls
        }
    }

    private var subtitle: String {
        var parts = [Tokens.longDate(store.selectedDay)]
        if store.streak > 0 {
            parts.append(store.streak == 1 ? "1-day streak" : "\(store.streak)-day streak")
        }
        if store.isToday {
            parts.append(store.goal.isMet
                         ? "Goal met"
                         : "\(Tokens.duration(store.goal.achieved)) of "
                           + "\(Tokens.duration(store.goal.goal))")
        }
        return parts.joined(separator: " · ")
    }
```

Replace `activeSession` (the `@ViewBuilder private var activeSession`) with:

```swift
    /// The session in flight, as a slim card. Absent when idle — the popover
    /// owns starting.
    @ViewBuilder private var activeSession: some View {
        HStack(alignment: .center, spacing: Tokens.Space.l) {
            if let away = store.pendingAway {
                ResolveCard(away: away,
                            onMerge: { store.resolve(.mergeTime) },
                            onBreak: { store.resolve(.continueSession) },
                            onDiscard: { store.resolve(.resetTimer) },
                            onRest: { store.resolve(.tookBreak) })
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Tokens.clock(store.elapsed))
                        .font(Tokens.Typography.heroTimer)
                        .contentTransition(.numericText())
                        .foregroundStyle(store.isPaused ? AnyShapeStyle(.secondary)
                                                        : AnyShapeStyle(.primary))
                    Text(store.activeSessionSubtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: Tokens.Space.s) {
                    if store.isAway {
                        Button("I'm back") { store.endAway() }
                            .buttonStyle(.borderedProminent)
                        Button("Stop") { store.stop() }
                    } else {
                        IconButton(systemImage: store.isPaused ? "play.fill" : "pause.fill",
                                   help: store.isPaused ? "Resume" : "Pause") {
                            store.togglePause()
                        }
                        IconButton(systemImage: "door.right.hand.open",
                                   help: "Away — stop the session and recording until you return") {
                            store.markAway()
                        }
                        Button("Stop") { store.stop() }.buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
```

Delete the now-unused `dayScopeLabel`? No — it is still used by `FocusQualityBar`; keep it. Delete `SectionHeader(title: "Active session", ...)` usage (it was inside the old `activeSession`). Remove the `Divider()` lines between sections in `leftColumn` (already done by the replacement). In `periodControls`, change `Picker` `.frame(width: 210)` to `.frame(width: 220)` and keep the rest.

In `rightColumn`, replace `EarlierTodayList(apps: store.earlierToday, store: store, expandedApps: store.expandedApps)` with:

```swift
            EarlierTodayList(apps: store.earlierToday, store: store,
                             title: store.isToday ? "Earlier today" : "Earlier that day",
                             expandedApps: store.expandedApps)
```

- [ ] **Step 7: Build, test, snapshot, look**

Run build and selftest. Expected: `Build succeeded`, `83/83 passed`. Snapshot; open `dashboard-running-dark.png` and `period-week-idleWithHistory-light.png`. Expected: a title band (`Today` / date · streak · goal), the active-session card, a band of four cards with context lines and the ring card; week view's Tracked card reads `… vs last week` when there is a baseline. Nothing is cut off; the band does not wrap.

- [ ] **Step 8: Commit** *(recorded, skipped)*

```bash
git add Sources/Core/PeriodStats.swift Sources/App/SessionStore.swift Sources/Surfaces/Dashboard/PeriodViews.swift Sources/Surfaces/Dashboard/DashboardView.swift Sources/SelfTest.swift
git commit -m "dashboard: title band, stat band with context lines and ring, previous-period baseline"
```

---

### Task 8: Dashboard cards — log, timeline, chart, quality, right column; day-aware copy

**Files:**
- Modify: `Sources/Surfaces/Dashboard/DashboardView.swift` (cards, right column)
- Modify: `Sources/Surfaces/Dashboard/PeriodViews.swift` (`SessionLogList.appRow`, `PeriodChart`)
- Modify: `Sources/Core/DashboardStats.swift` (insight headline)
- Modify: `Sources/Surfaces/Dashboard/DashboardSections.swift` (`FocusQualityBar`)
- Test: `Sources/SelfTest.swift` (if test 28 pins the old headline)

- [ ] **Step 1: Insight copy**

In `DashboardStats.swift`, in `longestStretch(_:)`, change `headline: "Longest stretch in one app today"` to `headline: "Longest stretch in one app"`. Run `grep -n "Longest stretch in one app today" Sources/SelfTest.swift`; if it matches, change the expected string in that test to `"Longest stretch in one app"`.

- [ ] **Step 2: Cards in `DashboardView`**

Replace `sessionLogSection` with:

```swift
    private var sessionLogSection: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack {
                Picker("Grouping", selection: groupingBinding) {
                    ForEach(LogGrouping.allCases, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)
                Spacer()
            }
            SessionLogList(entries: store.periodLog,
                           dayTotals: store.periodDayTotals,
                           groups: store.periodAppGroups,
                           grouping: store.logGrouping,
                           store: store,
                           showsHourly: store.period == .day,
                           periodBounds: store.periodBounds,
                           expandedApps: store.expandedApps,
                           showsMinorApps: store.showsMinorApps)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
```

Replace `periodChart` with:

```swift
    @ViewBuilder private var periodChart: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            SectionHeader(title: store.period == .day ? "Timeline" : "By day")
            if store.period == .day {
                DayTimelineView(store: store)
            } else {
                PeriodChart(days: store.periodDays,
                            average: store.periodSummary.averagePerActiveDay)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
```

Replace `rightColumn` with:

```swift
    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            RunningNowList(apps: store.runningApps)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: Tokens.Space.m)
            if !store.earlierToday.isEmpty {
                EarlierTodayList(apps: store.earlierToday, store: store,
                                 title: store.isToday ? "Earlier today" : "Earlier that day",
                                 expandedApps: store.expandedApps)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: Tokens.Space.m)
            }
            if !store.insights.isEmpty {
                InsightsList(insights: store.insights)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: Tokens.Space.m)
            }
            Spacer(minLength: 0)
        }
        .padding(Tokens.Space.l)
    }
```

Change the outer `HStack` in `body`: `.background(.background)` → `.background(Tokens.Surface.ground)`, and the right column's `.frame(width: 260, alignment: .topLeading)` → `.frame(width: 280, alignment: .topLeading)`. Remove the `Divider()` between the columns.

- [ ] **Step 3: Log rows and the chart on the palette**

In `PeriodViews.swift`, in `SessionLogList.appRow`, replace:

```swift
                AppIcon(bundleID: group.bundleID, size: 18, appName: group.appName)
```
with
```swift
                AppSwatch(rank: min(rank, 6), bundleID: group.bundleID,
                          appName: group.appName, size: 18)
```
and replace the `GeometryReader { ... }.frame(minWidth: 80, idealWidth: 160, maxWidth: .infinity, minHeight: 20, maxHeight: 20)` bar block with:

```swift
                DataBar(share: group.share, tint: Tokens.Palette.app(rank: min(rank, 6)))
                    .frame(minWidth: 80, idealWidth: 160, maxWidth: .infinity)
```

In `SessionLogList.body`, delete the `Text("Share of tracked time. Colours match the timeline above.")` block. In `PeriodChart`, the legend already routes through `TimelinePalette.color(for:)` (now the palette); change `.cornerRadius(2)` on both `BarMark`s to `.cornerRadius(Tokens.Radius.bar)`.

- [ ] **Step 4: `FocusQualityBar` as a card body**

In `DashboardSections.swift`, `FocusQualityBar.body`: replace the `Text(quality.byWorkType.map { ... }.joined(separator: " · ")).font(.callout)` with a split bar plus the legend:

```swift
                GeometryReader { geometry in
                    HStack(spacing: 2) {
                        ForEach(quality.byWorkType) { share in
                            RoundedRectangle(cornerRadius: Tokens.Radius.bar)
                                .fill(Tokens.Palette.workType(share.workType))
                                .frame(width: max(4, geometry.size.width * share.share))
                        }
                    }
                }
                .frame(height: 8)
                HStack(spacing: Tokens.Space.m) {
                    ForEach(quality.byWorkType) { share in
                        HStack(spacing: Tokens.Space.xs) {
                            Circle().fill(Tokens.Palette.workType(share.workType))
                                .frame(width: 6, height: 6)
                            Text("\(share.workType.displayName) "
                                 + "\(Int((share.share * 100).rounded()))%")
                        }
                    }
                }
                .font(Tokens.Typography.detail)
```

- [ ] **Step 5: Build, test, snapshot, look**

Run build and selftest. Expected: `Build succeeded`, `83/83 passed`. Snapshot; open `dashboard-running-light.png`, `dashboard-idleWithHistory-dark.png`, `period-month-idleWithHistory-dark.png`. Expected: every section is a card on the ground; the right column is a stack of three cards; the log rows carry swatches and palette bars; the chart's bars use the work-type colours; `Earlier today` reads `Earlier that day` only when browsing (check by opening the dashboard live and stepping back a day).

Relaunch; open the dashboard on Today, Yesterday and Week; resize the window to 900×620 and confirm the stat band does not wrap or clip.

- [ ] **Step 6: Commit** *(recorded, skipped)*

```bash
git add Sources/Surfaces/Dashboard Sources/Core/DashboardStats.swift Sources/SelfTest.swift
git commit -m "dashboard: card sections, palette bars and chart, day-aware copy"
```

---

### Task 9: Harness, gallery, README, live verification

**Files:**
- Modify: `Sources/Surfaces/GalleryView.swift` (component strip)
- Modify: `Sources/Surfaces/Snapshotter.swift` (component strip render)
- Modify: `README.md` (file tree, design section)
- Test: `Sources/SelfTest.swift` (test 84: popover stays under the 13" budget with the ring)

- [ ] **Step 1: Write the failing test**

Add before `    // MARK: - 60`:

```swift
    // MARK: - 84

    /// The popover must still fit a 13" screen after the hero grew a ring and
    /// the glance became cards. Measured with the real view: render the
    /// densest fixture at the 13" metrics and check its height against the
    /// screen's share, the same way the harness does.
    private static func testPopoverStillFits13Inch() -> [String] {
        var problems: [String] = []
        let metrics = PopoverMetrics.fitting(CGSize(width: 1_440, height: 845))
        let height: CGFloat = MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .needsResolution)
            let view = PopoverView(store: store, metricsOverride: metrics, scrolls: false)
                .frame(width: metrics.width)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            return renderer.nsImage?.size.height ?? .infinity
        }
        expect(height <= metrics.maxHeight,
               "needs-resolution panel is \(Int(height))pt, budget \(Int(metrics.maxHeight))",
               &problems)
        return problems
    }
```

Register after `testPreviousPeriodTracked`:

```swift
            ("The popover still fits a 13\" screen with the away card up",
             testPopoverStillFits13Inch)
```

- [ ] **Step 2: Run the test**

Run build and selftest. Expected: `84/84 passed` — this pins the layout rather than changing it. If it fails, the number it prints is the overrun; reduce `HeroCard`'s ring to 56 in dense mode (already) and `GlanceCards`' card padding to `Tokens.Space.s` when `metrics.dense`, then rerun.

- [ ] **Step 3: Component strip in the gallery and the snapshots**

In `GalleryView.swift`, add after `struct GalleryView: View {` ... inside `body`'s `VStack`, before `ForEach(fixtures, ...)`:

```swift
                VStack(alignment: .leading, spacing: Tokens.Space.m) {
                    Text("Components").font(.headline)
                    ComponentStrip()
                }
                Divider()
```

and append to the file:

```swift
/// The vocabulary in one row, so a token change can be judged in isolation.
struct ComponentStrip: View {
    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Space.l) {
            GoalRing(progress: 0.63, label: "63%")
            GoalRing(progress: 1.0, isMet: true)
            StatCard(label: "Tracked", value: "5h 10m", context: "+3h 5m vs yesterday",
                     contextTint: Tokens.Palette.app(rank: 1))
                .frame(width: 150)
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                ForEach(0..<7, id: \.self) { rank in
                    HStack(spacing: Tokens.Space.s) {
                        AppSwatch(rank: rank, bundleID: nil, appName: "App \(rank)")
                        DataBar(share: 1 - Double(rank) / 8, tint: Tokens.Palette.app(rank: rank))
                            .frame(width: 120)
                    }
                }
            }
            HStack(spacing: Tokens.Space.s) {
                IconButton(systemImage: "pause.fill", help: "Pause") {}
                IconButton(systemImage: "gearshape", help: "Settings…") {}
                IconButton(systemImage: "power", help: "Quit", prominent: true) {}
            }
            StartButton(fills: false) {}
        }
        .padding(Tokens.Space.l)
        .background(Tokens.Surface.ground)
    }
}
```

In `Snapshotter.run`, after the `for fixture in Fixture.allCases {` loop's closing brace and before `print("\(wrote)/...`, add:

```swift
        for scheme in [ColorScheme.light, .dark] {
            let strip = ComponentStrip()
                .environment(\.colorScheme, scheme)
                .frame(width: 900)
            _ = render(strip, to: directory.appendingPathComponent(
                "components-\(scheme == .light ? "light" : "dark").png"))
        }
```

- [ ] **Step 4: README**

In `README.md`, update the `Sources/` tree: under `Design/` list `DesignTokens.swift  Surfaces, palette, type, radii, formatters`, `MenuBarGlyph.swift  Goal ring as a template image`, `Components/Cards.swift  Card, stat card, bar, swatch, icon button`, `Components/GoalRing.swift`; under `App/` add `SettingsModel.swift  Settings window bridge`; under `Surfaces/` replace `PopoverView.swift  Menu bar popover` with `Popover/PopoverView.swift, HeroCard.swift, GlanceCards.swift, PopoverFooter.swift  Menu bar popover`, add `Settings/SettingsView.swift  ⌘, window`, and remove `GoalBar.swift`. Add a short `### Design` paragraph under the architecture notes: three surfaces, one accent, seven-colour palette by rank, SF Rounded numerals, goal ring in three places, settings in a standard window.

- [ ] **Step 5: Build, test, snapshot, look at everything**

Run build and selftest. Expected: `Build succeeded`, `84/84 passed`. Snapshot; open `components-light.png` and `components-dark.png` and confirm the seven colours are distinct and harmonised in both; open every `*-dark.png` and `*-light.png` once and confirm no collapsed region, no clipping, no hatched gap left, no SF Mono numeral left.

Live verification, with screenshots saved to `docs/plans/2026-08-22-premium-design-screens/` (create the directory): popover at 14" light and dark, popover with the away card up, dashboard Today / Yesterday / Week, the Settings window on the *Away and breaks* tab, and the menu bar with a session running, paused, and idle. Confirm: the popover fits with the away card up; the menu-bar ring changes when the goal changes in Settings; `Earlier that day` appears on Yesterday.

- [ ] **Step 6: Commit** *(recorded, skipped)*

```bash
git add Sources/Surfaces/GalleryView.swift Sources/Surfaces/Snapshotter.swift README.md Sources/SelfTest.swift docs/plans/2026-08-22-premium-design-screens
git commit -m "design: component strip in the gallery and snapshots; README; live verification"
```

---

## Final checklist

- [x] `./build.sh` produces no warnings and no errors.
- [x] `--selftest` reports `84/84 passed`.
- [x] `--snapshot` writes every fixture plus `components-*.png`; each opened and checked (archived in `2026-08-22-premium-design-screens/`).
- [ ] Live: popover fits 13"/14" with the away card up; Settings opens from ⌘, and the gear; menu-bar ring reflects the goal; dashboard reads `Earlier that day` on Yesterday. *(Menu-bar ring and popover fit verified live; the Settings window and the Yesterday copy need a human — the harness cannot open them and `osascript` has no Accessibility grant.)*
- [ ] No file over 500 lines, except `SelfTest.swift`. *(`SessionStore` is now three files, all under 500. Still over, all in Core: `SessionEngine` 861 (its transition table and persistence share private state, so a split needs a design decision), `SessionState` 526, `DashboardStats` 509.)*
- [x] `Sources/Core` still imports only Foundation/CoreGraphics.
