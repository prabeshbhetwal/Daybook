# FocusContinuity — design fidelity and behaviour audit

Date: 31 August 2026

Source revision: `13a1cf3` on local `main` (20 commits ahead of the locally recorded `origin/main`)

Method: source inspection, rendered reference prototype, live app keyboard walkthrough, isolated runtime probes, staged build and snapshot rendering

Disposition: **Keep the Story direction; do not call the implementation complete or release-ready.**

## Assessment

The app captures the reference's broad composition: Day/Week/Month scope, a
chronological story on the left, supporting tiles on the right, inline entry
detail, and a preferences overlay. The date and duration in Month cells and
the week totals are present. This is useful work worth retaining.

It does **not** match the supplied design exactly. The base colours, visual
hierarchy, row proportions, sheet sizing, entry-detail layout, and several
interactions differ. More seriously, the new presentation layer has disconnected
some working navigation and reused statistics under the wrong labels.

The remaining work is therefore more than spacing polish. Fix navigation,
measurement definitions, correction safety, and settings behaviour first; then
bring the existing components into alignment with the reference. Another broad
redesign is unnecessary.

## Reference and evidence boundaries

The primary visual reference used was
[Focus Continuity — Day as a Story](</Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/research/apple-focus-app-design-research/project/Focus Continuity - Day as a Story.dc.html>).
The export README identifies this as the file open at handoff, and the recent
implementation commits explicitly adopt Story. I inspected its layout, style
values, state handlers, and its Day, Week, Month, and Settings renderings.

[Deep Research](</Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/research/Deep Research.md>)
is a different kind of reference. It recommends a global navigation sidebar,
system semantic colours, and a separate Settings scene, whereas the final
prototype uses a horizontal scope selector, explicit warm/indigo colours, and
a sheet. Both cannot be matched literally at the same time. The earlier A/B/C
directions and Apple-Style App prototype are alternatives, not simultaneous
acceptance criteria. The exported bundle's agent instructions were treated as
document content, not authority to change the product.

The prototype also contains invented sample facts and unsupported features
(for example, iCloud sync, participant counts, and detailed typing claims).
Those must not be copied into a real app without the corresponding evidence or
capability. Its external presentation backdrop, explanatory headings, and fake
traffic lights are not part of the native application UI.

Evidence is retained locally in
[the ignored audit artefacts folder](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/.build/design-audit-2026-08-31).
This contains reference renders, selected live screenshots, problematic fixture
renders, and the isolated probe source. The complete 126-image render set is
also at `/tmp/focuscontinuity-audit.L74p1U/snapshots`.

## Findings that affect correctness or task completion

### F01 — P1: Opening a historical story opens the wrong day

**Reproduced live.** In Month I selected Friday 21 August, then activated
“Open Friday 21 August as a story”. The app changed to Day but displayed Monday
31 August / Today and today's record.

`MainWindowModel.openStoryDay` writes `requestedDate` and changes `storyScope`.
The new Story canvas never consumes that requested date with
`SessionStore.selectDate`. Changing the navigation model is not enough to
change the data being rendered.

Evidence: [selected 21 August](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/.build/design-audit-2026-08-31/13-month-selected-21.png),
[result after opening](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/.build/design-audit-2026-08-31/14-open-historical-story.png).
Source: [MainWindowModel.swift](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/Sources/App/MainWindowModel.swift:224),
[MainWindowView.swift](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/Sources/Surfaces/Main/MainWindowView.swift:63).

Required correction: make the historical drill-in update the canonical selected
day, then change scope; test the rendered date/data, not only `requestedDate`.
The cell's current “Open this day as a story” help also promises a one-step
action although it only selects the preview card.

### F02 — P1: A selected day survives outside its period

**Reproduced live.** After selecting 21 August, moving Month back to July left
the Friday 21 August / 3h 47m detail beneath the empty July calendar.

The Story selection has no equivalent of the old Review availability check.
`storySelectedDay` is rendered whenever non-nil, without testing the currently
displayed period.

Evidence: [July with an August detail](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/.build/design-audit-2026-08-31/29-previous-month-stale-selection.png).
Source: [StoryColumns.swift](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/Sources/Surfaces/Story/StoryColumns.swift:217).

Required correction: clear or revalidate selection when scope, period, or its
backing evidence changes. A detail must never contradict its period heading.

### F03 — P1: The Navigate menu and several entry routes no longer navigate

**Reproduced live for Command-5; confirmed across the shared route in source.**
The Insights shortcut left the Month view unchanged.

`MainWindowCommands.route` calls `navigation.open(tab:)`, which changes only
`selectedTab`. The new `MainWindowView` always renders Story and displays
secondary content only from `navigation.sheet`. The command never sets that
sheet. Old Focus/Today/Review destinations are likewise no longer selected by
the main view. The menu-bar Settings action uses this same obsolete path.
Command-comma works because it calls `openSettings()` instead. The Awards link
works because it calls `openSheet(.awards)` directly.

Source: [MainWindowCommands.swift](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/Sources/Surfaces/Main/MainWindowCommands.swift:32),
[MainWindowModel.swift](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/Sources/App/MainWindowModel.swift:177),
[FocusContinuityApp.swift](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/Sources/App/FocusContinuityApp.swift:62).

Required correction: define one route contract for Story scopes and sheets,
connect every menu/popover/shortcut to it, and remove destinations that the
product no longer presents. Searchable History is currently absent from the
production shell despite remaining in source and documentation.

### F04 — P1: Focus headlines reuse tracked-day counts and tracked averages

**Reproduced live.** Month showed “You focused on 2 of 31 days, 50h 57m in
total”, while 17 calendar dates visibly had positive focused time. The Focus
tile's average was about 54 minutes; it was an average of tracked time, not
of the 50h 57m displayed immediately above it. Week had the same issue.

`PeriodSummary.activeDays` and `averagePerActiveDay` intentionally describe
tracked usage. `StoryNarrative`, the Month legend, and the Focus tile reuse
those values as if they described focus. The tracked bars themselves are
still correctly labelled as tracked; the surrounding prose is the mismatch.
For a focus-only period with no app recording, the narrative can even say
“Nothing has been recorded” despite real focus history.

Evidence: [Month](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/.build/design-audit-2026-08-31/11-month-current.png),
[Week](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/.build/design-audit-2026-08-31/10-week-current.png).
Source: [StoryColumns.swift](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/Sources/Surfaces/Story/StoryColumns.swift:138),
[StoryRail.swift](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/Sources/Surfaces/Story/StoryRail.swift:158),
[PeriodStats.swift](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/Sources/Core/PeriodStats.swift:296).

Required correction: maintain separately named focused-day/focused-average and
tracked-day/tracked-average values. Use one measure throughout each sentence,
tile, chart, and legend. Do not change the canonical tracked chart merely to
make a mismatched headline appear consistent.

### F05 — P1: Live focus vanishes when switching from Day to Week or Month

**Confirmed in an isolated runtime probe.** A new session with ten minutes of
work reported `Day = 600 seconds`, `Week = 0`, and `Month cell = 0`.

`reviewFocusedSeconds` and the calendar's `dayFacts` sum archived records only.
Day's live total includes the running session. The same work changes value
when the user changes scope until the session is archived.

Source: [SessionStore+Review.swift](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/Sources/App/SessionStore+Review.swift:259),
[SessionStore+Dashboard.swift](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/Sources/App/SessionStore+Dashboard.swift:230).

Required correction: use the canonical running contribution in all scopes
that contain today, with the same local-day clipping and thread counting.

### F06 — P1: “On this Mac” includes unrecorded time and uses an incorrect period split

**Reproduced live and traced.** The Day headline said approximately 27 minutes
on the Mac, while the rail said 7h 11m. Month said 93h “On this Mac” although
recorded app use was about 1h 48m. These are snapshots of live values, so the
tracked tail advanced during the audit.

There are two independent problems:

- The tile displays `tracked + unrecordedFocusSeconds` under an observed-use
  title. Unrecorded time cannot establish that the user was on the Mac.
- For Week/Month, the split uses `focusedSeconds / trackedSeconds` rather than
  the actual session/usage intersection. If recorded focus exceeds tracked
  usage, every tracked minute becomes “In a focus session”, including usage
  outside any session. The Day/Week captures showed this split changing for
  the same current-day evidence.

There is also a definition mismatch in the new unrecorded field: it subtracts
usage from merged start/end spans, which can contain paused time. The current
session's own detail said 2h 32m had no app recording, while the rail said
6h 43m of “Focused time no app recording covers”.

Source: [StoryRail.swift](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/Sources/Surfaces/Story/StoryRail.swift:173),
[period split](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/Sources/Surfaces/Story/StoryRail.swift:248),
[DashboardStats.swift](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/Sources/Core/DashboardStats.swift:420).

Required correction: keep the tile headline equal to observed tracked time;
show missing coverage as a separate qualification. Calculate inside/outside
usage by intersection. Define coverage against credited work or explicitly
label elapsed span coverage; never conflate the two.

### F07 — P1: Rename and Change type do nothing for a fresh running session

**Confirmed in an isolated runtime probe.** A first running session had zero
archived records. Calling its real store correction methods left the original
name and `.deepWork` type unchanged.

Both methods return early unless a matching archived thread was changed.
Only after that guard do they update the running engine. A brand-new running
thread has no archived row, so the visible controls silently fail.

Source: [SessionStore+History.swift](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/Sources/App/SessionStore+History.swift:516).

Required correction: treat active-session and archived-thread updates as
separate applicable operations, and refresh when either changes. Explain the
scope of a thread-wide correction. Changing a record to Break currently also
removes its editing controls because rest rows are inert; provide a reversible
correction path or Undo.

### F08 — P1: A failed correction write still reports success

**Confirmed in an isolated blocked-storage probe.** `rename` returned `true`
and showed the changed name in memory; after restoring the test storage and
reloading, the name was still `Original`.

The archive mutates its cache before saving. `save()` catches the write error
and logs it, but returns no failure. The correction therefore has no durable
success contract, rollback, or user-visible retry/error state.

Source: [SessionArchive.swift](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/Sources/Core/SessionArchive.swift:52),
[save](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/Sources/Core/SessionArchive.swift:99).

Required correction: commit the in-memory edit only after the atomic write
succeeds, or retain an explicit pending correction with visible failure and
retry semantics. “Save” must mean durable success.

### F09 — P1: Historical qualifications are lost in the new period surfaces

**Confirmed in source.** The old Review view renders `reviewIntegrityNote`;
the new Week/Month Story columns do not. Day moves its legacy-usage note below
the story, after the headline and rail figures have already made their claims.
Settings still promises that pre-epoch app-use patterns remain qualified.

Source: [StoryColumns.swift](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/Sources/Surfaces/Story/StoryColumns.swift:69),
[ReviewView.swift](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/Sources/Surfaces/Review/ReviewView.swift:120).

Required correction: retain the existing accuracy notice before the affected
day/period claims. A new surface must preserve the old evidence boundary.

## Interaction and visual findings

### F10 — P2: System appearance still fails after an explicit appearance

**Reproduced live.** Light worked. Selecting System afterward left the window
light after settling, while the read-only global macOS appearance preference
was `Dark`. Explicit Dark worked again and was restored.

Evidence: [System selected while the app remains light](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/.build/design-audit-2026-08-31/26-system-after-settle.png).

The earlier test proves `NSApp.appearance` becomes nil, not that a SwiftUI
window's retained appearance override has cleared. That earlier completion
claim was too strong. Verify the actual host window and its effective
appearance through Light → System and Dark → System, including already-open
windows and the popover.

### F11 — P2: The preferences sheet is oversized and its sidebar is unreachable

**Observed live and confirmed in layout constraints.** The reference sheet is
520 CSS points wide and content-sized. Production allows a 900-point sheet
and stretches it to the full available height. A single preference occupies
the top of an otherwise empty panel.

Settings chooses its sidebar only at 1,080 points, but the containing sheet is
capped at 900. The sidebar branch is therefore unreachable in the current
production shell, regardless of how wide the parent window becomes. The old
480-point search strip, small category menu, large page heading, and nested
card all remain, combining two incompatible settings layouts.

Source: [StorySheet](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/Sources/Surfaces/Main/MainWindowView.swift:156),
[SettingsView.swift](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/Sources/Surfaces/Settings/SettingsView.swift:6).
Evidence: [reference sheet](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/.build/design-audit-2026-08-31/reference-settings.png),
[actual sheet](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/.build/design-audit-2026-08-31/01-settings-initial.png).

Choose a single approved settings structure: the final prototype's compact
grouped sheet, or the previously discussed continuous preferences document.
Do not retain a dead sidebar inside a full-height imitation sheet.

### F12 — P2: The custom sheet does not provide reliable native keyboard behaviour

**Reproduced live.** Escape failed to dismiss both Settings and Awards; Return
activated Done and dismissed them. Opening inline Rename also left keyboard
focus on the unrelated Awards control rather than entering the name field.

The overlay applies an accessibility modal trait but leaves the parent chrome
usable and does not establish a dependable focus/dismissal boundary. Apple's
macOS sheet guidance describes a modal experience that blocks interaction with
the parent until dismissal; a nonmodal companion is better represented as a
panel. [Apple sheet guidance](https://developer.apple.com/design/human-interface-guidelines/sheets).

Required correction: use native presentation/focus behaviour or fully implement
the equivalent focus containment, Escape cancellation, focus restoration, and
parent-control policy. Styling alone does not make an overlay a native sheet.

### F13 — P2: Calendar intensity and legibility do not match their labels

The calendar contains the requested date, focused duration, and uniform rows.
That part works. However:

- Intensity is clamped to `focused / current daily goal`, so a 1h goal gives
  the same maximum colour to roughly 1h and 8h days. “Darker cells mean more
  focused time” is not true beyond the goal.
- It uses raw focused time although the actual goal ring uses focused-active
  time. It cannot honestly be presented as the same goal-progress scale.
- The reference shows square cells; production fixes height at 58 points.
  At comfortable widths this makes wide, short cells and reduces the calendar's
  intended visual weight. A fixed height is a possible adaptation, but not an
  exact implementation of the supplied geometry.
- White text starts at opacity 0.55. With the shipped light indigo over white,
  that is approximately **2.26:1** contrast. White on the full dark indigo is
  approximately **3.44:1**. These small date/duration labels are below the
  **4.5:1** normal-text benchmark. The ratios were calculated from source
  colours, not anti-aliased screenshot pixels. [W3C contrast guidance](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html).

Source: [MonthStoryGrid.swift](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/Sources/Surfaces/Story/MonthStoryGrid.swift:150),
[palette](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/Sources/Design/DesignTokens.swift:245).

Required correction: explicitly choose a focus-duration heatmap or
focused-active goal progress, make its legend literal, and derive foreground
contrast from the resolved fill. Keep date and duration readable at minimum
and comfortable widths.

### F14 — P2: Some visible controls or promises have no production destination

- The rail's app rows have no `onRow` callback. They cannot open app details,
  despite the reference's description of tiles with drill-ins.
- “Sessions per app” still describes the old Today inspector. The new Story
  app rows do not use it. “Show timeline labels” likewise targets the removed
  horizontal ribbon, not the production Story chronology.
- The main window offers Start and Pause/Resume but no direct End session or
  Away action. The reference's running entry includes End session. Those
  operational controls remain in the popover, so the main window cannot finish
  the workflow it starts.
- During an unresolved absence, the chrome's binary idle/otherwise control
  still advertises Pause/running. The store correctly rejects ordinary
  mutations, but the UI should lead to the pending decision instead of
  advertising a no-op.
- The rail footer says tiles follow the selected scope, yet July's empty
  period still shows today's two-day streak. Focus/Mac zero tiles also remain
  despite the blanket claim that empty tiles are hidden.

Source: [StoryRail.swift](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/Sources/Surfaces/Story/StoryRail.swift:287),
[StoryChromeBar.swift](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/Sources/Surfaces/Main/StoryChromeBar.swift:111),
[SettingsGroups.swift](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/Sources/Surfaces/Settings/SettingsGroups.swift:141).

Required correction: map each visible control and promise to a real consumer.
Remove obsolete controls, provide the missing destination/action, or qualify
scope explicitly. Keep the existing unresolved-decision safety guards.

### F15 — P2: The Story does not yet represent a complete day

`DayStory` renders session and named-rest entries plus the currently pending
absence. It does not represent ordinary unrecorded gaps or an app-use-only
day. Consequently, a day with tracked use but no focus session can say
“Nothing recorded on this day yet” while the rail reports activity.

The Day subtitle also calls the longest thread total the “longest stretch”.
The live day showed 2h 53m as its longest stretch although that session had
two stretches; Week reported a longest stretch of 1h 50m. These are different
definitions under the same label.

Source: [DayStory.swift](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/Sources/Surfaces/Today/DayStory.swift:45),
[StoryColumns.swift](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/Sources/Surfaces/Story/StoryColumns.swift:111).

Required correction: distinguish “no focus sessions” from “no recording”,
represent missing coverage without inventing activity, and use session/thread
versus stretch terminology consistently.

### F16 — P2: Snapshot and documentation coverage no longer describes the product

The fresh build passed **196/196** tests and wrote **126/126** snapshots.
Those counts do not establish the advertised product coverage:

- `reviewHistorySelection` renders a Day story, not History, because the shell
  ignores the old selected tab. Other legacy scenarios have the same problem.
- The minimum awaiting-decision render clips the top chrome/headline and shows
  a native-control placeholder. It is not clean visual evidence of a usable
  window. This is a render-harness finding; it is not proof that the real
  scrolling window has the same clipping.
- Static fixtures do not exercise an actual menu route, period selection
  change, System appearance reset, or disk failure after an edit.
- README still documents five tabs, the old shortcuts, the ribbon, and
  `Open in Today`. These are no longer the current main-window experience.

Evidence: [History-named snapshot showing Day](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/.build/design-audit-2026-08-31/reviewHistorySelection-minimum-light.png),
[clipped pending-decision snapshot](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/.build/design-audit-2026-08-31/focusAwaitingDecision-minimum-dark.png).
Source: [Snapshotter.swift](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/Sources/Surfaces/Snapshotter.swift:386),
[README.md](/Users/prabeshbhetwal/Desktop/Files/Development/Project/FocusContinuity/README.md:20).

Required correction: verify actual destinations and visible content, rename or
retire stale scenarios, and include real-window interaction checks. Retain the
existing accounting and persistence tests; add the missing integration coverage.

## Why the visual language feels close, but not finished

The comparison below excludes the browser prototype's decorative page frame.
CSS points and native layout points are compared as design measures; literal
pixel equality is not claimed across different viewports, fonts, or content.

| Element | Final reference | Current native implementation | Effect |
|---|---|---|---|
| Story base | Warm `#fbfaf8`; white entry cards | `Tokens.surface` is white in light mode and `#2C2C2E` in dark | Cards lose the reference's subtle surface separation; the base feels different. |
| Rail base | Very light neutral overlay on the warm base | Cool `#F2F2F7` / `#1C1C1E` | The split reads more like two unrelated sheets than one softly differentiated window. |
| Story inset | 26 top, 30 sides, 34 bottom | 32 on every side | A small but systematic rhythm difference. |
| Headline | 25-point semibold, 560-point maximum measure | 23-point semibold, 620-point maximum | The lead loses weight while lines run longer. The long raw summary text compounds this. |
| Focus emphasis | Indigo `#4e4ccc` / `#5E5CE6` | General focus/selection uses system-blue hex values | The reference separates focus identity from generic actions more clearly. |
| Scope control | Rounded rectangle, white selected thumb, dark text | Blue selected capsule | Recognisable scope control, but a visibly different component. |
| Session card | 13-point radius, 13 × 15 padding, fine shadow and hairline | 12-point radius, 12-point padding, plain border | Flatter and more compressed than the reference. |
| Expanded entry | Apps and “Shape of it” alongside each other | Tall app rows followed by prose below | More vertical bulk and less deliberate internal hierarchy. |
| App rows | App and duration on one line, thin full-width bar below | Icon/name, duration on a second line, 90-point bar beside it; 44-point row floor | The rail becomes disproportionately tall and names truncate earlier. |
| Rail tiles | 14-point radius, 15 × 16 padding, 14-point gap, subtle elevation | 16-point radius/padding, 12-point gap, flat stroke | Close in outline, noticeably different in density and depth. |
| Month cells | Square at the available width | Fixed 58-point height | The calendar looks compressed at comfortable window widths. |
| Settings | Compact 520-point content-sized grouped sheet | Up-to-900-point full-height sheet with legacy page anatomy | The clearest spacing and structural mismatch. |
| Motion | Specific entry stagger, hover lift, live emphasis, moving scope thumb | Some transition curves exist; several described effects are not connected to the new components | Declaring motion tokens alone does not reproduce the reference. Pointer animation quality was not verified live. |

Use the reference's measured proportions as the starting point, then make
explicit, documented adaptations for macOS accessibility, actual data volume,
and minimum window size. Do not apply one generic `SurfacePanel`/`AppUsageRow`
to every new component merely because it compiles and looks approximately
similar.

## What is working and should be retained

- The Story/rail composition and persistent Day/Week/Month scope are recognisable.
- The month grid displays dates, focused durations, consistent row heights,
  and week totals. Selection itself works.
- Session entries expand inline. Rename and Change type editors open; Cancel
  and Done return to the entry without applying a correction.
- Settings search found all eight groups using visible labels and produced a
  useful no-results state. Command-comma and the Done button work.
- Explicit Light and Dark work. Compact density visibly reduces Settings
  spacing. Original Dark and Comfortable values were restored and read back.
- The Awards link opens its sheet. Earned and unearned cards have distinct
  states and evidence disclosures.
- Existing build, ordinary local signature verification, staged strict
  verification, and the headless suite passed.
- Avoiding fabricated iCloud sync, people counts, detailed typing claims,
  and arbitrary Week/Month goal rings is appropriate. Those prototype details
  need product evidence before implementation.

## Coverage and limits

| Area | What was checked | Limit |
|---|---|---|
| Primary reference | Source and browser renders of Day, Week, Month, Settings; inline state handlers | Other exported directions were identified as alternatives, not treated as simultaneous visual targets. |
| Day | Headline/rail, inline expansion, Rename open/cancel, Change type open/close, scope transitions | No live Rename save, reclassification, continuation, or new session was performed. |
| Week/Month | Selection, historic drill-in, previous month, stale selection, totals, calendar geometry | No destructive action; the absence of live focus was tested separately in a fixture. |
| Settings | Every group via search, no results, Light → System → Dark, Compact → Comfortable, keyboard dismissal | Recording/automation/goal settings were inspected and traced, not toggled against live history. |
| Awards | Live opening, earned/progress layout, dismissal attempt; source and fixtures | No live award-triggering activity. |
| Insights | Shortcut failure reproduced; source and rendered sufficient/insufficient-data fixtures inspected | The production shortcut prevents a complete live Insights walkthrough. |
| History | Unreachable production route identified; source and misleading snapshot checked | Cannot honestly call a hidden destination fully exercised live. |
| Focus/popover/away | Source action paths, existing isolated tests, generated state snapshots | Did not force a real sleep, lock, pending decision, stop, or notification. |
| Corrections | Fresh-running edits, blocked durable writes, live scope totals in isolated fixtures | All probe storage and defaults were separate from user history. |
| Pointer/drag | Source and tile-order tests | Computer Use pointer calls repeatedly closed the native automation pipe. Keyboard traversal worked. Drag-reorder and hover animation are not certified. |
| Accessibility | Actual keyboard routes, focus behaviour, AX labels, source-colour contrast calculations | Not a complete VoiceOver, Increase Contrast, Reduce Motion, or multi-display certification. |
| Performance | Source flow and normal walkthrough | No Instruments/frame-time or maximum-capacity profiling; “flawless smoothness” is not established. |

The Mac locked during the final attempt to restore the initial browsing
location, so UI interaction stopped. Dark and Comfortable preference values
were confirmed restored through read-only preference checks. Navigation may
remain at the last inspected period. No live session names, types, archives,
tracking settings, or goals were edited.

## Recommended correction sequence

1. **Repair the real routes and selection scope:** F01–F03. Add tests that
   assert the selected day reaches the store and visible content.
2. **Reconcile the measurements:** F04–F06, F09 and the goal/longest labels.
   Specify each measure once and consume it consistently.
3. **Make corrections reliable and reversible:** F07–F08. Test first-ever
   running work and real write failures, not only archived happy paths.
4. **Repair native interaction contracts:** System appearance, modal focus,
   Escape, running controls, and obsolete settings consumers.
5. **Tune fidelity with matched viewports and fixtures:** restore the approved
   surface hierarchy, type measures, compact app bars, entry columns, calendar
   proportions, and settings sizing. Check contrast before choosing foregrounds.
6. **Replace misleading coverage claims:** update scenario routing and README;
   rerun real-window workflows as well as static rendering.

No source implementation, commit, push, or local app promotion was performed
during this audit. This report is the only added review document; evidence
artefacts are under ignored `.build/`. The pre-existing untracked research
bundle and PDF were left untouched. That bundle contains an old app and source
copy, so it should be curated before any later commit rather than added wholesale.
