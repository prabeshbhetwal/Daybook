# Complete Story Interactions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. The user has approved implementation; do not ask again between batches.

**Goal:** Implement both approved written specifications, including the repeated End/Continue case, without altering live history during verification.

**Architecture:** One recording engine and one action store supply immutable date-scoped projections. Eligibility, observed activity, correction receipts, optional metadata and app-rule decisions have explicit boundaries. Native controls share actions; no view mutates global dates merely to render historical content.

**Tech Stack:** Swift 5 language mode, SwiftUI/AppKit, Foundation, public IOKit power APIs, direct `swiftc`, macOS 13 minimum. Existing headless SelfTest and native fixture-only verification.

**Spec:** `docs/specs/2026-08-31-story-interaction-model-design.md` and `docs/specs/2026-08-31-session-controls-and-activity-rules-proposal.md`, both approved in chat.

## Global Constraints

- Work in the main project directory. Do not create a worktree or push changes.
- Preserve unrelated user research files. Use native SwiftUI/AppKit, the existing direct `swiftc` build, Swift 5 language mode and the macOS 13 deployment target.
- Do not introduce a service, package, permission request or repeating timer for these interaction changes.
- Use `apply_patch` for file edits. Only commit task-owned files, never `git add -A`.
- Preserve source app-use evidence, local-clock DST handling, presence gating and existing interrupted-save protections.
- Do not launch the production app or copy its executable for automation. Native interaction tests must use `scripts/build-fixture-app.sh`.
- Keep the system font, native appearance, Australian English, Reduce Motion and keyboard/VoiceOver semantics.
- A session is a thread; a continuation is a new stretch in that thread. Never credit a gap automatically or double-count shared-app membership.
- Each task follows a RED/GREEN cycle with independently derived expectations; register focused checks in `SelfTest` and run the complete check before committing.
- No implementation worker spawns subagents. The controller supplies the independent review.

## Verification commands

Full headless build/check: `./build.sh --check`.
Final product build: `./build.sh --test` (do not add `--run`).
Use the existing direct `swiftc` source list for focused test drivers when it saves repeated full builds; keep such drivers under the ignored task workspace. Capture the command and relevant RED/GREEN output in the task report.

## File and interface map

- Continuation policy: a new Foundation-only `Sources/Core/ContinuationPolicy.swift`, consumed by the existing store continuation/start methods and Focus list.
- Recording presentation: a new Foundation-only duration/evidence projection, consumed by `SessionShape`, `SessionStore+StoryDetails` and the session activity view.
- Corrections: current engine/receipt persistence, expanded to entry-scoped receipts; the store's existing mutation boundary and inline rows remain authoritative.
- Date projections: new `Sources/App/StoryDayProjection.swift`; `DayStory` accepts an explicit day while retaining the same store for actions.
- Controls: `MainWindowModel`, chrome, main view, settings, popover and rail; one in-window session strip.
- Session context: new session metadata and power monitor files, plus a note editor and small power label in an entry.
- App rules: new activity definitions, catalog, pure rule detector and native settings editor, integrated through the coordinator/store with one-shot deadlines.

### Task 1: Enforce latest-stretch continuation everywhere

**Files:**
- Create `Sources/Core/ContinuationPolicy.swift` and `Sources/Verification/ContinuationChecks.swift`.
- Modify `Sources/App/SessionStore+History.swift`, `Sources/App/SessionStore.swift`, `Sources/Core/SessionThread.swift`, `Sources/Surfaces/Focus/FocusContinuations.swift`, `Sources/Surfaces/Today/DayStory.swift`, and `Sources/SelfTest.swift` as needed for the shared consumer boundary.

**Interfaces:**
- Consumes existing `SessionRecord`, `DaySession`, `ThreadSummary`, `RunningThread`, engine state and injected `now`.
- Produces `ContinuationPolicy.activityKey(name:workType:) -> String` and `ContinuationPolicy.isEligible(_:records:active:now:) -> Bool`, where the first parameter is a canonical `SessionRecord`, records are `[SessionRecord]`, active is `RunningThread?` and now is `Date`.
- Existing `canContinue`, `continueSession` and `continueThread` remain public call sites, now backed by that policy and a fresh record lookup. Add a separate explicit new-session action for expired entries, not a hidden continuation.

- [ ] **Step 1: Write behavioural RED tests.** Use isolated defaults/archives and an injected clock; initial tests call existing store methods so they fail on actual permissive continuation, not an absent symbol. Reproduce the user's sequence with named Coding records:

```swift
// Literal expected outcomes; time gaps must not become work.
// A: 22:10 to 23:11, worked 3600, thread T.
// Continue A, then B: 23:11 to 23:12, worked 60, thread T.
// Continuing stale A must leave engine idle and records unchanged.
// Continuing B creates C in T. A/B are then ineligible.
// End C; only C may continue, provided its age is <= 3600 seconds.
```

Also test three separate Coding threads, Browsing sharing Deep work, whitespace/case normalisation, 3599/3600/3601-second boundaries, midnight, future timestamps, active and paused ownership, pending absence, a stale thread menu, and starting Browsing while Coding is active.

- [ ] **Step 2: Run RED.** Register `ContinuationChecks.tests`; run `./build.sh --check` and retain the expected eligibility failures.
- [ ] **Step 3: Implement the shared policy and action-boundary checks.** An active activity blocks older entries of that same activity. Resolve the last canonical record for the requested thread and require the displayed stretch to contain that actual last record, so an old row cannot pass merely by sharing a thread. Determine latest activity across the archive, not just the currently viewed day. End dates must satisfy `0 <= now.timeIntervalSince(end) <= 3600`. Use deterministic tie handling and fail closed for a stale/missing source. Filter all continuation lists by the same policy. Start/new-session must not adopt a differently named current activity based on WorkType alone; preserve deliberate adoption of the same activity where appropriate.
- [ ] **Step 4: Run GREEN and self-review.** Confirm session count stays one for T, worked totals are `3600 + 60 + C.workSeconds`, and repeated stale callbacks never start work. Check compatibility with existing correction/continuation tests.
- [ ] **Step 5: Commit** as `fix: enforce latest-stretch continuation at every action boundary` and write the full report with RED/GREEN evidence.

### Task 2: Reconcile short-duration prose and replace ambiguous shape bars

**Files:**
- Create `Sources/Core/RecordedActivity.swift`, `Sources/Core/DurationText.swift`, and `Sources/Verification/RecordedActivityChecks.swift`.
- Modify `Sources/Core/SessionShape.swift`, `Sources/Design/DesignTokens.swift`, `Sources/App/SessionStore+StoryDetails.swift`, `Sources/Surfaces/Story/StoryShapeChart.swift`, `Sources/Surfaces/Today/DayStory.swift`, and registry/fixture checks that consume these contracts.

**Interfaces:**
- `DurationText.precise(_ seconds: TimeInterval) -> String` is Foundation-only; Design delegates its short-duration helper to it.
- `RecordedActivity` produces canonical non-overlapping app/gap intervals for a supplied `[TimelineSegment]` and explicit `[DateInterval]` session spans. Each interval exposes start/end, optional bundle/app identity and recorded duration; total coverage is a union, never a sum of overlaps.
- Extend `StorySessionDetail` with these intervals while preserving any older bins consumers until migrated. `storySessionDetail(_:on:)` accepts an explicit day, defaulting to the selected day only at the wrapper, for Task 4.

- [ ] **Step 1: Add RED cases with literal expectations.** `SessionShape.paragraph` on a 31-second ChatGPT segment must contain `31s`, not `0m`; 0.4 seconds is `<1s`. An actual zero Finder segment must not introduce a second app or app-switch claim. Duplicated `[0,30]` and `[10,40]` intervals have coverage 40, not 60. A `[10,20]` run inside `[0,30]` leaves two visibly distinct unknown gaps. Missing recording never implies rest.
- [ ] **Step 2: Run the new checks before implementation** and preserve the observed formatter/coverage failures.
- [ ] **Step 3: Implement canonical projection, shared precision and chart.** Resolve conflicting overlaps deterministically without inventing simultaneous foreground use; use stable ordering and preserve a coverage limitation if evidence conflicts. Clip to session spans before totalling. For finite short observations:

```swift
if seconds > 0 && seconds < 1 { return "<1s" }
// Under one minute, display whole seconds; longer values retain existing h/m style.
// Non-finite, negative and unrepresentable values never reach an unsafe Int conversion.
```

Render **App activity** as a compact time-proportional strip with actual app colours, start/end labels, named gap styling and keyboard/hover details. For sessions under two minutes, or no evidence, prefer the factual caption and no empty decorative chart. App ranks and captions consume the same clipped evidence. Keep the app-list cap, meeting evidence and live controls; remove contradictory repeated empty messages. Change physiological `rest` claims on named break entries to recorded-break language.
- [ ] **Step 4: Run GREEN, existing accounting tests and fixture renders.** Include the 31-second example, fully recorded 48-minute session, partial coverage, no recording, gaps, and colour/keyboard equivalents.
- [ ] **Step 5: Commit** as `fix: make session activity and duration descriptions factual` and report evidence.

### Task 3: Persist and target multiple reversible entry decisions

**Files:**
- Modify `Sources/Core/SessionEngine.swift`, `Sources/Core/PersistenceStore.swift`, the persisted-state/away-receipt definitions, `Sources/Core/SessionCorrection.swift`, `Sources/App/SessionCorrectionState.swift`, `Sources/App/SessionStore.swift`, `Sources/App/SessionStore+History.swift`, `Sources/App/SessionStore+StoryDetails.swift`, `Sources/Surfaces/Story/StoryDecisionRow.swift`, `Sources/Surfaces/Today/DayStory.swift` and existing correction checks.
- Create focused files for the durable correction collection and `Sources/Verification/DecisionHistoryChecks.swift` if needed to avoid enlarging unrelated engine methods.

**Interfaces:**
- Engine exposes `awayDecisions: [AwayDecisionReceipt]` and lookup by UUID. Preserve `lastAwayDecision` as a compatibility/latest-selection projection.
- `undoAwayDecision(expectedID:)` and historical re-answer identify the requested receipt; a default latest action remains available for existing global Undo.
- Persist field corrections by stable identity too; expose per-entry undo/correction actions through the store. Receipt data never includes mutable session notes.

- [ ] **Step 1: Write RED integration tests.** Resolve two distinct absences, undo the first after resolving the second, and assert the second receipt and all later work survive. Relaunch from persisted state and repeat. Rename a different thread, then undo the older break. Test original interval recovery, archive capacity, stale Retry and interrupted save using the existing failure-injection conventions. Existing single-receipt tests remain mandatory.
- [ ] **Step 2: Run RED** and record the first receipt being unavailable, not an unrelated setup failure.
- [ ] **Step 3: Implement entry-scoped persistence/migration.** Migrate the old single receipt with its ID unchanged; keep each operation's recovery phase and exact-record preconditions. Update only the chosen receipt, never replace newer records with a snapshot. Multiple credited decisions on one archived record must subtract each exact contribution once and remain retryable after an interrupted write. Protect unrelated edits with field-specific compare-and-apply checks. Do not silently discard history during migration.

Render every eligible receipt at its original interval, de-duplicate its break row, and give that row its own Undo/re-answer. Legacy break rows without original receipts expose **Change classification**; **Leave uncounted** is a recoverable classification change, while focus attribution requires an explicit target and scope. If no valid focus target exists, explain that and retain the uncounted option. Preserve source app usage. Purge correction metadata only with its corresponding explicit history erasure/retention boundary.
- [ ] **Step 4: Run GREEN**, including interrupted initial answer, interrupted historical re-answer, interrupted Undo, multiple credits, later edits, cross-day disclosure, migration and all original safety checks.
- [ ] **Step 5: Commit** as `feat: retain reversible decisions on their recorded entries` and report recovery evidence.

### Task 4: Inline historical stories and date-scoped reading workspaces

**Files:**
- Create `Sources/App/StoryDayProjection.swift` and `Sources/Verification/StoryWorkspaceChecks.swift`.
- Modify `Sources/App/MainWindowModel.swift`, `Sources/App/SessionStore+Story.swift`, `Sources/App/SessionStore+Review.swift`, `Sources/App/SessionStore+StoryDetails.swift`, `Sources/App/SessionStore+Summary.swift`, `Sources/App/SessionStore+Insights.swift`, `Sources/Surfaces/Story/StoryColumns.swift`, `Sources/Surfaces/Today/DayStory.swift`, `Sources/Surfaces/Insights/InsightsView.swift`, `Sources/Surfaces/Review/HistoryView.swift`, `Sources/Surfaces/Main/MainWindowView.swift`, `Sources/Surfaces/Main/StoryChromeBar.swift` and commands.

**Interfaces:**
- `StoryDayProjection` is a value with explicit date, chronology, factual summary, focus/usage totals and session details. It never owns a SessionEngine/SessionStore.
- Store provides `storyTimelineItems(on:)`, `storySessionDetail(_:on:)` and day summaries independent of `selectedDay`. Keep convenience wrappers for existing callers.
- Model owns expanded period-day state separately from the period anchor. Insights owns its own scope/anchor. Main window can present Story, History or Insights in its existing content region; Settings remains an attached panel.

- [ ] **Step 1: Add RED navigation/projection tests.** Opening a week/month child leaves `storyScope`, `reviewAnchor`, Day selection and parent totals unchanged; projected day facts match hand-seeded records. Selecting another day updates just the child. Step period clears incompatible selection. Insights scopes and History drill-in never mutate Story's last date or running engine.
- [ ] **Step 2: Observe RED** against current `openStoryDay` routing and selected-day-only details.
- [ ] **Step 3: Implement date projections and in-place reading.** Week/Month **Open as a story** becomes **Hide story** when expanded. Use the same action store and Task 3 receipts without constructing a second store or temporarily changing dates. Place **About this day** before Day chronology and generate a small factual bullet list without duplicating the headline.

Insights exposes Day/Week/Month regardless of current evidence. Show newest-first dated factual summaries, mark current periods **so far**, and limit initial history to a useful bounded page with an explicit earlier-period action. Reuse evidence gates for actual pattern claims; no complete-period comparison against a partial period without qualification. History stays date-first/searchable and expands the selected story in place. Keep existing History/Insights entry commands and a clear return-to-Story action. Preserve reading position using stable IDs, not rebuilding the source store.
- [ ] **Step 4: Run GREEN**, original navigation/accounting tests and render Day, Week child, Month child, History detail and all three Insights scopes with sparse/dense evidence.
- [ ] **Step 5: Commit** as `feat: keep historical stories and insights in their reading context` and report.

### Task 5: Compact native controls, stable Settings and deliberate arranging

**Files:**
- Create `Sources/Surfaces/Main/SessionControlStrip.swift`, a native scope-control adapter if needed, and `Sources/Verification/CompactControlsChecks.swift`.
- Modify model/settings preferences, `StoryChromeBar.swift`, `MainWindowView.swift`, commands, `PopoverMetrics.swift`, `PopoverView.swift`, `HeroCard.swift`, `FocusHero.swift`, `SettingsView.swift`, `StoryRail.swift`, `MonthStoryGrid.swift`, motion/style components and associated fixtures.

**Interfaces:**
- Model owns session-strip expansion; settings persists pinning only. `open(.focus)` reveals in-window controls rather than a Focus sheet. Commands and toolbar route to the same method.
- Scope control retains `Binding<StoryScope>` and exposes native/keyboard selected state with one coherent focus target.
- Rail's arranging state gates drag/drop and keyboard moves; existing `storyTileOrder` persists order.

- [ ] **Step 1: Add RED state/layout contract tests.** Opening controls changes neither period nor sheet; pin survives relaunch without starting a timer; settings pages/search have one frame; menu panel remains single-column on large/small displays; ordinary rail mode rejects drag actions and arranging mode moves exactly one item. Test smallest/wide month layout bounds behaviour rather than only asserting a constant.
- [ ] **Step 2: Observe RED** for the current Focus-sheet route, variable Settings frame and wide popover.
- [ ] **Step 3: Implement controls.** Target 340-point menu width, clamped to usable display space, content-driven height, one quiet goal line and only eligible continuations. Use at most one scroll region for real overflow. The session strip opens below chrome and can be pinned; no extra app window. Keep existing safe away-answer/error actions.

Use a native segmented-control adapter or equally accessible roving focus implementation for Day/Week/Month. Suppress the unmanaged blue outer ring only here; provide an integrated keyboard-focus cue and Left/Right/Home/End behaviour without disabling focus. Settings uses one bounded frame (maximum 600 points including title band, adapted to available main-window height); normal pages fit through group layout/spacing, not tiny fonts. Header close uses X with Escape and a scoped close command, restoring focus. Month cell height is bounded independently of width (start at 54 points and verify at both widths); retain weekly totals and readable dates/durations. Add one Arrange cards group button, enabled drag/drop only in arranging mode, keyboard moves, reset and Finish/Escape. Keep restrained 150–250 ms feedback with Reduce Motion equivalents.
- [ ] **Step 4: Run GREEN and isolated native fixture checks.** Verify no new Focus sheet on timer activation, pin/unpin, closing, keyboard scope movement, settings category/search sizes, six-row month and actual rail reorder. Record pointer/VoiceOver limitations separately.
- [ ] **Step 5: Commit** as `feat: streamline session controls and compact native layouts` and report.

### Task 6: Add subtle notes and recorded power context safely

**Files:**
- Create `Sources/Core/SessionMetadata.swift`, `Sources/Core/SessionMetadataArchive.swift`, `Sources/App/PowerSourceMonitor.swift`, `Sources/App/SessionStore+Metadata.swift`, `Sources/Surfaces/Story/SessionNoteEditor.swift`, and `Sources/Verification/SessionMetadataChecks.swift`.
- Modify `SessionEngine` only to expose stable current stretch identity/boundary hooks where necessary, coordinator/store injection, `DayStory.swift`, metadata retention/data-folder disclosure, and fixture factory. There is no existing export/erase UI; do not create an unrequested destructive workflow.

**Interfaces:**
- `SessionMetadata` keyed by stable recorded-stretch UUID, with optional note and ordered `PowerObservation` values. Absence of metadata means unknown, not a current-system fallback.
- `PowerObservation` has timestamp, source (battery/external/UPS/unknown), optional percentage, charging state and coverage boundary where appropriate. `PowerSourceMonitor` is injected and not constructed in fixtures.
- Store note API saves by record ID with a visible result/error and retained draft; power summary accepts the entry's own interval.

- [ ] **Step 1: Write RED metadata tests.** Save/reload one stretch note, continue to another stretch without duplicating it, edit note then Undo classification, simulate failed save with draft retained, and prove that copying/removing the complete fixture data directory includes its metadata. Use literal battery samples 78→64 and charging 64→81; an old/no-battery fixture must not display current power state. Test mixed sources, unknown percentage, resume gaps and invalid capacity values.
- [ ] **Step 2: Run RED** at the new archive/consumer boundary with only the minimal compiling model surface.
- [ ] **Step 3: Implement atomic compatible metadata and UI.** Prefer a sidecar keyed by stable IDs so note edits do not change exact-record Undo checks. Match the archive's directory and retention/erasure guarantees. A running stretch must keep the same metadata identity when archived. Add local plain-text Add note/Save/Cancel with Command-Return, native editing shortcuts and guarded dismissal; preserve unsaved text through collapse/navigation and show storage errors. No empty note area on ordinary entries.

Use public `IOPSCopyPowerSourcesInfo`, `IOPSCopyPowerSourcesList`, `IOPSGetPowerSourceDescription` and change notification APIs; sample only boundaries/events, never add a polling loop. Distinguish plugged-in from charging, handle no internal battery, clamp valid percent derived from capacity/max, and never backfill historic sessions. Display a small secondary power line under duration and expand mixed/partial context on request. Do not claim battery change is app energy consumption.
- [ ] **Step 4: Run GREEN**, migration/retention/data-folder portability, failure and fixture renders. Ensure the fixture-only app neither starts a live power monitor nor writes real metadata.
- [ ] **Step 5: Commit** as `feat: add local session notes and observed power context` and report.

### Task 7: User-owned activity rules, installed-app picker and honest automation

**Files:**
- Create `Sources/Core/ActivityRule.swift`, `Sources/Core/ActivityRuleDetector.swift`, `Sources/App/InstalledAppCatalog.swift`, `Sources/App/ActivityAutomation.swift`, `Sources/Surfaces/Settings/ActivityRulesView.swift`, and `Sources/Verification/ActivityRuleChecks.swift`.
- Modify persisted preferences/settings models and settings groups, coordinator automation integration, store observation/action callbacks, session strip/popover choice presentation and fixture factory.

**Interfaces:**
- `ActivityRule`: stable ID, name, WorkType, set of bundle IDs, enabled flag, start-after duration. Normalise/deduplicate without altering saved historical sessions.
- Pure detector consumes explicit timestamp, foreground app, presence, tracking/rule version and manual/automatic context; returns no-op, qualifying deadline, unambiguous start/switch or ambiguous candidates. Exactly one primary activity may own time.
- Coordinator owns cancellable one-shot deadline; callbacks validate generation, foreground app, recording coverage, absence/manual/pending state and rule version before acting.

- [ ] **Step 1: Write RED pure/consumer tests.** Shared ChatGPT/Claude alone produces candidates, not two starts. VS Code qualifies Coding; moving to shared Chrome retains it. Manual Coding is not relabelled by Research. Unique new activity can qualify only for an automatically owned session. Test a real deadline without another switch, 30/60/180/300 seconds, invalid custom values, rule edits mid-dwell, lock/sleep/Away, background apps, tracking disabled, failed/cancelled start, Undo cooldown and rule changes after manual correction.
- [ ] **Step 2: Observe RED** with a minimal compiling detector/model boundary and the current coordinator behaviour retained until integration.
- [ ] **Step 3: Implement rules/catalog/editor and wire one detector path.** Default 180 seconds; preset 30/60/180/300 seconds; custom 30–1800 seconds in whole seconds, explicitly validated. Rules are opt-in; adding/editing them does not enable mutation or rewrite history. Installed-app discovery scans standard application locations asynchronously, adds a bounded Spotlight query and observed-app fallback, deduplicates identity, labels missing apps and provides Add application. No whole-disk scan or content/title/URL inspection.

When enabled, rule-based automation supersedes the heuristic start detector, rather than running concurrently; retain existing manual/presence protections. Track the intersection of possible memberships through a continuous qualifying run. An explicit current activity wins. An ambiguous idle run records usage once and exposes a nonmodal activity choice; picking an activity revalidates that run before crediting it. A unique start includes only the supported qualifying interval, never overlaps previous session work, and starts a new thread unless the user explicitly chose Continue. Automatic activity switching closes at the new candidate's qualifying boundary and transfers only non-overlapping observed time. Expose reason and Undo/cooldown. Cancel deadlines on stop, edit, rule mode disable, lock, sleep and tracking changes; use injected scheduling in tests.
- [ ] **Step 4: Run GREEN** including archive totals proving 10 minutes ChatGPT plus 5 Claude is 15 minutes once. Render rule editor, shared-app conflict, unambiguous start and quiet choice in both control surfaces. Confirm catalog discovery stays local and fixtures do not enumerate the user's apps.
- [ ] **Step 5: Commit** as `feat: add explicit app activity rules without duplicate session time` and report.

### Task 8: Integration, visual acceptance and release evidence

**Files:**
- Update `FixtureFactory` in `Sources/Surfaces/GalleryView.swift`, `Sources/Surfaces/Snapshotter.swift`, interaction checks and fixture-only scenarios for all new states.
- Update `DESIGN.md`, relevant README behaviour and `docs/reviews/2026-08-31-complete-story-interactions-verification.md`.

**Interfaces:** All earlier production boundaries; no second engine, live coordinator, app inventory or power observer in a fixture.

- [ ] **Step 1: Add cross-feature regression coverage.** Continue after note save, Undo an older receipt while inline Month story is open, changing Settings rules while a pinned strip is visible, switching Insights without changing Story selection, and running power/no-power fixtures. Catch regressions through consumer state, not source-string assertions.
- [ ] **Step 2: Run RED where integration gaps appear**, fix only through the owning implementation boundary and retain explicit evidence. Do not weaken acceptance tests to make the aggregate green.
- [ ] **Step 3: Execute full verification.** `./build.sh --check`, `./build.sh --test`, `git diff --check`, strict product signature check, required screenshots at 980/1160 widths in light/dark/System and Reduce Motion. Inspect the actual rendered screenshots; generating files is not visual review.
- [ ] **Step 4: Use the fixture-only native app** for timer-strip opening/pinning, scope keyboard, Escape/X, note saving, rule selection and rail ordering. Review all app-owned operational window routes against the one-persistent-window rule. No production launch or real-data migration for testing. If a native tool cannot perform a check, document the exact limitation without a pass claim.
- [ ] **Step 5: Update documentation and commit** as `test: verify integrated Story interactions and document behaviour`. Record executed commands/counts, limitations and local commit range. A final independent whole-change review follows before completion. Do not push.
