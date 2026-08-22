# FocusContinuity — UI/UX Design Spec (Slice 1: The Loop)

**Date:** 2026-08-12
**Status:** Approved for planning
**Scope:** Slice 1 of a sequenced rebuild. Later slices listed in §10.

---

## 1. Goal

Turn FocusContinuity from a menu-bar session-honesty utility into a macOS focus-session
tracker people keep using. Slice 1 ships the loop the product lives or dies by:
**start → focus → reward**, with near-zero friction to start and a reason to return
tomorrow. Analytics come later; the research is explicit that a rich dashboard on day one
is the wrong first move.

Two metrics govern every decision here: **time-to-first-session** and **day-7 retention**.

## 2. Locked decisions

These were settled with the user during brainstorming. They are not open in planning.

| # | Decision | Rationale |
|---|---|---|
| D-1 | **Evolve the existing app.** FocusContinuity becomes this product; the AppKit menu/alert layer is replaced by SwiftUI surfaces. | The `Core` already solves honest timekeeping across lock, sleep, clock skew and crash — the hard part, with tests. Restarting discards it. |
| D-2 | **The original "no SwiftUI" constraint (C1) is retired**, superseded by this spec. | Swift Charts, `MenuBarExtra` and `NavigationSplitView` do not exist outside SwiftUI. |
| D-3 | **Slice 1 = the loop only.** | Matches the research's must-have list; keeps the plan reviewable. |
| D-4 | **Idle resolution is non-blocking.** No focus-stealing modal. | The modal contradicts the calm brief and the research's "painless, not a data-integrity lecture". |
| D-5 | **Discrete sessions.** Each start/stop is a record with start, end, work seconds, work type, intent and detected app. | Every surface in both briefs assumes it: the Sessions table, "sessions completed", quick-start with a pre-chosen work type. |
| D-6 | **Deliverable = real data-driven SwiftUI views + a `--gallery` state catalogue.** | Review the shipping views, not a drawing; reach states that are hard to produce on demand. |
| D-7 | **No Xcode. `ObservableObject` house rule.** No `@State`, no `@Observable`. | Verified: this machine has Command Line Tools only, whose SDK ships no `SwiftUIMacros` plugin. |

## 3. Stack constraints (verified on this machine, 2026-08-12)

Every row below was confirmed by compiling, not assumed.

| Capability | Status | Note |
|---|---|---|
| SwiftUI, Swift Charts, `MenuBarExtra`, `NavigationSplitView`, `Table` at macOS 13.0 | Works | Requires `-parse-as-library` |
| `@Binding` `@StateObject` `@ObservedObject` `@EnvironmentObject` `@Environment` `@Published` `@AppStorage` `@FocusState` | Works | The full toolkit we need |
| `@State`, `@Observable` | **Blocked** | `SwiftUIMacros` plugin absent from Command Line Tools |
| SwiftData | **Blocked** | `@Model` needs macOS 14; macro plugin also absent |
| CloudKit E2E sync, secure-enclave encryption | **Blocked** | Needs entitlements + a real signing identity; we are ad-hoc signed with no entitlements by design |
| `UNUserNotificationCenter` on an ad-hoc-signed `LSUIElement` app | **Unverified** | Must be spiked in the plan. Design degrades safely without it (§7.3) |
| Global hotkey without Accessibility permission | **Unverified** | Carbon `RegisterEventHotKey` should need no TCC grant, unlike `NSEvent.addGlobalMonitorForEvents`. Must be spiked |

**Consequence for Brief 2's privacy section:** its *requirement* — local-only by default, no
telemetry, stated plainly, cloud strictly opt-in — is honoured. Its *named technologies*
(SwiftData, CloudKit, secure enclave) are not available and are replaced by a local
Codable file store (§5.2). Nothing leaves the machine in slice 1, and no TCC permission is
requested, so the promise holds by construction.

## 4. Architecture

**Hard rule: `Core/` never imports SwiftUI.** The headless self-test keeps working exactly
as it does today, and the engine stays reviewable without a UI.

```
Sources/
  Core/                     no SwiftUI, no views — headless-testable
    SessionState.swift        types; SessionRecord gains workType, intent, app
    SessionEngine.swift       discrete sessions: start(workType:intent:) / stop()
    PersistenceStore.swift    preferences in UserDefaults; history in a file store
    SessionArchive.swift      NEW — Codable file store + today/week/streak queries
    CategoryManager.swift     bundle ID → AppCategory (auto-pause) + suggested WorkType
    EventMonitor.swift        unchanged — lock, sleep, activate, power-off
    HotKeyMonitor.swift       NEW — Carbon RegisterEventHotKey wrapper
  App/
    FocusContinuityApp.swift  @main; static main() gates --selftest / --gallery
    SessionStore.swift        ObservableObject; the ONLY file importing both worlds
  Surfaces/
    PopoverView.swift, TodayView.swift, GalleryView.swift
  Design/
    DesignTokens.swift
    Components/               StartButton, LiveTimer, StreakBadge, StatTile,
                              WeekChart, ResolveCard, QuickStartRow, IntentField
```

**Ownership.** `FocusContinuityApp` owns `SessionStore`, which owns `SessionEngine`,
`EventMonitor` and `HotKeyMonitor`. `SessionEngine` owns `CategoryManager`,
`PersistenceStore` and `SessionArchive`. Views own nothing; they receive the store through
`@EnvironmentObject`.

**The one seam.** `SessionStore` subscribes to the engine's existing
`onStateChanged` / `onNeedsDecision` callbacks and republishes `@Published` values:
`state`, `elapsed`, `todayTotal`, `streak`, `weekBars`, `quickStarts`, `pendingResolution`.
Views never touch the engine. The gallery drives the same views from fixture stores.

**Retirement order.** `MenuBarController` and `AlertPresenter` are deleted only once the
SwiftUI surfaces reach parity, so the app is never left unusable mid-plan. `main.swift` is
deleted when `@main` lands (they cannot coexist).

## 5. Data model

### 5.1 Session record

```swift
struct SessionRecord: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String         // user intent, may be empty — never blocks starting
    var workType: WorkType   // what kind of work this was, see 5.3
    var start: Date
    var end: Date
    var workSeconds: Double  // elapsed minus paused/away, from the existing engine
    var detectedApp: String? // frontmost bundle id at start, informational
}
```

`workSeconds` is produced by the existing engine arithmetic — wall-clock, skew-clamped,
minus paused and discarded-away time. That accounting is already tested and does not change.

### 5.2 Storage

Preferences (threshold, pinned quick-starts, last work type) stay in `UserDefaults`.
Session history moves to `~/Library/Application Support/FocusContinuity/sessions.json`,
written atomically, decoded on launch, capped at 5000 records (about five years of heavy
use). Rationale: `UserDefaults` is a preferences store, Apple warns against bulk data in
it, and the current 50-record ring holds roughly one week — far too little for streaks and
Insights. The file is plain Codable JSON, local-only, never transmitted.

A corrupt or unreadable file is renamed aside with a timestamp and a fresh store starts, so
a parse failure can never wedge launch or silently destroy history.

### 5.3 Two distinct taxonomies — do not merge them

The existing `AppCategory` answers *"should this app pause my session?"*. The new label
answers *"what kind of work was this?"*. They are different questions with different value
sets, and collapsing them would break the auto-pause logic. They stay separate types:

```swift
// EXISTING, unchanged. Drives the state machine: .breakTime pauses after the
// 20s dwell, .work resumes, .neutral never moves the machine (D5).
enum AppCategory: String, Codable { case work, breakTime, neutral }

// NEW. A label on a completed session, chosen by the user, never by the machine.
enum WorkType: String, Codable, CaseIterable {
    case deepWork, meetings, admin, learning, breakTime
}
```

`CategoryManager` keeps mapping bundle ids to `AppCategory` for auto-pause, and gains a
second, advisory map from bundle id to a **suggested** `WorkType` (Xcode → deep work, Zoom
→ meetings). The suggestion only pre-selects; the user's explicit choice always wins and is
what gets stored. Project and intent tags stay optional and off the critical path.

### 5.4 Streak

A day counts toward the streak when its completed sessions total **≥ 25 minutes** of work
time. The streak is the number of consecutive such days ending today or yesterday — ending
yesterday keeps today's streak visible before the first session, which is the moment
motivation matters most. Freezes and grace days are slice 3; slice 1 shows the number only.

## 6. Surfaces

### 6.1 Menu bar item — four ambient states

| State | Appearance |
|---|---|
| Idle | App glyph only, no text |
| Running | Glyph + elapsed, SF Pro monospaced digits, `2h 15m` / `15m` |
| Paused | `⏸` prefix, `secondaryLabelColor` |
| Needs attention | Glyph with a dot badge after an unresolved absence |

SF Pro with `monospacedDigit` — not SF Mono — because the menu bar uses the system font;
SF Mono there reads as foreign and runs wide. Brief 2's SF Mono instruction is honoured in
the popover timer instead (§9).

### 6.2 Popover — 320pt, `.ultraThinMaterial`, three zones

1. **Hero.** Top row: today's focused time (leading), streak flame (trailing, accent).
   Then `IntentField`, focused on open, placeholder *"What are you working on?"*. Then
   either `StartButton` (idle) or `LiveTimer` in SF Mono with Pause and Stop (running).
   When a session needs resolving, `ResolveCard` replaces this zone's controls.
2. **Quick-start.** Three to seven chips derived from history (§7.4). One click starts
   immediately with that work type and intent. With no history, the five work types show
   instead, so the zone is never empty.
3. **Footer.** Seven-bar weekly chart, current day highlighted, and `Open Dashboard`.

### 6.3 Today window

A plain `Window` in slice 1 — **not** `NavigationSplitView`. There is exactly one
destination until Insights exists, and an empty sidebar is worse than no sidebar. The split
view arrives in slice 2 with something to navigate to; Brief 2's three-column Timeline is
slice 4.

Contents, top to bottom: hero (large start control or live timer, today's total, streak),
weekly rhythm chart with today highlighted, and four `.regularMaterial` stat cards —
today's focused time, current streak, sessions completed today, and longest session today.
The fourth card is *longest session*, not "you focus best 9–11am": that insight needs weeks
of data and would show a fabricated or empty value on day one.

### 6.4 Gallery

`--gallery` renders every state from fixtures, light and dark, side by side: idle, running,
paused, needs-resolution, first-run empty, and broken-streak recovery. It is a review
surface and a visual regression check, and it must not touch real user data.

## 7. Interaction logic

### 7.1 Starting

1. User opens the popover (click, or ⌃⌥Space) — `IntentField` is already focused.
2. They type an intent and press Return, or press Return immediately, or click
   `Start Focus`, or click a quick-start chip.
3. The engine starts a session with the chosen work type (default: last used, else the
   frontmost app's suggestion, else Deep work) and the typed intent (may be empty).
4. Menu bar switches to running. Popover can be dismissed with Esc; the session continues.

**Empty intent never blocks a start.** Categorising later is explicitly allowed — the
research is blunt that forcing a label up front adds friction at the worst moment.

### 7.2 Stopping and pausing

Stop writes a `SessionRecord`, updates today's total, streak and week bars, and returns to
idle. Pause and resume use the existing engine transitions. Auto-pause on a distraction app
keeps its 20-second dwell guard.

### 7.3 Idle resolution (non-blocking)

1. Lock or sleep begins; the engine records the away interval (existing behaviour).
2. On return, an away shorter than 5s is discarded and one under the threshold is absorbed
   silently — both unchanged from today.
3. An away at or over the threshold parks the session in `awaitingUserDecision`, sets the
   menu bar to *needs attention*, and posts a notification: *"Away 22m — was that a break?"*.
4. Clicking the notification, or simply opening the popover, shows `ResolveCard` with
   **Merge / Break / Discard**, mapping onto the engine's existing `mergeTime`,
   `continueSession` and `resetTimer` decisions.
5. Nothing steals focus and nothing blocks typing. If notifications are unavailable, the
   attention badge plus the popover card carry the entire flow — the design degrades safely.

### 7.4 Quick-start derivation

The top (workType, intent) pairs by frequency over the last 14 days, capped at seven,
minimum three shown when history allows. Ties break by most recent. This is the research's
"pre-fill from history" and it is computed, never configured, in slice 1.

### 7.5 Global hotkey

⌃⌥Space toggles the popover, and starts or stops depending on state. Implemented with
Carbon `RegisterEventHotKey`, which requires no Accessibility grant. If the spike shows
otherwise, the hotkey is dropped from slice 1 rather than requesting a TCC permission —
the privacy promise outranks the convenience.

## 8. Error and edge handling

| Situation | Behaviour |
|---|---|
| Session archive unreadable | Renamed aside with a timestamp, fresh store, logged. Launch never blocks |
| Notification authorisation denied or unavailable | Attention badge + popover resolve card carry the flow |
| Hotkey registration fails (already taken) | Logged, feature silently absent, everything else works |
| Clock jumps backwards | Existing clamp-to-zero, already tested |
| App quit with a session running | Existing persist-on-terminate; restored on next launch through the same resolution path |
| Two unresolved sessions | Resolve card queues them, most recent first |

## 9. Visual system

- **Typography.** SF Pro Text for body; menu bar title SF Pro with `monospacedDigit`;
  popover and Today hero timers SF Mono.
- **Colour.** Semantic system colours only (`.primary`, `.secondary`, `.tint`) so light and
  dark are automatic. The system accent is reserved for the primary Start action and the
  streak. No hardcoded hex.
- **Materials.** `.ultraThinMaterial` for the popover; `.regularMaterial` for cards and,
  from slice 2, the sidebar.
- **Motion.** Session start gets one brief, satisfying transition. Everything is wrapped in
  a Reduce Motion check that degrades to a cross-fade.
- **Accessibility.** Reduce Motion, Increase Contrast and Dynamic Type respected; every
  control has an accessibility label; the popover is fully keyboard navigable.

## 10. Out of scope for slice 1

Recorded so nothing from either brief is lost.

| Slice | Contents |
|---|---|
| 2 | `NavigationSplitView` shell, Insights (category breakdown, trends, best focus window), Sessions `Table` with inline relabel |
| 3 | Retention layer: growing artifact, streak freezes, day 3/5/7 milestones, notification schedule (Thursday nudge, Sunday start-fresh) |
| 4 | Brief 2's three-column Timeline, `Canvas` 24-hour view, context-switch segmentation, post-session 1–5 focus rating |
| 5 | Onboarding with permission rationale, privacy statement, first-run tour |
| Undecided | Opt-in behavioural layers (window titles, Git branch, typing velocity) — each needs TCC permissions the app currently avoids. AI daily summary — needs an explicit decision, since sending session text off-device contradicts local-only |

## 11. Verification

- The existing 14 headless tests keep passing; `Core` changes extend them (discrete
  sessions, archive queries, streak computation, quick-start derivation).
- `--gallery` renders every state in both appearances for visual review.
- `./build.sh --test` stays the single command, `-warnings-as-errors` stays on.
- Manual script: start from the hotkey with the screen locked mid-session; confirm the
  attention badge, the notification, and that resolving from the popover produces the right
  `workSeconds`.

## 12. Risks

1. **Notification delivery under ad-hoc signing** — spiked first in the plan; design already
   degrades safely.
2. **Carbon hotkey without TCC** — spiked; dropped rather than requesting Accessibility.
3. **`ObservableObject` ceremony** — no `@State` means local UI state needs a view model.
   Accepted; revisit only if it becomes genuinely painful.
4. **Engine refactor to discrete sessions** touches the most valuable tested code in the
   project. It is sequenced first, behind the existing tests, before any UI is built on it.
