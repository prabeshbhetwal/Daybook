# FocusContinuity Mole-Inspired Interface Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the vertically exhaustive dashboard with a Mole-inspired five-tab desktop interface while preserving FocusContinuity's canonical accounting, privacy boundary, compact menu-bar workflow and local build guarantees.

**Architecture:** Keep Core responsible for pure records and reporting, App responsible for navigation, persistence and published presentation data, Design responsible for tokens/primitives, and Surfaces responsible only for composition and interaction. A persistent `MainWindowModel` owns the five-tab route; each tab consumes the existing canonical `SessionStore` snapshot through a purpose-built surface. The compact popover shares Focus presentation primitives but never embeds the global tab system.

**Tech Stack:** Swift 5 language mode, Swift 6.4 compiler, SwiftUI, AppKit, Charts, CoreGraphics, IOKit, macOS 13+, direct `swiftc`, no packages or Xcode project.

**Spec:** `docs/superpowers/specs/2026-08-29-mole-inspired-interface-redesign-design.md`

## Global Constraints

- Preserve macOS 13 deployment, direct `swiftc`, Swift 5 language mode and warnings-as-errors builds.
- Preserve exactly one repeating timer; no package, service, telemetry, account, third-party font or new TCC permission.
- Preserve Core → App → Design/Surfaces ownership; Core remains free of SwiftUI and views never read raw archives or calculate accounting values.
- Preserve canonical Focused, At the Mac/Tracked, break, Watching, historical, legacy-accuracy and pending-overlay semantics from the stabilised branch.
- Never rewrite, smooth or reclassify historical records for presentation.
- Use dynamic light/dark tokens, SF Symbols/system fonts, Australian English and a practical 28 pt minimum hit area.
- Add no setting without a persisted field, explicit default and observable product effect.
- Generated app bundles, `.build`, snapshots and Finder metadata remain ignored by Git.
- Every production change is test-first; tests use suite-scoped defaults and temporary directories only.

## Execution Baseline

Execution starts in a new `codex/mole-interface-redesign` worktree created from `codex/focuscontinuity-stabilisation`. Bring the approved design specification and this plan from `main` into that branch before Task 1. Do not redesign on the older `main` source tree: the tab surfaces depend on the stabilised usage snapshot, focused-active history, period bars, integrity warnings, build harness and 139-test baseline.

---

### Task 1: Close the stabilisation release gate

**Files:**

- Modify: `build.sh`
- Modify: `scripts/test-build-concurrency.sh`

**Interfaces:**

- Consumes: `release_recovery_guard() -> Bool`-equivalent shell status and the guarded stale-recovery transaction.
- Produces: stale recovery stops before candidate, backup or local-app mutation when guard release cannot be proven.

- [ ] **Step 1: Add the release-boundary regression**

Extend the real concurrency harness so a wrapper replaces or corrupts the recovery guard owner immediately before `release_recovery_guard`. Assert that the build exits non-zero and preserves the stale candidate, backup, local app and guard evidence byte-for-byte:

```bash
test "${BUILD_STATUS}" -ne 0 \
  || fail "recovery continued after guard release failed"
test -e "${STALE_CANDIDATE}" -a -e "${STALE_BACKUP}" \
  || fail "failed guard release discarded recovery evidence"
test "$(shasum -a 256 "${RECOVERY_GUARD}/owner" | awk '{print $1}')" = "${GUARD_HASH}" \
  || fail "failed guard release rewrote foreign ownership evidence"
```

- [ ] **Step 2: Verify RED**

Run:

```bash
bash -n build.sh scripts/test-build-concurrency.sh
./scripts/test-build-concurrency.sh
```

Expected: the new boundary assertion fails because the caller ignores the non-zero release status and continues stale transaction recovery.

- [ ] **Step 3: Check the release result explicitly**

At the guarded stale-recovery boundary, replace the unchecked call with:

```bash
if ! release_recovery_guard; then
  echo "error: could not release the proven stale-recovery guard" >&2
  return 1
fi
```

Do not weaken any existing type, identity, symlink, signal, rollback or contender checks.

- [ ] **Step 4: Verify GREEN and commit**

Run the syntax check, full concurrency harness, `./build.sh --check`, `./build.sh --test`, deep codesign, diff check and status check. Commit:

```bash
git add build.sh scripts/test-build-concurrency.sh
git commit -m "build: fail closed on guard release"
```

### Task 2: Add persistent navigation and real interface preferences

**Files:**

- Create: `Sources/App/MainWindowModel.swift`
- Modify: `Sources/Core/PersistenceStore.swift`
- Modify: `Sources/App/SettingsModel.swift`
- Modify: `Sources/SelfTest.swift`

**Interfaces:**

- Produces:

```swift
enum AppTab: String, CaseIterable, Identifiable {
    case focus, today, review, insights, settings
    var id: String { rawValue }
    var title: String { get }
    var symbol: String { get }
    var commandNumber: Int { get }
    func moved(by delta: Int) -> AppTab
}

enum ReviewSection: String, CaseIterable { case week, month, history }
enum InsightRange: String, CaseIterable { case week, month }
enum SettingsSection: String, CaseIterable, Identifiable {
    case general, focus, away, automatic, tracking, appearance, data, advanced
}
enum InterfaceDensity: String, CaseIterable { case comfortable, compact }
enum AppearancePreference: String, CaseIterable { case system, light, dark }

@MainActor final class MainWindowModel: ObservableObject {
    @Published var selectedTab: AppTab
    @Published var reviewSection: ReviewSection = .week
    @Published var insightRange: InsightRange = .week
    @Published var settingsSection: SettingsSection = .general
    func select(_ tab: AppTab)
    func moveTab(by delta: Int)
}
```

- Adds persisted `defaultAppTab`, `interfaceDensity`, `appearancePreference` and `showsTimelineLabels`; no other speculative preference is introduced.
- `PersistenceStore` retains Core ownership by storing validated raw strings (`defaultAppTabRawValue`, `interfaceDensityRawValue`, `appearanceRawValue`) plus the Boolean. `SettingsModel` maps those values to the App enums; Core never imports or names an App navigation type.

- [ ] **Step 1: Write `testMainNavigationAndInterfacePreferences`**

Use suite-scoped defaults and assert:

```swift
expect(settings.defaultAppTab == .focus, "Focus is the default tab", &problems)
expect(AppTab.focus.moved(by: -1) == .settings, "left wraps", &problems)
expect(AppTab.settings.moved(by: 1) == .focus, "right wraps", &problems)
settings.defaultAppTab = .today
settings.interfaceDensity = .compact
settings.appearancePreference = .dark
settings.showsTimelineLabels = false
expect(reloadedSettings.defaultAppTab == .today, "default tab persists", &problems)
```

- [ ] **Step 2: Verify RED**

Run `./build.sh --check`. Expected: compilation/test failure because the navigation types and preferences do not exist.

- [ ] **Step 3: Implement the model and persistence**

Store raw values in `UserDefaults`; `SettingsModel` validates and maps invalid values to `.focus`, `.comfortable`, `.system` and `true`. `SettingsModel.write` continues to publish once per persisted mutation.

- [ ] **Step 4: Verify GREEN and commit**

Run `./build.sh --check`, then commit:

```bash
git add Sources/App/MainWindowModel.swift Sources/Core/PersistenceStore.swift \
        Sources/App/SettingsModel.swift Sources/SelfTest.swift
git commit -m "feat: add persistent main-window navigation"
```

### Task 3: Establish warm-precision tokens and reusable primitives

**Files:**

- Modify: `Sources/Design/DesignTokens.swift`
- Modify: `Sources/Design/Components/Cards.swift`
- Modify: `Sources/Design/Components/Components.swift`
- Create: `Sources/Design/Components/TabRail.swift`
- Create: `Sources/Design/Components/SurfacePrimitives.swift`
- Modify: `Sources/Surfaces/GalleryView.swift`
- Modify: `Sources/SelfTest.swift`

**Interfaces:**

- Produces `Tokens.Colour.ground/surface/elevated/line/hover/focus/progress/attention/danger`, the 4–48 spacing rhythm, 16/12/capsule radii, 46/26/17/28/13/14/12 typography roles and `InterfaceDensity.layout`.
- Produces reusable `TabRail`, `SurfacePanel`, `MetricLine`, `AppUsageRow`, `SectionHeader`, `EmptyState`, `IntegrityNotice` and `SettingsRow`.

- [ ] **Step 1: Add design-behaviour tests**

Add `testMoleDesignTokensAndDensity` with hand-derived relationships:

```swift
expect(InterfaceDensity.compact.layout.rowHeight >= 28,
       "compact targets remain practical", &problems)
expect(InterfaceDensity.compact.layout.rowHeight < InterfaceDensity.comfortable.layout.rowHeight,
       "compact density is observably denser", &problems)
expect(Tokens.Colour.resolved(.focus, dark: false).hex == 0x3478F6,
       "light focus token matches the approved signal", &problems)
expect(Tokens.Colour.resolved(.attention, dark: true).hex == 0xE3A34F,
       "dark attention token remains semantic amber", &problems)
```

- [ ] **Step 2: Verify RED**

Run `./build.sh --check`. Expected: the semantic token and density APIs are missing.

- [ ] **Step 3: Implement tokens and primitives**

Use dynamic `NSColor` providers. Keep app/work-type palettes stable. Add compatibility aliases only while later tasks migrate callers; record their removal in Task 11. `TabRail` uses `ViewThatFits`, icon+label wide pills, label-only compact pills, `.focusable()`, arrow movement and a 160–200 ms Reduce-Motion-aware selection transition.

- [ ] **Step 4: Extend the component gallery and verify**

Render both appearances with selected/unselected tabs, integrity notice, empty state, app row, metric line and both densities. Run `./build.sh --check` and snapshot the component strip.

- [ ] **Step 5: Commit**

```bash
git add Sources/Design Sources/Surfaces/GalleryView.swift Sources/SelfTest.swift
git commit -m "feat: add Mole-inspired design foundations"
```

### Task 4: Build the main-window shell, commands and routing

**Files:**

- Create: `Sources/Surfaces/Main/MainWindowView.swift`
- Create: `Sources/Surfaces/Main/MainWindowHeader.swift`
- Create: `Sources/Surfaces/Main/MainWindowCommands.swift`
- Modify: `Sources/App/FocusContinuityApp.swift`
- Modify: `Sources/App/AppCoordinator.swift`
- Modify: `Sources/App/SettingsModel.swift`
- Modify: `Sources/SelfTest.swift`

**Interfaces:**

- Main window consumes `SessionStore`, `SettingsModel`, `MainWindowModel`.
- `MainWindowModel.open(tab:)` and `openToday(date:)` provide popover/notification/day-bar deep links.
- `⌘1…⌘5` select global tabs; `⌘,` selects Settings in the main window. The separate form-only Settings scene is removed.

- [ ] **Step 1: Add `testMainWindowRoutesAndCommands`**

Assert pure routing without instantiating SwiftUI:

```swift
navigation.open(tab: .review)
expect(navigation.selectedTab == .review, "review route selects Review", &problems)
navigation.openToday(date: yesterday)
expect(navigation.selectedTab == .today && navigation.requestedDate == yesterday,
       "day links route into Today", &problems)
navigation.openSettings()
expect(navigation.selectedTab == .settings, "command-comma routes to Settings", &problems)
```

- [ ] **Step 2: Verify RED**

Run `./build.sh --check`. Expected: deep-link/command routing does not exist.

- [ ] **Step 3: Implement the three-band shell**

`MainWindowView` fixes title/status and centred tab rail above a tab canvas whose selected surface owns scrolling. Apply minimum content size 980×680 and default 1,160×780. The status is quiet and literal (`Focus active · 42m`, `Today · 2h 10m focused`). The shell consumes store figures; it performs no accounting.

- [ ] **Step 4: Wire application entry and commands**

Rename the window id to `main`, open on `defaultAppTab`, route `Open FocusContinuity` to Focus, and route Settings/`⌘,` into the Settings tab. Update preview-window construction to `MainWindowView`.

- [ ] **Step 5: Verify and commit**

Run `./build.sh --check`; render a shell snapshot in light/dark and wide/narrow widths; commit:

```bash
git add Sources/App Sources/Surfaces/Main Sources/SelfTest.swift
git commit -m "feat: add the five-tab main window shell"
```

### Task 5: Make Focus action-first and keep the popover compact

**Files:**

- Create: `Sources/Surfaces/Focus/FocusView.swift`
- Create: `Sources/Surfaces/Focus/FocusHero.swift`
- Create: `Sources/Surfaces/Focus/FocusContinuations.swift`
- Modify: `Sources/Surfaces/Popover/PopoverView.swift`
- Modify: `Sources/Surfaces/Popover/HeroCard.swift`
- Modify: `Sources/Surfaces/Popover/GlanceCards.swift`
- Modify: `Sources/Surfaces/Popover/PopoverFooter.swift`
- Modify: `Sources/Surfaces/ContinueTodaySection.swift`
- Modify: `Sources/SelfTest.swift`

**Interfaces:**

- Produces `FocusSurfaceMode` (`idle`, `running`, `paused`, `watching`, `awaitingDecision`) and `FocusContinuationSource.rows(threads:quickStarts:limit:)`.
- Focus desktop and popover share honest hero state/action semantics; only layout density differs.

- [ ] **Step 1: Add `testFocusSurfaceStateAndContinuationLimit`**

Assert each session state maps to one primary question/action, awaiting decision hides ordinary controls, and continuation output is capped at three with threads preferred over quick starts.

- [ ] **Step 2: Verify RED**

Run `./build.sh --check`. Expected: Focus presentation types are missing.

- [ ] **Step 3: Implement the Focus tab**

Idle shows intent, work type, one filled Start action and supporting goal pace. Running centres the 46 pt timer, intent/work type and Pause/Away/Stop; it does not show KPI tiles. Paused, Watching and awaiting-decision use the exact state/copy hierarchy from the specification. Below the hero show at most three continuation rows and one quiet break line.

- [ ] **Step 4: Reduce the popover to Focus essentials**

Keep hero, one primary action, concise goal/break status, at most three continuations, and text-labelled footer actions `Open FocusContinuity`, `Settings`, `Quit`. Remove Today/Review/Insights metric-card duplication. `Open FocusContinuity` routes `.focus`; Settings routes `.settings`.

- [ ] **Step 5: Verify and commit**

Run `./build.sh --check`; render first-run, running, paused, watching and awaiting-decision Focus/popover states in both appearances and narrow/wide metrics; commit:

```bash
git add Sources/Surfaces/Focus Sources/Surfaces/Popover \
        Sources/Surfaces/ContinueTodaySection.swift Sources/SelfTest.swift
git commit -m "feat: redesign Focus and the compact popover"
```

### Task 6: Recompose Today around the time ribbon

**Files:**

- Create: `Sources/Surfaces/Today/TodayView.swift`
- Create: `Sources/Surfaces/Today/TodayHeader.swift`
- Create: `Sources/Surfaces/Today/TodayInspector.swift`
- Create: `Sources/Surfaces/Today/TodayRecap.swift`
- Modify: `Sources/Surfaces/Dashboard/DayTimelineView.swift`
- Modify: `Sources/Surfaces/Dashboard/DayPickerCalendar.swift`
- Modify: `Sources/Surfaces/Dashboard/DashboardSessions.swift`
- Modify: `Sources/Surfaces/Dashboard/DashboardSections.swift`
- Modify: `Sources/SelfTest.swift`

**Interfaces:**

- Today consumes existing `selectedDay`, timeline, focus brackets, day sessions, ranked apps, focused-active goal, integrity note and selection APIs.
- Selecting an app/session opens a lightweight inspector below the ribbon; Escape clears selection without changing the day.

- [ ] **Step 1: Add `testTodaySurfaceScopeAndInspector`**

Use a past-day store and assert tab changes preserve `dayOffset`, explicit Today resets it, timeline selection populates inspector data, Escape/clear empties it, and a past-day subtitle uses canonical focused/session figures.

- [ ] **Step 2: Verify RED**

Run `./build.sh --check`. Expected: Today presentation/inspector APIs are absent.

- [ ] **Step 3: Implement Today composition**

Make the ribbon the dominant full-width visual. Put date stepper/calendar at right; expose `Today` reset only when historical. Follow with inspector, Sessions group, At the Mac app rows and compact Day recap. Keep named breaks/rest and Watching visually distinct and keep the accuracy warning above affected evidence.

- [ ] **Step 4: Verify and commit**

Run `./build.sh --check`; render empty Today, live Today, history, selected inspector and past-day qualification in light/dark; commit:

```bash
git add Sources/Surfaces/Today Sources/Surfaces/Dashboard/DayTimelineView.swift \
        Sources/Surfaces/Dashboard/DayPickerCalendar.swift \
        Sources/Surfaces/Dashboard/DashboardSessions.swift \
        Sources/Surfaces/Dashboard/DashboardSections.swift Sources/SelfTest.swift
git commit -m "feat: make Today evidence-led"
```

### Task 7: Build Review Week, Month and searchable History

**Files:**

- Create: `Sources/Core/HistoryStats.swift`
- Create: `Sources/App/SessionStore+Review.swift`
- Create: `Sources/Surfaces/Review/ReviewView.swift`
- Create: `Sources/Surfaces/Review/HistoryView.swift`
- Modify: `Sources/Surfaces/Dashboard/PeriodViews.swift`
- Modify: `Sources/App/SessionStore.swift`
- Modify: `Sources/SelfTest.swift`

**Interfaces:**

```swift
struct HistoryDay: Identifiable, Equatable {
    let date: Date
    let tracked: TimeInterval
    let focused: TimeInterval
    let sessions: Int
    let appBundleIDs: Set<String>
    let workTypes: Set<WorkType>
}

struct HistoryFilter: Equatable {
    var query = ""
    var appBundleID: String?
    var workType: WorkType?
    func apply(to days: [HistoryDay]) -> [HistoryDay]
}
```

- `SessionStore` publishes canonical `historyDays` built from authoritative usage plus archive records.
- Review bar selection calls `navigation.openToday(date:)`.

- [ ] **Step 1: Add `testReviewHistoryFiltersAndDayRouting`**

Assert Week/Month bars equal exact tracked totals, the average uses that series, History is reverse chronological, query/app/work-type filters intersect, and a selected bar routes the literal date into Today.

- [ ] **Step 2: Verify RED**

Run `./build.sh --check`. Expected: History data/filter APIs are missing.

- [ ] **Step 3: Implement Review**

Reuse `PeriodChartData.tracked`; keep work type separate. Add local Week/Month/History pills, period navigation, concise summary, grouped session log, top apps/work type and period integrity notice. History uses date range/calendar, compact day rows and optional app/work-type filters; it adds no export/edit/repair.

- [ ] **Step 4: Verify and commit**

Run `./build.sh --check`; render Week, Month, empty Review, legacy-qualified period and filtered History in both appearances; commit:

```bash
git add Sources/Core/HistoryStats.swift Sources/App/SessionStore+Review.swift \
        Sources/App/SessionStore.swift Sources/Surfaces/Review \
        Sources/Surfaces/Dashboard/PeriodViews.swift Sources/SelfTest.swift
git commit -m "feat: add period Review and History"
```

### Task 8: Add evidence-gated Insights

**Files:**

- Create: `Sources/App/SessionStore+Insights.swift`
- Create: `Sources/Surfaces/Insights/InsightsView.swift`
- Create: `Sources/Surfaces/Insights/InsightSection.swift`
- Modify: `Sources/App/SessionStore.swift`
- Modify: `Sources/SelfTest.swift`

**Interfaces:**

```swift
struct InsightSurface: Equatable {
    let range: InsightRange
    let pace: Insight?
    let rhythm: Insight?
    let quality: Insight?
    let continuity: Insight?
    var hasEvidence: Bool { get }
}
```

- App builds `InsightSurface` from existing `DailyGoal`, `Rhythm`, `FocusQuality`, streak and comparable-period facts. The view only renders present sections.

- [ ] **Step 1: Add `testInsightSurfaceRequiresEvidence`**

Assert first-run data produces no statements and the specified empty copy; three authoritative active days permit pace; Rhythm requires non-zero canonical hours; no missing value is rendered as zero; Week/Month selector appears only when both ranges have evidence.

- [ ] **Step 2: Verify RED**

Run `./build.sh --check`. Expected: `InsightSurface` is missing.

- [ ] **Step 3: Implement Insights**

Render at most Pace, Rhythm, Focus quality and Continuity groups, each naming its measure and offering concise calculation detail. Reuse chart/list primitives; do not invent a score, prediction, comparison or encouragement feed.

- [ ] **Step 4: Verify and commit**

Run `./build.sh --check`; render evidence-rich and insufficient-data Insights in both appearances; commit:

```bash
git add Sources/App/SessionStore+Insights.swift Sources/App/SessionStore.swift \
        Sources/Surfaces/Insights Sources/SelfTest.swift
git commit -m "feat: add evidence-gated Insights"
```

### Task 9: Move all real behaviour into the Settings tab

**Files:**

- Rewrite: `Sources/Surfaces/Settings/SettingsView.swift`
- Create: `Sources/Surfaces/Settings/SettingsSidebar.swift`
- Create: `Sources/Surfaces/Settings/SettingsGroups.swift`
- Modify: `Sources/App/SettingsModel.swift`
- Modify: `Sources/App/FocusContinuityApp.swift`
- Modify: `Sources/SelfTest.swift`

**Interfaces:**

- `SettingsSection` exposes `title`, `symbol` and actual searchable control labels.
- SettingsModel exposes persisted defaults from Task 2 and existing daily goal, away thresholds, full prompt, reminders, automatic sessions, automatic gap, rewards, sessions-per-app, usage recording and data-folder reveal.
- Appearance preference applies to main window and popover; density changes shell/panel metrics; timeline-label preference changes the ribbon.

- [ ] **Step 1: Add `testSettingsGroupsContainOnlyBackedControls`**

Assert all eight groups exist, search `"goal"` returns Focus sessions, search `"privacy"` returns Data and privacy, persisted appearance/density/default-tab/timeline choices survive reload, and every listed mutable control key maps to a `SettingsModel` property.

- [ ] **Step 2: Verify RED**

Run `./build.sh --check`. Expected: group/search metadata and new observable effects are missing.

- [ ] **Step 3: Implement the responsive two-pane Settings surface**

Use sidebar at comfortable width and pill/menu group selector when narrow. Keep explanations and controls from the existing Settings form. General contains default tab; Appearance contains appearance, density and timeline labels; Data contains privacy, accuracy epoch, legacy backup location and reveal action; Advanced contains read-only version/build/recovery diagnostics. Add no unsupported launch, retention, exclusion, editing or destructive control.

- [ ] **Step 4: Apply appearance and density**

Pass `SettingsModel` into main window and popover. Apply `.preferredColorScheme` for light/dark/system, environment density for layout, and the timeline-label boolean at its actual labels. Respect system Reduce Motion without an override setting.

- [ ] **Step 5: Verify and commit**

Run `./build.sh --check`; render every Settings group, filtered search, both densities and appearances at wide/narrow widths; commit:

```bash
git add Sources/Surfaces/Settings Sources/App/SettingsModel.swift \
        Sources/App/FocusContinuityApp.swift Sources/SelfTest.swift
git commit -m "feat: make Settings a first-class tab"
```

### Task 10: Complete accessibility, keyboard and responsive behaviour

**Files:**

- Modify: `Sources/Design/Components/TabRail.swift`
- Modify: `Sources/Surfaces/Main/MainWindowView.swift`
- Modify: `Sources/Surfaces/Today/TodayView.swift`
- Modify: `Sources/Surfaces/Review/ReviewView.swift`
- Modify: `Sources/Surfaces/Review/HistoryView.swift`
- Modify: `Sources/Surfaces/Insights/InsightsView.swift`
- Modify: `Sources/Surfaces/Settings/SettingsView.swift`
- Modify: `Sources/Surfaces/Dashboard/DayTimelineView.swift`
- Modify: `Sources/Surfaces/Dashboard/PeriodViews.swift`
- Modify: `Sources/Surfaces/AwayPrompt/AwayFullPrompt.swift`
- Modify: `Sources/Surfaces/AwayPrompt/AwayQuickPanel.swift`
- Modify: `Sources/Design/Components/AwayAnswers.swift`
- Modify: `Sources/Surfaces/RewardHUD.swift`
- Modify: `Sources/SelfTest.swift`

**Interfaces:**

- Every tab/period/date announces selection; chart summaries expose literal values; Escape clears Today selection; left/right changes focused tab; `⌘1…⌘5` and `⌘,` remain standard commands.

- [ ] **Step 1: Add `testAccessibleNavigationAndChartSummaries`**

Assert tab accessibility labels include selected state, period points produce `"Saturday 29 August, 5 hours 10 minutes tracked"`, command digits map uniquely, compact controls remain at least 28 pt, and Escape clears Today selection without changing the selected day.

- [ ] **Step 2: Verify RED**

Run `./build.sh --check`. Expected: accessible summary APIs and Escape contract are missing.

- [ ] **Step 3: Implement accessibility and responsiveness**

Add VoiceOver labels/selected traits, equivalent chart list summaries, colour-independent legends, focus order, 28 pt targets, narrow group selectors, `ViewThatFits` tab labels and Reduce-Motion-aware transitions. Preserve existing timeline hover/click/Escape interaction. Migrate quick/full away prompts and the non-activating reward HUD to the semantic focus/progress/attention tokens without changing their decisions, timing or activation policy.

- [ ] **Step 4: Verify and commit**

Run `./build.sh --check`; render 980×680 minimum, 1,160×780 comfortable and narrow popover in both appearances; commit:

```bash
git add Sources/Design/Components/TabRail.swift Sources/Surfaces/Main \
        Sources/Surfaces/Today Sources/Surfaces/Review Sources/Surfaces/Insights \
        Sources/Surfaces/Settings Sources/Surfaces/Dashboard/DayTimelineView.swift \
        Sources/Surfaces/Dashboard/PeriodViews.swift Sources/Surfaces/AwayPrompt \
        Sources/Surfaces/RewardHUD.swift Sources/Design/Components/AwayAnswers.swift \
        Sources/SelfTest.swift
git commit -m "feat: complete accessible desktop interaction"
```

### Task 11: Replace the gallery matrix and remove dashboard drift

**Files:**

- Modify: `Sources/Surfaces/Snapshotter.swift`
- Modify: `Sources/Surfaces/GalleryView.swift`
- Delete when unreferenced: `Sources/Surfaces/Dashboard/DashboardView.swift`
- Delete when unreferenced: `Sources/Surfaces/Dashboard/DashboardHero.swift`
- Delete when unreferenced: `Sources/Surfaces/Dashboard/DashboardSummary.swift`
- Delete when unreferenced: `Sources/Surfaces/Popover/GlanceCards.swift`
- Modify: `Sources/Design/DesignTokens.swift`
- Modify: `README.md`
- Modify: `Sources/SelfTest.swift`

**Interfaces:**

```swift
enum SnapshotScenario: String, CaseIterable {
    case focusFirstRun, focusRunning, focusPaused, focusAwaitingDecision
    case todayHistory, todayPast
    case reviewWeek, reviewMonth
    case insightsEnough, insightsEmpty
    case settingsGeneral, settingsFocus, settingsAway, settingsAutomatic
    case settingsTracking, settingsAppearance, settingsData, settingsAdvanced
    case awayQuick, awayFull, rewardEarned
}
```

- [ ] **Step 1: Add `testSnapshotMatrixCoversEveryMaterialSurface`**

Assert all required scenarios exist, settings cases equal `SettingsSection.allCases`, each scenario renders light/dark, and wide/narrow variants exist for shell, Settings and Focus where the specification requires them.

- [ ] **Step 2: Verify RED**

Run `./build.sh --check`. Expected: the existing fixture-centric matrix lacks global tabs, Insights and settings-group scenarios.

- [ ] **Step 3: Rewrite gallery/snapshot routing and remove old roots**

Render only the new main shell/tab surfaces and compact popover/away prompts. Delete unused exhaustive-dashboard roots after `rg` proves no consumer. Remove temporary compatibility token aliases once all callers use semantic tokens. Update README architecture, navigation, settings and snapshot instructions without a hard-coded test count.

- [ ] **Step 4: Run final verification**

```bash
bash -n build.sh scripts/test-build-concurrency.sh
./scripts/test-build-concurrency.sh
./build.sh --check
./build.sh --test
codesign --verify --deep FocusContinuity.app
git diff --check
git status --short --untracked-files=all
```

Render snapshots to a temporary directory. Inspect every `SnapshotScenario` in light/dark plus minimum/comfortable widths. Confirm tab hierarchy, clipping, focus visibility, contrast, empty/integrity states and unchanged literal semantic figures.

- [ ] **Step 5: Commit**

```bash
git add -A Sources/Surfaces Sources/Design README.md Sources/SelfTest.swift
git commit -m "test: verify the Mole-inspired interface"
```

## Acceptance Criteria

- The main window presents Focus, Today, Review, Insights and Settings in one persistent centred tab rail with working keyboard commands.
- Each tab has one dominant purpose and visual; the exhaustive dashboard/card grid is no longer a product surface.
- The Focus popover remains compact and action-first, with no embedded Today/Review/Insights dashboard.
- Today preserves canonical day/ribbon/session/app/goal/integrity semantics and historical browsing.
- Review bars and averages use the same exact tracked series; History is searchable and routes into Today.
- Insights renders only evidence-backed pace, rhythm, quality and continuity statements.
- Every visible setting has persisted backing and an observable effect; no unsupported control appears.
- Warm-precision tokens, system typography, spacing, hit areas, Reduce Motion and VoiceOver behaviour match the specification in light/dark and wide/narrow layouts.
- The build-release residual is closed before interface work begins.
- Full headless, concurrency, staged/promoted signing and visual verification pass with a clean repository state.
