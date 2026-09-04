# FocusContinuity Native Continuity Refinement — Design

**Status:** Approved design direction; implementation not started  
**Date:** 30 August 2026  
**Scope:** Main-window chrome, Today, Review, day calendar, and Settings  
**Supersedes:** Only the conflicting presentation clauses in `2026-08-30-premium-interface-design-system.md`; time accounting, privacy, and all core data contracts remain unchanged.

## 1. Objective

Make the desktop interface feel like one calm, native macOS product. The work
removes interaction surprises, makes active states legible without relying on
subtle decoration, and gives Settings the coherent continuous-document
behaviour expected of a serious desktop application.

The intended result is not a new visual language. It keeps the established
warm-neutral surfaces, system typography, blue focus accent, native traffic
lights, and evidence-first reporting. It changes where information appears,
how selections reveal detail, and how the user moves through Settings.

## 2. Decisions and rationale

| Area | Decision | Rationale |
|---|---|---|
| Global tabs | Remove the rail's enclosing capsule and leave five self-contained tab buttons. | The outer capsule is redundant framing around already-contained controls and makes the header look heavy. |
| Window identity | Add a compact FocusContinuity app mark beside the title. | A hidden-titlebar app otherwise has traffic lights and a title but no recognisable product identity. |
| Today hierarchy | Place the day recap immediately after the day header and any integrity notice. | Users first need a short answer to “how did this day go?” before reading its chronology. |
| Day detail | Keep a selected session/app detail under the list that caused it; the ribbon only highlights the same evidence. | A click should expand where the user is looking, not insert content above the clicked row and move the visual target. |
| Recap disclosure | Make the whole “More about this day” row clickable. | A labelled disclosure is a row-level action; requiring a tiny chevron target is not a native-quality interaction. |
| Calendar goal feedback | Use three visibly distinct cell states and a legend built from the same visual primitive. | The existing opacity-only scale is too subtle and the legend symbols do not clearly correspond to the cells. |
| Historical Review | Remove `Open in Today` entirely. | Review is the complete, purpose-built home for historical inspection; a cross-tab route duplicates context without giving the user a stronger task. |
| Settings | Replace one-selected-pane navigation with a continuous settings document and synchronised sidebar index. | Most groups are too small to justify their own page. A continuous preference document improves scanning, search, and configuration continuity. |

## 3. Non-negotiable constraints

1. Preserve macOS 13 support, SwiftUI/AppKit, direct `swiftc` builds, and no third-party packages or permissions.
2. Do not alter time accounting, period statistics, historical clipping, persistence, privacy, or usage accuracy qualification.
3. Maintain the 980-point minimum window width and existing keyboard routes unless an interaction is deliberately removed below.
4. Use Australian English in user-facing copy and documentation.
5. Global window chrome stays fixed while selected canvases scroll.
6. Do not add decorative gradients, unbounded animation, or cards merely to fill space.
7. All new tests remain headless, suite-scoped, and avoid live user history.

## 4. Global chrome

### 4.1 Brand mark

`FocusContinuityMark` is a 24-point app-icon rendering when the bundle icon is
available, with a `target` SF Symbol in the focus colour as the deterministic
fallback for previews and headless snapshots. It sits immediately before the
title/subtitle stack and is accessibility-hidden because the adjacent title
already supplies the application identity.

The mark is neither a launcher-sized logo nor a second page icon. It is a
single compact identity cue in the content-titlebar row.

### 4.2 Tab treatment

`TabRail` retains its five labels, icons where width permits, `⌘1`–`⌘5`
shortcuts, arrow-key movement, VoiceOver selected state, and reduced-motion
behaviour.

It removes the enclosing capsule's fill, stroke, and padding. Each tab keeps
its own practical hit target:

- selected: focus-blue capsule with `onFocus` foreground;
- unselected: transparent background, primary foreground, no surrounding
  border; and
- hover/focus: the existing quiet interactive state without an all-rail ring.

At constrained widths, the existing icon-elision fallback remains. The lack of
an outer rail must not make the controls ambiguous: labels and selected state
remain explicit.

## 5. Today: summary first, evidence in place

### 5.1 Reading order

Today renders this fixed semantic order:

```text
Day header and date controls
  ↓
Integrity qualification, when required
  ↓
Day recap band
  ↓
Time ribbon
  ↓
Sessions and At the Mac evidence, with local selected detail
```

`DaySurfaceOrder` must model this order. A qualification remains before every
app-use figure it qualifies. The recap moves before the ribbon, never above an
integrity notice.

### 5.2 Day recap band

The recap becomes a lightweight top summary band rather than a large, late page
card. It retains the canonical values already supplied by the store:

- Focused, with focused-active goal credit clearly qualified;
- At the Mac, named as observed app use;
- Sessions; and
- Longest.

The lead canonical summary sentence stays below the figures. It remains plain
text, preserves its current `SummaryText.plain` handling, and is available for
text selection. No calculation is moved into the view.

`More about this day` becomes a full-width `Button` disclosure row. Its label,
chevron, VoiceOver state, and activation target form one control:

- collapsed: `chevron.right`, “Show more about this day”; and
- expanded: `chevron.down`, “Hide more about this day”.

The extra sentences attach directly below that row with a small internal inset.
They do not become a second card or float apart from the label.

### 5.3 Local inspector placement

The Time Ribbon remains the day’s chronological visual. Selecting a ribbon
segment still establishes the existing single Today inspector state and frames
the matching evidence. It does **not** grow an inspector below the ribbon when
the selection originated from a lower list.

Instead:

- selecting a `Sessions` row reveals `TodayInspector` directly below the
  selected session within the Sessions surface;
- selecting an `At the Mac` row reveals the same inspector directly below the
  selected app within that surface; and
- selecting a ribbon segment reveals the inspector directly below the ribbon,
  because the ribbon is then the origin.

The store retains exactly one inspector state. Selecting a different origin
replaces it; selecting the current origin or pressing Escape clears it. The
ribbon highlights the selected session/app in every case, but does not acquire
an unrelated detail block merely because a supporting row was clicked.

Rows with a local inspector receive a clear selected surface and an appropriate
`chevron.right`/`chevron.down` affordance. A session's independent
stretches-and-breaks disclosure remains a separate, labelled control; selecting
the session must not toggle that disclosure.

## 6. Day calendar: visible goal progress

### 6.1 Goal state

`DayGoalState` is a pure presentation classification based only on the existing
focused-active goal share:

| State | Share | Cell treatment |
|---|---:|---|
| `none` | 0 | No progress marker; tracked-only days retain their quiet dot. |
| `belowHalf` | `0 < share < 0.5` | A low-emphasis focus progress marker. |
| `halfOrMore` | `0.5 ≤ share < 1` | A stronger focus progress marker. |
| `goalMet` | `share ≥ 1` | A filled focus marker with a white checkmark. |

The selected date keeps its high-contrast selected treatment and does not
attempt to show a second competing goal colour. Its accessibility label still
states the actual focused and tracked amounts plus the goal status in words.

### 6.2 Cell and legend grammar

Every cell uses the same small bottom progress marker: a rounded, focus-colour
bar whose width and fill distinguish below-half, half-or-more, and goal-met.
Goal-met adds the visible checkmark. The main date and focused-time line retain
their current scan-friendly structure.

The legend renders three miniature examples of those exact markers, followed
by literal labels: `Below half`, `Half or more`, and `Goal met`. It is not a
row of unrelated SF Symbols. Its explanatory line remains: `Share of your
<goal> goal · figure is focused time`.

The calendar remains a date-picker popover. It does not become a second report
or change its day/month bounds.

## 7. Review: complete historical inspection

### 7.1 Removed route

Review no longer presents `Open in Today` in period-detail or History-detail
contexts. `ReviewDayDetailPanel` no longer accepts or renders an action that
calls `MainWindowModel.openToday(date:)`.

The existing Review selection contract remains:

```text
bar or History row selected
  → selected Review local date changes
  → Review tab, period, History filters, and detail remain in place
```

Closing the detail or pressing the selected row clears only the Review
selection. It never changes tabs. `MainWindowModel.openToday(date:)` remains
available for explicit Today-level features but is no longer a Review action.

### 7.2 Detail action hierarchy

Review detail retains concise metrics, focus stretches, app evidence, and its
close affordance. Removing the action shortens the panel and makes its message
unambiguous: the user is already viewing the relevant historical record in the
right surface.

## 8. Settings: continuous document and synchronised index

### 8.1 Wide layout (1,080 points and above)

Settings becomes one vertical document. All visible groups appear in the
established order:

1. General
2. Focus sessions
3. Away and breaks
4. Automatic and rewards
5. Tracking and apps
6. Appearance
7. Data and privacy
8. Advanced

The left sidebar is a persistent index, not a view switcher:

- clicking an item scrolls the main document to that section heading;
- the heading is placed at a comfortable top reading position, below fixed
  window chrome;
- as the document scrolls, the foremost visible section updates the sidebar
  selection with a restrained ease animation; and
- the sidebar itself remains stable where all eight items fit. Its changing
  selected state is the meaningful visual motion, not gratuitous scrolling.

The right document keeps the existing 720-point readable control measure.
Small groups stay small; the document does not stretch a single preference into
a sparse full-height page. Each section has a title/icon anchor and one or more
existing `SurfacePanel`s. Panels may remain separate only where they express a
real sub-group, such as Away’s stepping-away and breaks settings.

### 8.2 Search

Search moves into the top of the sidebar on wide layouts, matching macOS
preferences conventions and the navigation it filters. It is constrained to
the sidebar width rather than spanning a disconnected strip above both panes.

Searching is live and literal:

- the sidebar shows only matching section names/control labels;
- the document shows only matching sections, in their original order;
- a non-empty result set starts at its first matching section;
- clearing search restores the full document and retains the currently visible
  section where possible; and
- no results show one concise empty state in the document and no stale selected
  panel.

Search indexes only the existing visible section and control labels. It does
not pretend that narrative help text is a hidden setting.

### 8.3 Narrow layout (980–1,079 points)

The same continuous document is used. The sidebar is replaced by a compact
section jump menu above the document, plus the in-document search field. A
menu choice scrolls to the section rather than replacing the content. This
avoids maintaining two settings information architectures.

### 8.4 Scroll-state implementation contract

Use a named coordinate space and section-anchor preference values to observe
the document's heading positions on macOS 13. `ScrollViewReader` handles
sidebar/menu jumps. A pure `SettingsScrollPresentation.activeSection(...)`
helper chooses the foremost visible section from the reported anchors,
including deterministic tie-breaking in declared section order.

The helper consumes section IDs and positions; it does not know about SwiftUI
views, preferences, or persistence. `MainWindowModel.settingsSection` remains
the single selected-index value. It is not persisted and never changes a
setting.

Programmatic scrolling must suppress only the immediate geometry echo that it
caused, so a sidebar click cannot animate to its destination and then select a
different section mid-flight. Reduced Motion replaces the short interpolation
with an immediate state change.

## 9. Interaction and accessibility requirements

| Interaction | Pointer behaviour | Keyboard/VoiceOver behaviour |
|---|---|---|
| Tab | Each tab is an independent target; selected tab is visibly filled. | Existing `⌘1`–`⌘5` and left/right movement remain. |
| More-about disclosure | Text and chevron share one full-row target. | Announces show/hide action and expanded/collapsed value. |
| Session/app detail | Row selects and reveals a detail at that row’s surface. | Announces selected state and detail; Escape clears only detail. |
| Calendar progress | State is visible through marker shape/fill and checkmark. | Literal goal status appears in each date’s label; never colour alone. |
| Review | Selection reveals detail only in Review. | No control announces or performs an unexpected tab route. |
| Settings index | Sidebar/menu scrolls to a document section. | Selected index changes as document heading changes; focus order remains index then document. |

All controls retain at least the existing 28-point practical target. Text
selection remains available for narrative and diagnostic content. Motion is
limited to 0.16–0.20-second transitions and disabled when macOS Reduce Motion
is enabled.

## 10. Source changes anticipated

| Area | Files | Intended change |
|---|---|---|
| Global chrome | `Sources/Design/Components/TabRail.swift`, `Sources/Surfaces/Main/MainWindowHeader.swift` | Independent tabs and app mark. |
| Today hierarchy/recap | `Sources/Surfaces/Today/TodayView.swift`, `Sources/Surfaces/Today/TodayRecap.swift`, `Sources/Surfaces/Dashboard/DashboardSessions.swift`, `Sources/Surfaces/Dashboard/DashboardSections.swift`, `Sources/Surfaces/Today/TodayInspector.swift` | Top recap, complete disclosure target, source-local inspector placement, explicit row affordances. |
| Calendar | `Sources/Surfaces/Dashboard/DayPickerCalendar.swift` | Pure goal-state presentation and matching legend. |
| Review | `Sources/Surfaces/Review/ReviewView.swift`, `Sources/Surfaces/Review/HistoryView.swift`, `Sources/Surfaces/Review/ReviewDayDetail.swift`, `Sources/App/MainWindowModel.swift` | Remove Review-to-Today action/route. |
| Settings | `Sources/Surfaces/Settings/SettingsView.swift`, `Sources/Surfaces/Settings/SettingsSidebar.swift`, `Sources/Surfaces/Settings/SettingsGroups.swift` | Continuous document, scroll-aware index, integrated search, narrow jump menu. |
| Tests/snapshots | `Sources/SelfTest.swift`, `Sources/Surfaces/Snapshotter.swift` | Behaviour contracts and visual-state coverage. |
| Existing system document | `docs/specs/2026-08-30-premium-interface-design-system.md` | Amend the conflicting tabs, Today, Review, and Settings clauses. |

No Core accounting, archive schema, persistence format, build script, or
generated bundle is in scope.

## 11. Test-first acceptance criteria

### Automated behaviour

1. The tab presentation has no outer rail surface while selected/unselected
   tab state and keyboard routes remain explicit.
2. The top chrome has a deterministic app-mark fallback and preserves native
   traffic-light clearance.
3. Today order is header → qualification → recap → ribbon → supporting groups;
   a recap disclosure exposes a full-row label/action/state contract.
4. A session-origin selection produces a session-local detail; an app-origin
   selection produces an app-local detail; a ribbon-origin selection remains
   ribbon-local. All share the existing one inspector state and Escape clears
   only that state.
5. Calendar state classification maps literal goal shares to `none`,
   `belowHalf`, `halfOrMore`, and `goalMet`; accessibility text states the
   status independently of colour.
6. Selecting or closing a Review day never changes `selectedTab`; Review detail
   exposes no Today action.
7. Settings anchor selection is deterministic for initial position, exact
   heading, overlapping reported positions, filtering, and reduced-motion
   programmatic scroll.
8. Settings search filters the continuous document and index by existing labels
   only, clearing cleanly restores the full order, and a jump target is always
   a visible section.

### Visual matrix

Render and inspect light/dark, minimum/comfortable states for:

- selected and unselected global tabs;
- Today with no selection, session selection, app selection, ribbon selection,
  and expanded recap;
- day calendar with each goal state plus selected/today states;
- Review period and History selected day without a cross-tab action; and
- Settings at wide continuous-document, filtered, no-results, and narrow
  jump-menu states.

The first manual pass verifies no selected detail displaces its origin, no
calendar legend state is visually ambiguous, no app mark collides with traffic
lights, and no Settings sidebar/index selection drifts from the foremost
document section.

## 12. Out of scope

- New onboarding, account, cloud sync, export, or analytics;
- Editing historical records or repairing historical usage;
- Replacing the existing date picker with a full calendar application;
- Changing the focus timer, live tracking, app-usage recorder, or goal maths;
- Distribution signing, notarisation, or GitHub push.

