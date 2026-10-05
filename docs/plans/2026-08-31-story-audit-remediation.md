# Story audit remediation

Date: 31 August 2026

Baseline: `13a1cf3`

Status: implemented and locally verified; not pushed. See the
[verification report](../reviews/2026-08-31-story-remediation-verification.md)
for results and manual-verification limits.

Authority: the user's approval to fix all findings in `docs/reviews/2026-08-31-design-and-behaviour-audit.md`.

## Direction and constraints

Retain the supplied **Day as a Story** composition. Correct its implementation;
do not introduce another design direction. The final Story HTML in the research
handoff is the visual reference, not the alternative prototypes or their sample
facts. Operational correctness takes precedence over copying unsupported mock data.

- Work in the original main checkout. Do not push or publish.
- Preserve macOS 13, direct Swift compilation, one repeating ticker, and Core →
  App → Surfaces boundaries. No packages, services, permissions, or fabricated data.
- Tests use suite-scoped preferences and temporary archives, never live history.
- App-use history and its accuracy epoch remain unchanged. A user-requested focus
  correction must be durable, scoped, visible, and reversible.
- Focused time, tracked time, and goal credit are separate measures. Period bars
  remain exact tracked time. Missing recording is not observed Mac use.
- Australian English; preserve accessible labels, keyboard operation, reduced
  motion, and readable contrast in light and dark appearances.
- Keep user research additions out of commits. Commit only scoped project work
  after its acceptance checks; promote a fresh local app only after verification.

## Execution and ownership

Focused implementers handle accounting, correction persistence, and preferences;
the controller integrates navigation, native presentation, and the visual surface.
Only one implementation subagent runs at once. They do not spawn more agents.
Each focused task receives an independent spec/quality review; the final review
covers the complete integrated change. The controller owns `SelfTest.swift` and
integrates new test groups, avoiding shared-file edits while implementers work.

### Task 1: Canonical Story accounting

**Addresses:** F04, F05, F06 and the measurement portion of F15.

**Own:** new `Sources/App/SessionStore+Story.swift`,
`Sources/App/SessionStore+Review.swift`,
`Sources/App/SessionStore+Dashboard.swift`, and new
`Sources/Verification/StoryAccountingChecks.swift`. A small pure helper under
Core is allowed if it materially avoids duplication. Do not modify Story views,
navigation, `SessionStore.swift`, `SessionStore+History.swift`, or SelfTest.

1. Add regression checks using real temporary stores: a ten-minute running
   session contributes equally to Day, Week and its Month cell; focus-only days
   count towards focus averages with no app recording; a mixed inside/outside
   usage fixture reconciles across scopes; paused span time never becomes
   observed Mac use or credited focus coverage; cross-midnight running work is
   clipped by local calendar boundaries and session counts deduplicate threads.
2. Introduce clearly named Story-focused period statistics, independent of
   `PeriodSummary.activeDays` / `averagePerActiveDay` (which remain tracked).
   Expose `storyFocusedSeconds(on:)`, `storySessionCount(on:)`, and
   `storyFocusSummary` with `focused`, `activeDays`, `averagePerActiveDay`,
   `longestStretch`, and `longestName`. Use the canonical running contribution.
3. Expose `storyUsageBreakdown(in:)` and `storyUsageBreakdown` for the current
   day/Review period. Values: `tracked`, `insideSessions`, `outsideSessions`,
   `uncoveredFocus`. Tracked is exact observed app use; inside/outside are
   intersections, not focus/tracked ratios. Credited focus without app coverage
   is separate, computed using FocusedActiveTime and bounded by credited work.
4. Include running focus in Review entries/totals/best day/longest, calendar facts,
   and History's canonical current-day row where appropriate. Retain true
   archive identities and never append a synthetic running record to storage.
5. Expose tests as `StoryAccountingChecks.tests: [(String, () -> [String])]`;
   controller registers them. Provide a focused temporary executable harness if
   needed for RED/GREEN. Report exact commands/results and interface decisions.

### Task 2: Route the real Story and restore working destinations

**Addresses:** F01, F02, F03, navigation portion of F14.

**Own (controller):** MainWindowModel, MainWindowCommands, MainWindowView,
StoryChromeBar, StoryColumns, DaybookApp, relevant routing checks.

Unify menu, popover, keyboard and on-screen routes. Opening a historical story
must select its canonical store date before showing Day. Period changes clear
unavailable selections. Expose actual Day/Week/Month destinations and searchable
History, Insights, Awards and Settings; retain a reachable Focus control surface
for intent, work type, Stop and away decisions. Tests exercise store data as well
as navigation state and cover already-open windows and repeated same-day routes.

### Task 3: Durable and reversible focus corrections

**Addresses:** F07 and F08.

**Own:** SessionArchive, SessionEngine correction methods,
SessionStore+History correction methods; new narrow correction state/helper and
`Sources/Verification/StoryCorrectionChecks.swift`. Coordinate any new published
SessionStore properties with controller. No UI edits or SelfTest edits.

Test fresh running rename/type changes without archived records; a resumed thread
updates both active and archived parts; no-op operations are honest; blocked
storage leaves the old archive/cache intact and returns visible failure; an undo
restores the affected thread after conversion to Break. Write candidate archives
atomically before publishing changes. Keep existing Bool entry points compatible
where possible, expose correction error/undo availability to the UI, and never
claim a saved correction if writing failed. Scope is the whole named thread,
which the UI will disclose. Tests expose `StoryCorrectionChecks.tests`.

### Task 4: Backed preferences and native appearance

**Addresses:** F10, F11 and settings portion of F14.

**Own:** SettingsView, SettingsSidebar, SettingsGroups, SettingsSection metadata,
SettingsModel, plus a small AppKit appearance helper if needed. Coordinate
MainWindowModel/DaybookApp/AppCoordinator edits with controller.

Make preferences a compact, bounded sheet matching the reference's five groups:
General (general + appearance), Sessions (focus + automatic), Away & Breaks,
Recording (tracking), Privacy (data + advanced). Preserve every backed control.
Search belongs to the preferences header and shows matching settings with clear
group context; no unreachable wide sidebar inside a narrower sheet. Long
diagnostics wrap, scroll, and remain selectable. Appearance must inherit macOS
after Light → System and Dark → System, clearing host/window overrides, not
merely asserting NSApp.appearance == nil. Production SwiftUI preferredColorScheme
overrides will be removed by controller; snapshot-only overrides remain explicit.
Update search terms for actual controls; no inert settings. Report observable
verification and expose any tests as `StorySettingsChecks.tests`.

### Task 5: Reference fidelity, useful detail and complete-day evidence

**Addresses:** F09, F12, F13, F14, F15 and visual comparison table.

**Own (controller):** Story views, scoped Story design tokens, native sheet
presentation, app/entry detail components, operational controls.

- Warm `#fbfaf8` Story canvas, white cards, neutral rail; 336pt rail, 26/30/34pt
  column insets and 22/20/30pt rail insets. Heading 25pt/max560; indigo focus
  identity separate from blue action. Rounded-rectangle scope selector with a
  neutral selected thumb, not a blue capsule.
- Cards radius13, 13×15pt insets; rail tiles radius14 and 15×16pt insets. Subtle
  hairline/shadow. App title and duration share a line over a thin full-width bar.
  Expanded entry detail uses apps and credited-work coverage beside one another
  when there is room, stacked when narrow. Do not add charts without evidence.
- Put accuracy qualifications before affected figures. Mac headline is tracked
  only; focus, goal credit and uncovered focus are explicitly distinguished.
- Square responsive Month cells, 62pt week total, 8pt gaps; date and duration
  remain. Heat intensity describes focused duration, independent of goal credit;
  foreground must retain 4.5:1 contrast and labels explain selection vs intensity.
- Native modal sheets block the underlying story, Escape dismisses, and focus
  returns predictably. Text-edit focus is immediate; Save failure stays visible.
  Whole-row disclosures and app details are keyboard-operable. Corrections have
  visible Undo, including Break. Honour labels/expanded-entry preferences.
- Reachable Start/Pause/Continue/Stop and away-decision actions; current streak
  explicitly labelled as current, not falsely scoped to a historical month.
- An app-only day describes observed app use, not “nothing recorded”. Display
  honest inter-entry gaps as unrecorded intervals, never fabricated breaks.
  Longest stretch means an actual stretch, not a whole resumed thread.

### Task 6: Verify the integrated app and hand over

**Addresses:** F16 and closure of all findings.

Update snapshot routing so named scenarios show their intended production surface;
add meaningful real-window coverage for history, native sheets, appearance, live
focus, sparse app-only days and full Month grids. Inspect light/dark Day, Week,
Month, Settings, history drill-in and awaiting-decision layouts at minimum and
comfortable widths. A generated PNG is not proof of correct content.

Run `./build.sh --check`, `./build.sh --test`, ordinary local signature verification
and `git diff --check`. Review the integrated diff independently; fix material
findings. Update README to shipped navigation, metrics, corrections, preferences
and architecture. Record verification evidence and any genuine environmental
limits in the audit closure document. Keep generated artefacts ignored; do not
push. Leave the fresh local bundle ready for the user.
