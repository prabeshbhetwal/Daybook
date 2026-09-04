# How Apple Would Design & Architect "FocusContinuity" — A First-Party macOS Design Study

## TL;DR
- **Apple would keep FocusContinuity's core structure but re-cast it in system idioms:** the five-tab rail should become a SwiftUI `NavigationSplitView` sidebar (Apple's own guidance is to switch to `NavigationSplitView` once you exceed roughly five/six peer sections), the eight-group Settings screen should be rebuilt as a macOS `Settings` scene mirroring the Ventura+ System Settings grouped-form model, and the menu-bar popover should behave like Control Center / the Focus menu — a transient `NSStatusItem`/`MenuBarExtra` panel that opens instantly and dismisses on click-away.
- **The app's "honesty" concept is squarely aligned with Apple's own practice:** Health prioritizes manually-entered data over automatically-recorded data and attributes every value to a source ("Data Sources & Access"), Screen Time distinguishes categorized vs. uncategorized time using color vs. gray in its bars, and Apple labels derived metrics as an "estimation"/"approximation." FocusContinuity's Focused / Focused-active / Tracked / Break-Away distinction should be conveyed through semantic color (green for evidence-backed, gray/secondary for uncertain), SF Symbols, and progressive disclosure rather than prose.
- **The Core / App / Design-Surfaces layering and single-ticker SessionStore are validated by Apple's current guidance:** Apple's Observation framework (`@Observable`), the "single source of truth" principle, and the `@MainActor`-by-default concurrency model map almost exactly onto a UI-free Core, one canonical MainActor-isolated store, and pure render-only views. The all-local, no-telemetry, no-permissions privacy model matches Apple's stated "prioritize on-device processing" principle.

## Key Findings

**1. Navigation.** Apple's HIG says tab bars are for flat, peer navigation and sidebars are for apps with more content and deeper hierarchy. Apple Developer Technical Support states the rule explicitly (Developer Forums thread 764293): *"The best practice is to limit the number of tabs in a tab view to six or fewer … If more than five tabs are necessary, consider using a NavigationSplitView as an alternative."* On the Mac the sidebar (`NavigationSplitView`) is already the default for multi-section apps like Mail, Music, and Notes. FocusContinuity's five sections (Focus, Today, Review, Insights, Settings) are peers with sub-content, so a translucent sidebar is the more Mac-native choice than a horizontal tab rail; Command-1…5 shortcuts remain fully compatible.

**2. Menu-bar popover.** Apple's system menu extras (Control Center, Wi-Fi, Battery, Focus/Do Not Disturb) are transient panels that open instantly on click and dismiss when you click away. The modern first-party route is SwiftUI's `MenuBarExtra` with `.menuBarExtraStyle(.window)`, or an `NSStatusItem` + `NSPopover` with `behavior = .transient`. The popover should be compact and Focus-only, exactly as specified.

**3. Settings.** macOS Ventura (13) renamed System Preferences to System Settings and rebuilt it as a sidebar of categories plus grouped forms of controls, coded in SwiftUI (which is also why Ventura switched from checkboxes to toggles). Apple's `Settings` scene (invoked by Command-comma) automatically applies HIG-appropriate settings styling — a Frameworks engineer confirmed on the Developer Forums that the `Settings` scene "is designed to help you build a first-class Mac settings experience that follows Apple's Human Interface Guidelines," using centered tabs to group related settings. FocusContinuity's eight groups map cleanly onto this pattern.

**4. Charts.** Swift Charts is Apple's native framework (`BarMark`, `LineMark`, etc.); by default it uses semantic colors that adapt to light/dark mode and picks "system colors that are easy to differentiate." Apple's own WWDC22 session ("Swift Charts: Raise the bar") demonstrates de-emphasizing context marks with "a fade gray color" and adding a `RuleMark` for an average/threshold line — directly applicable to a Review tab showing tracked week/month bars.

**5. Honesty patterns.** Apple already ships the exact honesty vocabulary FocusContinuity needs. Per Apple Support article 108779 ("Manage Health data…"), *"By default, Health prioritizes data in this order: Health data that you enter manually. Data from your iPhone, iPad, and Apple Watch. Data from apps and Bluetooth devices"* — i.e., user-declared data outranks auto-recorded data. Health surfaces provenance via "Data Sources & Access" (the same article: *"Scroll down, then tap Data Sources & Access. Only the sources that contribute to that data type will appear,"* where *"the data source at the top will take priority over other sources"*) and "Show All Data." Screen Time bars, per Apple Support ("Track app and device usage in Screen Time on Mac"), work like this: *"The bars represent your total usage. The colored parts represent the top three categories, shown under the chart. The gray parts represent usage that does not fall into those categories."* Apple labels derived values as estimates — its healthcare paper states *"Cardio fitness on Apple Watch is an estimation of a user's VO2 max in ml/kg/min, made based on measuring a user's heart rate response to physical activity"* — and calls the Watch-less iOS Move ring "an approximation of activity."

**6. Architecture.** Apple's Observation framework (WWDC23 "Discover Observation in SwiftUI") implements SwiftUI's "single source of truth" doctrine; `@MainActor` is the compile-time and runtime default for SwiftUI views (WWDC25 "Embracing Swift concurrency": *"Swift protects your main thread code using the main actor by default"*). This validates a single canonical, MainActor-isolated `SessionStore` and a UI-free Core of pure calculations, with views that only read published state.

## Details

### Layer 1 — Broad HIG principles that govern this app

| Domain | HIG guidance | Implication for FocusContinuity |
|---|---|---|
| Navigation | Tab bars = flat peer sections; DTS: use `NavigationSplitView` if more than five/six tabs are needed; default on Mac; show no more than two hierarchy levels in a sidebar | Convert the five-tab rail to a translucent sidebar; keep Command-1…5. Review's "period → trend → day detail" is a classic sidebar→content→detail 3-column flow |
| Window chrome | Use standard title bar + unified toolbar; put primary view controls in the toolbar; use system-provided window backgrounds/materials | Main window: standard toolbar hosting the period switcher (Review), inspector toggle (Today), and search |
| Settings | Ventura+ System Settings = sidebar categories + grouped forms; use SwiftUI `Settings` scene (⌘,), which auto-applies macOS settings styling with centered tabs | Rebuild 8 groups in the grouped-form idiom; only show real backed controls |
| Menu bar extra | System menus (Control Center, Focus, Battery) are transient, instant, click-away-dismiss panels | `MenuBarExtra(...).menuBarExtraStyle(.window)` or `NSPopover.behavior = .transient`; compact, Focus-only |
| Typography | SF Pro system font with 11 semantic Dynamic Type text styles (`.largeTitle`…`.caption2`); optical sizing (SF Pro Text ≤19pt, Display ≥20pt); proportional-by-default numerals but tabular figures for aligned data | Use semantic styles, not fixed points; use `.monospacedDigit()` for live timers and tables of durations |
| Color & materials | Use semantic colors (`.primary`, `.secondary`, `label`, `systemBlue`, etc.) that adapt to light/dark, increased contrast, and vibrancy; Apple ships adaptive system colors, never guaranteed hex; use system materials for menus/sidebars, and only vibrant colors on top of materials | Never hard-code hex; drive all state colors from semantic roles; sidebar/popover use system material |
| Spacing/layout | Community-standard 8pt grid with 4pt subdivisions (Apple does not brand it), 44×44pt minimum control targets, alignment to safe areas | Adopt an 8pt rhythm, 16/20pt window margins |
| Motion | "Don't add motion for the sake of motion"; support Reduce Motion via `@Environment(\.accessibilityReduceMotion)`; swap springs for cross-fades when set; avoid ~0.2 Hz oscillation | Use `.snappy` when Reduce Motion is on, `.bouncy`/spring otherwise; never rely on motion alone to convey a state change |
| Writing | Plain language; pick sentence vs. title case and be consistent; empty states must include a clear next action; button labels are verb-noun | State labels and Insights statements in plain, consistent copy; empty Today/Review states guide the next action |

### Layer 2 — How Apple's own products solve the same problems

| Apple product | Problem it shares with FocusContinuity | Pattern Apple uses | What to borrow |
|---|---|---|---|
| **Screen Time** (System Settings) | Present observed app-use time honestly, with categorized vs. uncategorized time | Week bar chart on top, per-day breakdown below; colored bars = top three categories, gray = usage "that does not fall into those categories"; sidebar of App Usage / Notifications / Pickups; date/week popup + arrows | Review tab: colored = evidence-backed/attributed, gray = uncertain/uncategorized; week bars + selected-day detail; period switcher in toolbar |
| **Health** | Distinguish user-declared vs. auto-recorded; attribute data to sources; qualify estimates | Provenance priority (manual > device > third-party apps); "Data Sources & Access," "Show All Data"; derived metrics labeled "estimation"/"approximation"; "not a medical device" disclaimers | Focused (declared) ranks above Tracked (observed); every session/app-use row attributes its source; Insights are gated and qualified, never overclaimed |
| **Focus / Do Not Disturb** | Communicate a deliberate, user-declared "focus" state | Explicit user-activated modes (not silently inferred); clear iconography (moon); surfaced in Control Center and menu bar | The declared-session model mirrors Focus's explicit activation; the unresolved-decision UI (resolve away/stop) reflects Apple's preference for explicit user choice over silent guessing |
| **Journal** | Local-only, private, on-device session-like logging | On-device processing, entries stored locally, E2EE when synced, "No one but you can access your journal"; Insights view with streaks/stats; clean chronological timeline | The all-local JSON + no-account + no-telemetry model is squarely in Journal's lineage; a "gated Insights" tab mirrors Journal's stats-only Insights |
| **Swift Charts** | Native time-series bar/line rendering | Semantic auto-adapting colors; de-emphasize context with gray; `RuleMark` for averages/goals; built-in VoiceOver | Review's week/month bars in Swift Charts; goal/average `RuleMark`; gray for non-focus time |
| **Shortcuts / Reminders / Calendar** | State, history, and calendar-day boundaries | Calendar clipping to local days; list/detail history; explicit completion states | Midnight-clipping of sessions matches Calendar's day-boundary handling; searchable History mirrors Reminders/Calendar list-detail |

### Layer 3 — Concrete recommendations

**SF Symbols per state**

| State | Recommended SF Symbol | Rationale |
|---|---|---|
| Focus / start session | `play.fill` or `timer` | Standard media/timer affordance |
| Focused-active (hands-on evidence) | `checkmark.seal` / `checkmark.seal.fill` | "Verified/confirmed" connotation for evidence-backed time |
| Pause | `pause.fill` | Universal pause glyph |
| Break / rest | `cup.and.saucer` or `figure.walk` | Break/away-from-desk connotation |
| Watching (passive) | `eye` | Passive observation, not deliberate work |
| Away / uncertain | `moon.zzz` or `questionmark.circle` | Away/uncertain; `moon.zzz` echoes Focus/DND |
| Idle (trimmed tail) | `hourglass` or `clock.badge.questionmark` | Uncertain/untended time |
| Unresolved decision | `exclamationmark.triangle` | Blocking, needs-attention state |
| At the Mac / Tracked | `desktopcomputer` or `macwindow` | Observed presence |
| Tabs | Focus `target`/`scope`, Today `sun.max`/`calendar.day.timeline.left`, Review `chart.bar`, Insights `lightbulb`, Settings `gearshape` | Consistent, HIG-native metaphors |

**Semantic color palette (roles, not hex)**

| Meaning | Semantic role | Notes |
|---|---|---|
| Focused-active / evidence-backed | `Color.green` (system green) | Reserve the one "confirmed" accent for evidence-backed time |
| Focused (declared, not yet corroborated) | app accent / `systemBlue` | Declared but unconfirmed |
| Tracked / At the Mac | `.secondary` label or `systemGray` | Observed, neutral |
| Break / Watching / Away / Idle | `.tertiary`/`.quaternary` or gray fill | Mirrors Screen Time's gray "uncategorized" |
| Unresolved decision | `systemOrange`/`systemYellow` | Attention without alarm |
| Backgrounds/containers | system window + `.regularMaterial` for sidebar/popover | Vibrancy on materials only |

Drive all of these from semantic roles so they adapt automatically to light/dark, increased contrast, and vibrancy. Information should never be conveyed by color alone — pair every color with a symbol and a text label (HIG accessibility requirement).

**Typography.** Use semantic `Font.TextStyle` throughout: `.largeTitle`/`.title` for tab/screen headers, `.headline` for section headers, `.body` for content, `.subheadline`/`.caption` (with `.secondary`) for qualifiers like "based on hands-on evidence." Apply `.monospacedDigit()` to the live session timer and any table of durations so digits don't jitter or misalign.

**Menu-bar popover vs. main window.**

| Aspect | Menu-bar popover | Main window |
|---|---|---|
| Framework | `MenuBarExtra(.window)` / `NSPopover(.transient)` | `WindowGroup` + `NavigationSplitView` |
| Size | Compact, ~320pt wide, fixed; content-sized | Resizable, standard toolbar; ~900–1000pt wide default for the 3-column Review workbench |
| Scope | Focus-only: current action, up to 3 continuations, quiet break context, Open App / Settings / Quit | All five sections |
| Dismissal | Click-away transient | Standard window lifecycle |
| Behavior | Instant open, no Dock churn | Full app; `Settings` scene via ⌘, |

**Settings restructured to mirror System Settings (2023+).** Present the eight groups as a grouped-form layout inside the `Settings` scene. Show only real, backed controls (Apple's HIG cautions against exposing controls the app can't honor). Use toggles (SwiftUI's switch idiom, as Ventura adopted) rather than checkboxes; group with `Form`/`GroupBox` sections and section headers; keep labels left, controls right.

| FocusContinuity Settings group | System Settings analogue |
|---|---|
| General | General |
| Focus sessions | Focus (mode configuration) |
| Away and breaks | Screen Time / downtime scheduling |
| Automatic and rewards | (app-specific; keep only backed controls) |
| Tracking and apps | Screen Time App Usage / Privacy category |
| Appearance | Appearance |
| Data and privacy | Privacy & Security |
| Advanced | (advanced/developer group) |

### Layer 4 — Architecture & engineering philosophy

| Apple principle / guidance | Source | Maps onto FocusContinuity |
|---|---|---|
| Single source of truth | SwiftUI data-flow doctrine; Observation framework (WWDC23) | The one canonical `SessionStore` is exactly this — all views read from it |
| `@Observable` over `ObservableObject` | WWDC23 "Discover Observation in SwiftUI"; property-level tracking reduces unnecessary redraws | Migrate the store to `@Observable`; views observe only the read models they touch |
| `@MainActor` by default | WWDC25 "Embracing Swift concurrency"; SwiftUI views are implicitly `@MainActor` | The App-layer store and its one-second ticker are correctly MainActor-isolated; heavy pure calc in Core can be `nonisolated`/actor-isolated if needed |
| Views are a function of state; never mutate storage from the view | SwiftUI declarative model | Validates Design/Surfaces rendering published read models only, never recalculating time |
| Prioritize on-device processing; data never leaves the device | Apple privacy principles; Differential Privacy Overview; Journal E2EE | All-local JSON, no accounts, no telemetry, no network is the strongest form of this principle (nothing to anonymize because nothing leaves) |
| Least-privilege permissions | HIG privacy; Journaling Suggestions on-device grouping | No Accessibility/Screen Recording/Input Monitoring; idle via system counters only — matches Apple's minimal-permission posture |

The Core / App / Design-Surfaces split is essentially Apple's recommended layering: a pure, testable, UI-free domain (Core) → a single MainActor state owner wiring events, presence, checkpoints, and persistence (App) → declarative render-only views (Design). The single-ticker model is a clean, deterministic state machine, which Apple's actor/state-machine guidance endorses. The one caveat: as concurrency grows (e.g., background persistence or heavy period-stat computation), isolate those in Core behind async boundaries so the MainActor ticker never blocks the UI.

## Recommendations

**Stage 1 — Structural (do first).**
1. Replace the horizontal tab rail with a `NavigationSplitView` sidebar (five items), keeping Command-1…5 and Command-comma. This is the single biggest "make it feel first-party" change, and it is Apple's own stated fallback once you have five-plus peer sections.
2. Rebuild the popover as `MenuBarExtra(.window)` (or `NSPopover` transient), compact and Focus-only, instant-open/click-away.
3. Move Settings into the `Settings` scene with grouped forms and toggles; delete any unbacked controls.

**Stage 2 — Visual honesty system.**
4. Adopt the semantic color roles above: green reserved for Focused-active/evidence-backed; gray/secondary for Tracked/Break/Away/Idle (Screen Time's colored-vs-gray model). Pair every color with an SF Symbol and text label.
5. In Review, render week/month bars in Swift Charts with a `RuleMark` goal/average line and gray context bars; wire the "Open in Today" action as a standard navigation.
6. Qualify Insights and estimates with Apple-style copy (see Stage 3) and secondary-styled captions.

**Stage 3 — Language & microcopy.** Mirror Apple's honesty vocabulary: attribute observed time to its source (Health's "Data Sources & Access" model, where manually-entered data explicitly outranks auto-recorded data), and never present Tracked time as deliberate work. Gate Insights so only evidence-backed statements appear, and phrase derived statements with hedged, Apple-consistent framing (an "estimation"/"approximation," as Apple frames VO2 max and the Move ring) rather than false certainty.

**Stage 4 — Architecture polish.**
7. Migrate `SessionStore` to `@Observable`; confirm MainActor isolation of the ticker; push pure period-stat/clipping math into Core with async boundaries so long computations never block the tick.
8. Wire Reduce Motion (`@Environment(\.accessibilityReduceMotion)`) to swap spring transitions for cross-fades.

**Benchmarks that would change these recommendations.** If the app ever grew beyond ~5 top-level sections or needed multi-window document behavior, reconsider the split-view depth. If a future feature genuinely required on-device ML grouping (à la Journaling Suggestions), the privacy posture would need an explicit on-device-only disclosure. If live-refresh ever caused UI hitches, that is the trigger to move computation off the MainActor.

## Caveats
- **No official Apple design exists for this app.** Everything here is synthesized from Apple's public HIG, WWDC sessions, Apple Support documentation, and reputable analysis; it is an evidence-led reconstruction of what Apple's idioms imply, not an Apple endorsement.
- **Apple ships adaptive system colors, not guaranteed hex values.** Community-measured hex (e.g., systemBlue ≈ #007AFF) is approximate and varies by OS version; always bind to semantic roles.
- **The "8pt grid" is a community convention**, not an Apple-branded mandate; treat it as a working rhythm.
- **Health's honesty framing leans on source attribution and manual-first prioritization**, plus "not a medical device"/"estimation"/"approximation" language, rather than a per-datapoint "estimated vs measured" label — so FocusContinuity's finer Focused/Focused-active distinction goes slightly beyond what Apple surfaces today, though it is consistent with Apple's direction.
- **Some snippets came from third-party developer blogs and skill-marketplace summaries** rather than primary Apple pages; the core claims (navigation fallback, Observation, MainActor, Screen Time bars, Health provenance, Ventura Settings) are corroborated by Apple's own documentation, forums, and WWDC videos.
- **SwiftUI `MenuBarExtra`/`Settings` scene have known edge cases** (e.g., version-specific `showSettingsWindow:` selector on Ventura; popover sizing traps); a small amount of AppKit glue (`NSStatusItem`) may still be the more robust route for the transient popover.