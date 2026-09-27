# Native Continuity Refinement Implementation Plan

**Goal:** Make FocusContinuity’s desktop navigation, Today inspection, calendar feedback, Review history, and Settings behave as one calm native macOS interface without changing canonical time data.

**Architecture:** Keep Core accounting and persistence untouched. Add small pure presentation contracts in the Design/Surfaces boundary, retain `SessionStore` as the single owner of Today inspection state, and turn Settings from a selected-pane switcher into one scrollable document with a synchronised index. All views continue consuming existing canonical read models.

**Tech Stack:** Swift 5 language mode, Swift 6.4 compiler, SwiftUI, AppKit, macOS 13+, direct `swiftc`, no packages or Xcode project.

**Spec:** `docs/specs/2026-08-30-native-continuity-refinement-design.md`

## Global Constraints

- Preserve macOS 13 deployment, direct `swiftc` builds, and the existing Core → App → Design/Surfaces boundary.
- Add no package, network service, account, telemetry surface, or TCC permission.
- Do not change canonical time accounting, historical clipping, persistence formats, accuracy epochs, or privacy language.
- Use Australian English in UI copy and documentation.
- Preserve the 980-point minimum window and native traffic-light clearance.
- Keep existing `⌘1`–`⌘5`, arrow-key tab navigation, Escape semantics, reduced-motion support, and 28-point practical target sizes unless this plan deliberately replaces a control.
- All tests use the suite-scoped defaults and temporary directories already provided by `SelfTest`.
- Do not push or modify remote state. Generated application bundles remain ignored by Git.
- Run `./build.sh --check` before every commit. Run `./build.sh --test` only after a task is accepted and visual inspection needs a promoted local bundle.

---

## File structure and ownership

| File | Responsibility after this plan |
|---|---|
| `Sources/Design/Components/TabRail.swift` | Independent global-tab visual states; no outer rail surface. |
| `Sources/Surfaces/Main/MainWindowHeader.swift` | Header layout and deterministic FocusContinuity app mark. |
| `Sources/Surfaces/Today/TodayView.swift` | Day reading order and inspector placement by source. |
| `Sources/Surfaces/Today/TodayRecap.swift` | Top recap band and complete-row narrative disclosure. |
| `Sources/Surfaces/Today/TodayInspector.swift` | `TodayInspectorOrigin` contract and source-aware selection state. |
| `Sources/App/SessionStore.swift` | Published ephemeral Today inspector origin alongside existing selected session/segment state. |
| `Sources/Surfaces/Dashboard/DashboardSessions.swift` | Session row selected-detail insertion point; stretch disclosure remains independent. |
| `Sources/Surfaces/Dashboard/DashboardSections.swift` | App row selected-detail insertion point. |
| `Sources/Surfaces/Dashboard/DayPickerCalendar.swift` | Pure day-goal presentation state, matching cells and legend. |
| `Sources/Surfaces/Review/ReviewView.swift` | Review copy and period-detail construction without an outward Today action. |
| `Sources/Surfaces/Review/HistoryView.swift` | History detail construction without an outward Today action. |
| `Sources/Surfaces/Review/ReviewDayDetail.swift` | Review-only evidence panel and close behaviour. |
| `Sources/Surfaces/Settings/SettingsScrollPresentation.swift` | New pure heading-anchor and active-index algorithm. |
| `Sources/Surfaces/Settings/SettingsView.swift` | Continuous settings document, scroll reader, search results, wide/narrow composition. |
| `Sources/Surfaces/Settings/SettingsSidebar.swift` | Index/sidebar and compact jump menu, not pane switching. |
| `Sources/SelfTest.swift` | Behavioural, accessibility-contract, and presentation-state regression tests. |
| `Sources/Surfaces/Snapshotter.swift` | Scenarios for every new visible state. |
| `docs/specs/2026-08-30-premium-interface-design-system.md` | Amend clauses that conflict with the approved refinement. |

## Task 1: Simplify global chrome and restore product identity

**Files:**
- Modify: `Sources/Design/Components/TabRail.swift:17-113`
- Modify: `Sources/Surfaces/Main/MainWindowHeader.swift:5-87`
- Modify: `Sources/SelfTest.swift`
- Modify: `Sources/Surfaces/Snapshotter.swift`

**Consumes:** `AppTab`, `Tokens`, `AccessibilityMetrics`, `MainWindowChrome.trafficLightClearance`.

**Produces:**

```swift
enum TabRailPresentation {
    static let usesOuterSurface = false
    static let unselectedUsesBorder = false
}

enum MainWindowChrome {
    static let appMarkFallbackSymbol = "target"
    static let appMarkSize: CGFloat = 24
}
```

- [ ] **Step 1: Write the failing chrome-presentation test**

  In `SelfTest.run()`, register `testNativeChromePresentation` after the existing unified-window-chrome test. Add the test:

  ```swift
  private static func testNativeChromePresentation() -> [String] {
      var problems: [String] = []
      expect(!TabRailPresentation.usesOuterSurface,
             "global tabs do not sit inside a second enclosing rail", &problems)
      expect(!TabRailPresentation.unselectedUsesBorder,
             "unselected tabs remain quiet individual controls", &problems)
      expect(MainWindowChrome.appMarkFallbackSymbol == "target"
                 && MainWindowChrome.appMarkSize == 24,
             "window chrome has a compact deterministic app-mark fallback", &problems)
      expect(MainWindowChrome.trafficLightClearance >= 68,
             "adding the app mark preserves traffic-light clearance", &problems)
      return problems
  }
  ```

- [ ] **Step 2: Run the test to verify the intended red state**

  Run: `./build.sh --check`

  Expected: compilation fails because `TabRailPresentation` and the app-mark constants do not exist.

- [ ] **Step 3: Add the pure presentation contract**

  At the top of `TabRail.swift`, after `AccessibilityMetrics`, add:

  ```swift
  enum TabRailPresentation {
      static let usesOuterSurface = false
      static let unselectedUsesBorder = false
  }
  ```

  In `MainWindowChrome`, add:

  ```swift
  static let appMarkFallbackSymbol = "target"
  static let appMarkSize: CGFloat = 24
  ```

- [ ] **Step 4: Remove the outer tab rail treatment**

  In `TabRail.body`, delete the rail-level `.padding`, capsule background, and
  capsule overlay. Retain the keyboard handlers and accessibility container.
  In `tabPill`, condition the unselected overlay through
  `TabRailPresentation.unselectedUsesBorder`; with the contract set to `false`,
  no unselected pill draws a border. Keep selected focus-blue fill, label,
  icon fallback, hit target, content shape, and hover/focus styling.

- [ ] **Step 5: Add the compact app mark**

  Import AppKit and create a private `FocusContinuityMark` view in
  `MainWindowHeader.swift`:

  ```swift
  private struct FocusContinuityMark: View {
      private var icon: NSImage? {
          Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
              .flatMap(NSImage.init(contentsOf:))
      }

      var body: some View {
          Group {
              if let icon {
                  Image(nsImage: icon).resizable().interpolation(.high)
              } else {
                  Image(systemName: MainWindowChrome.appMarkFallbackSymbol)
                      .font(.system(size: 13, weight: .semibold))
                      .foregroundStyle(Tokens.Colour.focus)
                      .background(Tokens.Colour.focus.opacity(0.12), in: Circle())
              }
          }
              .frame(width: MainWindowChrome.appMarkSize,
                     height: MainWindowChrome.appMarkSize)
              .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
              .accessibilityHidden(true)
      }
  }
  ```

  Place it before the title/subtitle `VStack` in `MainWindowChromeBar`. Keep
  the title stack at a readable fixed measure and do not reduce the leading
  traffic-light clearance.

- [ ] **Step 6: Extend snapshot coverage**

  In the wide light/dark `Focus`, `Today`, `Review`, and `Settings` main-window
  snapshots, rely on the real chrome rather than adding a special image-only
  scenario. Add a narrow Focus snapshot assertion that the app mark and tab
  labels survive the compact fallback together.

- [ ] **Step 7: Verify green**

  Run: `./build.sh --check`

  Expected: all tests pass, including `Native chrome uses individual tabs and a compact app mark`.

- [ ] **Step 8: Commit the accepted task**

  ```bash
  git add Sources/Design/Components/TabRail.swift \
          Sources/Surfaces/Main/MainWindowHeader.swift \
          Sources/Surfaces/Snapshotter.swift Sources/SelfTest.swift
  git commit -m "ui: simplify tabs and add window identity"
  ```

## Task 2: Lead Today with a complete, accessible recap

**Files:**
- Modify: `Sources/Surfaces/Today/TodayView.swift:5-128`
- Modify: `Sources/Surfaces/Today/TodayRecap.swift:5-110`
- Modify: `Sources/SelfTest.swift`
- Modify: `Sources/Surfaces/Snapshotter.swift`

**Consumes:** `SummaryText.plain`, `GoalProgress`, `SessionStore.summarySentences`, `BoolBox`, `Tokens`.

**Produces:**

```swift
enum DaySurfaceOrder: CaseIterable {
    case header, qualification, recap, timeline, selectedDetail, supportingGroups
}

struct DayRecapDisclosurePresentation: Equatable {
    let isExpanded: Bool
    var chevronSystemName: String
    var accessibilityLabel: String
    var accessibilityValue: String
}
```

- [ ] **Step 1: Write failing Today-order and disclosure tests**

  Replace the affected expectations in `testDayAndFocusHierarchy` with:

  ```swift
  expect(DaySurfaceOrder.visible(hasQualification: true, hasSelection: true) == [
      .header, .qualification, .recap, .timeline, .selectedDetail, .supportingGroups
  ], "Today qualifies before the recap, then answers the day before its chronology", &problems)

  let closed = DayRecapDisclosurePresentation(isExpanded: false)
  expect(closed.chevronSystemName == "chevron.right"
             && closed.accessibilityLabel == "Show more about this day"
             && closed.accessibilityValue == "Collapsed",
         "the recap disclosure exposes one full-row collapsed action", &problems)
  let open = DayRecapDisclosurePresentation(isExpanded: true)
  expect(open.chevronSystemName == "chevron.down"
             && open.accessibilityLabel == "Hide more about this day"
             && open.accessibilityValue == "Expanded",
         "the recap disclosure exposes one full-row expanded action", &problems)
  ```

- [ ] **Step 2: Run the red test**

  Run: `./build.sh --check`

  Expected: compile/test failure because `DayRecapDisclosurePresentation` does
  not exist and `DaySurfaceOrder` still places recap after supporting groups.

- [ ] **Step 3: Implement the pure order/disclosure contracts**

  Change `DaySurfaceOrder` to the produced order, keeping `visible`’s existing
  filtering behaviour for qualification and selected detail. In
  `TodayRecap.swift`, add:

  ```swift
  struct DayRecapDisclosurePresentation: Equatable {
      let isExpanded: Bool
      var chevronSystemName: String { isExpanded ? "chevron.down" : "chevron.right" }
      var accessibilityLabel: String {
          isExpanded ? "Hide more about this day" : "Show more about this day"
      }
      var accessibilityValue: String { isExpanded ? "Expanded" : "Collapsed" }
  }
  ```

- [ ] **Step 4: Move the recap ahead of the time ribbon**

  In `TodayView.content`, keep `TodayHeader` and `IntegrityNotice` first, then
  place `TodayRecap(store: store)` before the `SurfacePanel` that owns
  `DayTimelineView`. Remove the old recap call after supporting groups. Do not
  move the integrity note after the recap.

- [ ] **Step 5: Replace the default disclosure target with one complete row**

  In `TodayRecap`, add `@StateObject private var narrativeExpanded = BoolBox()`.
  Replace `DisclosureGroup` with a plain `Button` whose label is:

  ```swift
  HStack(spacing: Tokens.Space.xs) {
      Image(systemName: presentation.chevronSystemName)
          .font(.caption.weight(.semibold))
      Text("More about this day")
      Spacer(minLength: 0)
  }
  .frame(maxWidth: .infinity, minHeight: AccessibilityMetrics.minimumTargetSize,
         alignment: .leading)
  .contentShape(Rectangle())
  ```

  Toggle `narrativeExpanded.value` with the existing reduced-motion policy from
  the parent view. Apply the produced accessibility label/value to the button.
  Render detailed sentences only when expanded, immediately below the button,
  preserving text selection and the existing plain-text conversion.

- [ ] **Step 6: Update Today snapshots**

  Add one expanded-recap Today snapshot fixture. Confirm its normal counterpart
  retains the same recap band without hidden content occupying space.

- [ ] **Step 7: Verify green and commit**

  Run: `./build.sh --check`

  ```bash
  git add Sources/Surfaces/Today/TodayView.swift \
          Sources/Surfaces/Today/TodayRecap.swift \
          Sources/Surfaces/Snapshotter.swift Sources/SelfTest.swift
  git commit -m "ui: lead Today with an accessible recap"
  ```

## Task 3: Keep Today inspection at its source

**Files:**
- Modify: `Sources/App/SessionStore.swift:107-129`
- Modify: `Sources/Surfaces/Today/TodayInspector.swift:3-96`
- Modify: `Sources/Surfaces/Today/TodayView.swift:53-128`
- Modify: `Sources/Surfaces/Dashboard/DashboardSessions.swift:11-262`
- Modify: `Sources/Surfaces/Dashboard/DashboardSections.swift:223-311`
- Modify: `Sources/SelfTest.swift`
- Modify: `Sources/Surfaces/Snapshotter.swift`

**Consumes:** Existing `selectedSession`, `selectedSegment`,
`TodayInspectorData`, `SessionStore.selectTodaySession`,
`SessionStore.selectTodayApp`, `SessionStore.selectTodayTimeline`.

**Produces:**

```swift
enum TodayInspectorOrigin: Equatable {
    case ribbon
    case session(UUID)
    case app(String)
}

extension SessionStore {
    @Published var todayInspectorOrigin: TodayInspectorOrigin?
    var todayInspectorPlacement: TodayInspectorOrigin?
}

// New stored optional inputs on the existing views:
// `var selectedDetail: AnyView? = nil`
```

- [ ] **Step 1: Write the failing origin-state test**

  Add `testTodayInspectorRemainsAtSelectionOrigin` to `SelfTest` using a real
  `FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)`. Select a
  real session, a real ranked app, then a real timeline fraction. Assert:

  ```swift
  expect(store.todayInspectorOrigin == .session(session.id),
         "a session selection records the session as its inspector origin", &problems)
  expect(store.todayInspectorOrigin == .app(app.bundleID),
         "an app selection records the app row as its inspector origin", &problems)
  expect(store.todayInspectorOrigin == .ribbon,
         "a ribbon selection records the ribbon as its inspector origin", &problems)
  store.clearTodaySelection()
  expect(store.todayInspector == nil && store.todayInspectorOrigin == nil,
         "Escape-style clearing removes inspector data and its origin together", &problems)
  ```

  Retain the existing assertion that exactly one backing session/segment
  selection exists after each action.

- [ ] **Step 2: Run the red test**

  Run: `./build.sh --check`

  Expected: compile failure because `todayInspectorOrigin` is absent.

- [ ] **Step 3: Add one ephemeral origin state to SessionStore**

  Add `@Published var todayInspectorOrigin: TodayInspectorOrigin?` beside the
  existing selected session/segment fields in `SessionStore`. This is UI state,
  not historical data; do not persist it.

  In `TodayInspector.swift`, define `TodayInspectorOrigin` and amend selection
  methods exactly as follows:

  ```swift
  func clearTodaySelection() {
      clearTimelineSelection()
      clearSession()
      todayInspectorOrigin = nil
      hoveredSegment = nil
      hoveredSession = nil
      highlightedBundleID = nil
  }

  func selectTodaySession(_ session: DaySession) {
      if selectedSession?.id == session.id { clearTodaySelection(); return }
      clearTimelineSelection()
      selectSession(session)
      todayInspectorOrigin = .session(session.id)
  }

  func selectTodayApp(_ bundleID: String) {
      if todayInspectorOrigin == .app(bundleID) { clearTodaySelection(); return }
      // retain the existing segment/layout/fraction selection calculation
      clearSession()
      selectTimeline(at: fraction)
      todayInspectorOrigin = .app(bundleID)
  }

  func selectTodayTimeline(at fraction: Double) {
      clearSession()
      selectTimeline(at: fraction)
      todayInspectorOrigin = selectedSegment == nil ? nil : .ribbon
  }
  ```

  Update all day-change and stale-selection clearing paths to use
  `clearTodaySelection()` where the intention is to clear the complete transient
  inspector. Do not alter the lower-level generic History selection helpers.

- [ ] **Step 4: Make inspector placement a pure view decision**

  Add a computed property in `TodayInspector.swift`:

  ```swift
  extension SessionStore {
      var todayInspectorPlacement: TodayInspectorOrigin? {
          guard todayInspector != nil else { return nil }
          return todayInspectorOrigin
      }
  }
  ```

  In `TodayView`, render `TodayInspector` below `DayTimelineView` only when
  `todayInspectorPlacement == .ribbon`. Add the following stored input to both
  `SessionsCard` and `TodayAppsList`:

  ```swift
  var selectedDetail: AnyView? = nil
  ```

  Each component renders `selectedDetail` immediately after its selected row.
  In `TodayView`, create the `AnyView(TodayInspector(...))` only when the
  current `todayInspectorPlacement` matches that surface (`.session(_)` for
  Sessions and `.app(_)` for At the Mac); otherwise pass `nil`. The inspector
  receives the same canonical `TodayInspectorData`, app sessions, and close
  closure in every placement. Existing non-Today callers use the default nil.

- [ ] **Step 5: Add explicit selected-row affordances without merging controls**

  In `SessionsCard`, keep the existing independent stretches/breaks disclosure
  button. Make the session selection button show a trailing
  `chevron.right`/`chevron.down` reflecting the source-local inspector state;
  use `SessionRowInteraction` only for its existing stretches disclosure.

  In `TodayAppsList`, add the same chevron and selected background to an app
  row. The whole app row remains one button. Neither row expands the Time
  Ribbon; the ribbon only receives existing selected/highlight state.

- [ ] **Step 6: Add source-specific snapshot scenarios**

  Create Today snapshots for session-origin, app-origin, and ribbon-origin
  inspector placement in light and dark. Each fixture must establish an actual
  store selection rather than drawing a synthetic inspector view.

- [ ] **Step 7: Verify green and commit**

  Run: `./build.sh --check`

  ```bash
  git add Sources/App/SessionStore.swift Sources/Surfaces/Today/TodayInspector.swift \
          Sources/Surfaces/Today/TodayView.swift \
          Sources/Surfaces/Dashboard/DashboardSessions.swift \
          Sources/Surfaces/Dashboard/DashboardSections.swift \
          Sources/Surfaces/Snapshotter.swift Sources/SelfTest.swift
  git commit -m "ui: keep Today details at their selection source"
  ```

## Task 4: Make day-goal progress visible and self-explanatory

**Files:**
- Modify: `Sources/Surfaces/Dashboard/DayPickerCalendar.swift:3-307`
- Modify: `Sources/SelfTest.swift`
- Modify: `Sources/Surfaces/Snapshotter.swift`

**Consumes:** `DayFacts.goalAchieved`, `DayFacts.focused`, selected date, daily goal, and existing date accessibility labels.

**Produces:**

```swift
enum DayGoalState: Equatable {
    case none
    case belowHalf
    case halfOrMore
    case goalMet

    init(share: Double)
    var accessibilityLabel: String
    var progressFraction: CGFloat
    var showsCheckmark: Bool
}
```

- [ ] **Step 1: Write the failing goal-state test**

  Add `testDayGoalPresentationStates` to `SelfTest`:

  ```swift
  let cases: [(Double, DayGoalState, String, CGFloat, Bool)] = [
      (0, .none, "No focus goal progress", 0, false),
      (0.49, .belowHalf, "Below half of goal", 0.35, false),
      (0.5, .halfOrMore, "Half or more of goal", 0.68, false),
      (1, .goalMet, "Goal met", 1, true),
      (1.7, .goalMet, "Goal met", 1, true)
  ]
  for (share, expectedState, expectedLabel, expectedFraction, expectedCheck) in cases {
      let state = DayGoalState(share: share)
      expect(state == expectedState && state.accessibilityLabel == expectedLabel
                 && state.progressFraction == expectedFraction
                 && state.showsCheckmark == expectedCheck,
             "goal share \(share) maps to a literal visible calendar state", &problems)
  }
  ```

- [ ] **Step 2: Run the red test**

  Run: `./build.sh --check`

  Expected: compile failure because `DayGoalState` is missing.

- [ ] **Step 3: Implement the pure state classification**

  At file scope in `DayPickerCalendar.swift`, implement the produced enum.
  Clamp non-finite/negative input to zero before classifying. Use exact boundary
  handling: `0.5` is `halfOrMore`; `1.0` is `goalMet`. Keep the literal labels
  from the test.

- [ ] **Step 4: Replace opacity-only cell tint with matching progress markers**

  In `dayCell`, calculate:

  ```swift
  let share = goal > 0 ? (facts.goalAchieved ?? facts.focused) / goal : 0
  let goalState = DayGoalState(share: share)
  ```

  Leave the selected cell’s existing full focus-blue background intact. For
  unselected cells, remove `tint(_:)` and add a bottom-aligned rounded marker
  whose width is `max(0, cellWidth - 12) * goalState.progressFraction`. Use a
  low-opacity fill for below-half, a stronger focus fill for half-or-more, and
  full focus fill plus a white `checkmark` for goal-met. Days with no progress
  render no marker. Keep tracked-only dot/quiet text behaviour unchanged.

- [ ] **Step 5: Replace the legend symbols with real marker samples**

  Create a private `DayGoalLegendItem` view that renders the same marker and
  checkmark rules as a cell in a fixed 24-point sample. Use it for the three
  labelled states. Keep the explanatory goal/focused-time text beneath the
  legend. Do not use `circle`, `circle.lefthalf.filled`, or
  `checkmark.circle.fill` as stand-in symbols.

- [ ] **Step 6: Amend accessibility and snapshots**

  Append `goalState.accessibilityLabel` to a pickable date’s existing
  accessibility label whenever `goal > 0`. Add calendar snapshot fixtures for
  below-half, half-or-more, goal-met, and selected-goal-met states in each
  appearance.

- [ ] **Step 7: Verify green and commit**

  Run: `./build.sh --check`

  ```bash
  git add Sources/Surfaces/Dashboard/DayPickerCalendar.swift \
          Sources/Surfaces/Snapshotter.swift Sources/SelfTest.swift
  git commit -m "ui: clarify calendar goal progress"
  ```

## Task 5: Keep historical day inspection wholly inside Review

**Files:**
- Modify: `Sources/Surfaces/Review/ReviewView.swift:3-200`
- Modify: `Sources/Surfaces/Review/HistoryView.swift:368-470`
- Modify: `Sources/Surfaces/Review/ReviewDayDetail.swift:3-192`
- Modify: `Sources/SelfTest.swift`
- Modify: `Sources/Surfaces/Snapshotter.swift`

**Consumes:** `ReviewDayRoute.select`, `MainWindowModel.reviewSelectedDate`,
`MainWindowModel.clearReviewDay`, `SessionStore.reviewDayDetail(for:)`.

**Produces:** A Review detail component with only evidence and close behaviour;
no `onOpenInToday` parameter or Review-to-Today control.

- [ ] **Step 1: Write the failing Review route test**

  In `testReviewContentHierarchy`, replace the explicit route assertions with:

  ```swift
  navigation.selectReviewDay(yesterday, calendar: calendar)
  expect(navigation.selectedTab == .review,
         "selecting historical evidence remains in Review", &problems)
  navigation.clearReviewDay()
  expect(navigation.selectedTab == .review && navigation.requestedDate == nil,
         "closing historical evidence does not create a Today route", &problems)

  let detailAction = ReviewDayDetailPresentation()
  expect(!detailAction.showsTodayRoute,
         "Review detail exposes no route to a past Today canvas", &problems)
  ```

  Refer to `ReviewDayDetailPresentation` without defining it in the test;
  compilation must fail until production adds it.

- [ ] **Step 2: Run the red test**

  Run: `./build.sh --check`

  Expected: compile failure because `ReviewDayDetailPresentation` does not exist.

- [ ] **Step 3: Add the presentation contract and remove the outward action**

  At file scope in `ReviewDayDetail.swift`, add:

  ```swift
  struct ReviewDayDetailPresentation: Equatable {
      let showsTodayRoute = false
  }
  ```

  Remove `onOpenInToday` from `ReviewDayDetailPanel`’s stored properties and
  every initializer. Remove the `actions` view and its `Open in Today` button.
  Retain `onClose` for standalone period detail and retain History’s selected
  row toggle for joined detail.

- [ ] **Step 4: Update all Review call sites and copy**

  In `ReviewView`, construct the detail with `detail` and `onClose` only. In
  `HistoryView`, construct the joined detail with the same two inputs.

  Change the History subtitle to:

  ```swift
  "Search the local record and select a day for its complete detail."
  ```

  Update ReviewDayRoute comments so they no longer describe an explicit Today
  action. Do not remove `MainWindowModel.openToday(date:)`; it belongs to
  explicit Today-level navigation outside Review.

- [ ] **Step 5: Update Review snapshots**

  Refresh week, month, selected-first-day, selected-last-day, and History
  selection snapshots. Confirm selected details end after evidence rather than
  containing a primary blue action that leaves the current analytical context.

- [ ] **Step 6: Verify green and commit**

  Run: `./build.sh --check`

  ```bash
  git add Sources/Surfaces/Review/ReviewView.swift \
          Sources/Surfaces/Review/HistoryView.swift \
          Sources/Surfaces/Review/ReviewDayDetail.swift \
          Sources/Surfaces/Snapshotter.swift Sources/SelfTest.swift
  git commit -m "ui: keep historical detail within Review"
  ```

## Task 6: Convert Settings into one synchronised preferences document

**Files:**
- Create: `Sources/Surfaces/Settings/SettingsScrollPresentation.swift`
- Modify: `Sources/Surfaces/Settings/SettingsView.swift:3-151`
- Modify: `Sources/Surfaces/Settings/SettingsSidebar.swift:1-179`
- Modify: `Sources/Surfaces/Settings/SettingsGroups.swift:20-329`
- Modify: `Sources/SelfTest.swift`
- Modify: `Sources/Surfaces/Snapshotter.swift`

**Consumes:** `SettingsSection.allCases`, `SettingsSection.matching(_:)`,
`MainWindowModel.settingsSection`, `MainWindowModel.settingsQuery`,
`SettingsLayout.usesSidebar(at:)`, and existing backed `SettingsModel` rows.

**Produces:**

```swift
struct SettingsSectionAnchor: Equatable {
    let section: SettingsSection
    let minY: CGFloat
}

enum SettingsScrollPresentation {
    static func visibleSections(query: String) -> [SettingsSection]
    static func activeSection(
        anchors: [SettingsSectionAnchor],
        viewportTop: CGFloat = 0,
        order: [SettingsSection] = SettingsSection.allCases
    ) -> SettingsSection?
}
```

- [ ] **Step 1: Write the failing pure index/search tests**

  Add `testSettingsContinuousDocumentPresentation` to `SelfTest`:

  ```swift
  let all = SettingsScrollPresentation.visibleSections(query: "")
  expect(all == SettingsSection.allCases,
         "an empty Settings query keeps the complete document order", &problems)
  expect(SettingsScrollPresentation.visibleSections(query: "privacy") == [.data],
         "Settings search filters visible sections by literal control labels", &problems)

  let anchors = [
      SettingsSectionAnchor(section: .general, minY: -180),
      SettingsSectionAnchor(section: .focus, minY: -8),
      SettingsSectionAnchor(section: .away, minY: 210)
  ]
  expect(SettingsScrollPresentation.activeSection(anchors: anchors) == .focus,
         "the most recently passed heading owns the sidebar selection", &problems)
  expect(SettingsScrollPresentation.activeSection(anchors: [
      SettingsSectionAnchor(section: .general, minY: 20),
      SettingsSectionAnchor(section: .focus, minY: 180)
  ]) == .general,
         "before the first heading passes, the first visible heading is selected", &problems)
  ```

  Add a deterministic tie case with duplicate `minY` values and assert that
  `SettingsSection.allCases` order wins.

- [ ] **Step 2: Run the red test**

  Run: `./build.sh --check`

  Expected: compilation fails because `SettingsScrollPresentation` and
  `SettingsSectionAnchor` do not exist.

- [ ] **Step 3: Implement the pure settings scroll contract**

  Create `SettingsScrollPresentation.swift` with:

  ```swift
  import SwiftUI

  struct SettingsSectionAnchor: Equatable {
      let section: SettingsSection
      let minY: CGFloat
  }

  enum SettingsScrollPresentation {
      static func visibleSections(query: String) -> [SettingsSection] {
          SettingsSection.matching(query)
      }

      static func activeSection(
          anchors: [SettingsSectionAnchor],
          viewportTop: CGFloat = 0,
          order: [SettingsSection] = SettingsSection.allCases
      ) -> SettingsSection? {
          let indexed = anchors.compactMap { anchor in
              order.firstIndex(of: anchor.section).map { ($0, anchor) }
          }.sorted { lhs, rhs in
              lhs.1.minY == rhs.1.minY ? lhs.0 < rhs.0 : lhs.1.minY < rhs.1.minY
          }
          guard !indexed.isEmpty else { return nil }
          if let passed = indexed.last(where: { $0.1.minY <= viewportTop + 8 }) {
              return passed.1.section
          }
          return indexed[0].1.section
      }
  }
  ```

- [ ] **Step 4: Make SettingsGroups render document sections rather than a pane switch**

  Keep `SettingsGroups(model:section:)` as the backed controls source. Add a
  `SettingsDocumentSection` view in `SettingsView.swift` that wraps one section
  heading plus `SettingsGroups`, tags it with `section.id`, and reports its
  `minY` through a named coordinate-space preference key. It must retain the
  existing 720-point panel measure and each original `SurfacePanel` grouping.

- [ ] **Step 5: Rebuild the wide Settings canvas around one ScrollViewReader**

  Replace selected-pane `detail(section)` with:

  ```swift
  ScrollViewReader { proxy in
      HStack(alignment: .top, spacing: Tokens.Space.xl) {
          SettingsSidebar(sections: visibleSections,
                          selected: $navigation.settingsSection,
                          onSelect: { section in
                              navigation.settingsSection = section
                              scrollTo(section, proxy: proxy)
                          })
          Divider()
          ScrollView {
              LazyVStack(alignment: .leading, spacing: Tokens.Space.xxl) {
                  ForEach(visibleSections) { section in
                      SettingsDocumentSection(model: model, section: section)
                  }
              }
          }
      }
  }
  ```

  Implement `scrollTo` with `.top` anchoring and a 0.18-second ease only when
  Reduce Motion is false. Store a short-lived programmatic target in a
  `@StateObject` box; while that target’s heading is still moving into place,
  ignore geometry updates that would select a different section. Clear the
  target once the selected section becomes the active anchor.

  On every anchor-preference change, call
  `SettingsScrollPresentation.activeSection` and write the result to
  `navigation.settingsSection` only when no programmatic target is in flight.

- [ ] **Step 6: Integrate search with the index and document**

  On wide layouts, render the existing real `TextField` as the first element
  inside `SettingsSidebar`, at its 240-point width. Remove the unrelated
  480-point search strip above both columns. Use
  `SettingsScrollPresentation.visibleSections(query:)` for both sidebar and
  document. When the filtered collection changes:

  - select the current section if it remains visible;
  - otherwise select and scroll to the first result; and
  - render the existing concise `EmptyState` if there are no results.

  Clearing the query restores the ordered document and keeps the current
  section whenever it appears in the full list.

- [ ] **Step 7: Preserve one document at the narrow breakpoint**

  At widths below 1,080, replace the selected-pane `SettingsGroupMenu` action
  with a jump menu whose selection calls the same `scrollTo` function. Keep a
  full-width in-document search field above the continuous ScrollView. The
  menu is a locator only: it never removes non-selected document sections.

  Update `SettingsSidebar` and `SettingsGroupMenu` initialisers to take:

  ```swift
  let sections: [SettingsSection]
  let selected: SettingsSection
  let onSelect: (SettingsSection) -> Void
  ```

  Do not keep a selected-pane binding API after this task.

- [ ] **Step 8: Add search/scroll snapshots**

  Add wide light/dark snapshots of the complete Settings document at General,
  Appearance, and Advanced scroll positions; add a filtered `privacy` result,
  a no-results state, and a narrow jump-menu position. Build fixtures from the
  real `SettingsModel` so all controls remain backed.

- [ ] **Step 9: Verify green and commit**

  Run: `./build.sh --check`

  ```bash
  git add Sources/Surfaces/Settings/SettingsScrollPresentation.swift \
          Sources/Surfaces/Settings/SettingsView.swift \
          Sources/Surfaces/Settings/SettingsSidebar.swift \
          Sources/Surfaces/Settings/SettingsGroups.swift \
          Sources/Surfaces/Snapshotter.swift Sources/SelfTest.swift
  git commit -m "ui: make Settings a continuous preferences document"
  ```

## Task 7: Reconcile documentation and perform the final visual gate

**Files:**
- Modify: `docs/specs/2026-08-30-premium-interface-design-system.md`
- Modify: `docs/specs/2026-08-30-native-continuity-refinement-design.md`
- Modify: `README.md` only if it still describes removed Review-to-Today navigation

**Consumes:** Tasks 1–6, snapshot scenarios, `build.sh` verification modes.

- [ ] **Step 1: Write the documentation-alignment test**

  Add one `SelfTest` assertion to the Review/Today hierarchy test using public
  presentation contracts rather than scanning prose:

  ```swift
  expect(!ReviewDayDetailPresentation().showsTodayRoute,
         "the shipped Review presentation still has no historical Today route", &problems)
  expect(DaySurfaceOrder.visible(hasQualification: false, hasSelection: false).first == .header,
         "the documented Today order begins with its day context", &problems)
  ```

- [ ] **Step 2: Run the full staged verification**

  Run: `./build.sh --check`

  Expected: all headless tests pass and the staged bundle passes strict code-signature verification without replacing the local app.

- [ ] **Step 3: Amend the earlier design-system document**

  Make the following exact documentation corrections:

  - tabs have independent selected/unselected controls and no outer rail;
  - Today order places recap before the ribbon, and inspector placement follows
    the selection origin;
  - calendar goal legend mirrors actual progress markers;
  - Review historical detail has no Today action; and
  - Settings is one scrollable document with a synchronised index, with search
    in the wide sidebar and a narrow jump-menu locator.

  Preserve all accounting, integrity, and privacy clauses that are not in
  conflict.

- [ ] **Step 4: Render and inspect the final matrix**

  Run:

  ```bash
  snapshot_dir="$(mktemp -d /tmp/focuscontinuity-native-continuity.XXXXXX)"
  ./build.sh --test
  FocusContinuity.app/Contents/MacOS/FocusContinuity --snapshot "$snapshot_dir"
  ```

  Inspect the 98-plus PNG matrix, focusing on the states listed in Tasks 1–6.
  Confirm all selected-details remain at their origin and no global chrome,
  Settings index, calendar legend, or history detail is clipped in light or dark.

- [ ] **Step 5: Final repository checks**

  Run:

  ```bash
  codesign --verify --deep FocusContinuity.app
  git diff --check
  git status --short
  ```

  Expected: ordinary local code-signature verification passes; no generated
  app bundle or Finder metadata appears in Git status; only intended tracked
  source/tests/docs changes were committed.

- [ ] **Step 6: Commit the final documentation alignment**

  ```bash
  git add docs/specs/2026-08-30-premium-interface-design-system.md \
          docs/specs/2026-08-30-native-continuity-refinement-design.md \
          Sources/SelfTest.swift README.md
  git commit -m "docs: align interface guidance with native continuity"
  ```
