# Away Prompt — Design

Date: 2026-08-22. Status: approved in chat; built straight through.

## Problem

When the user comes back from an absence long enough to ask about, the question sits in
the popover as a card — a card they have to go and find. The card's two secondary answers
(*I was away*, *Start fresh instead*) are borderless links that read as an afterthought,
and the card never says *when* the absence was, only how long. The user's brief: show the
range, make all four answers proper buttons that look good, and ask the question where the
user is — lightly, from the menu bar, for a short absence; on a blurred screen, centred,
for a long one — so that one click answers it.

## Goals

1. One answer vocabulary — `AwayAnswerGrid` — used by the popover card, the dashboard card,
   the quick prompt and the full prompt: header with the range, four equal buttons in a
   2 × 2 grid, the recommended answer filled; captions under each button where there is room.
2. A **quick prompt**: a small floating card with an arrow, anchored under the menu-bar item,
   never taking focus, one click to answer, fading after 20 s if ignored.
3. A **full prompt**: the display under the pointer blurred behind a centred card with the
   four big buttons and captions; Return answers *break*, Esc or *Later* dismisses.
4. A **tier rule** that is pure and tested: absence ≥ *Full-screen prompt after* → full;
   otherwise quick. The threshold is a setting (default 30 min; *Never* means always quick).
5. One state, three surfaces: answering anywhere dismisses everything else at once;
   dismissing a prompt leaves the card in the popover and the session running — the honest
   default the card already has.
6. `SessionStore` split into two files so the 500-line rule holds for it.

## Non-goals

- No change to what is asked or what each answer does (`UserDecision` is unchanged).
- No prompt below *Ask me after* or at/above *End session after* — those bands already
  have their behaviour (quiet exclusion; session ended).
- No prompt for an absence the user declared (`Away` → `I'm back`): they already told us.
- No sound. *(Revised in the build: the native "Away Xm" notification was removed — it
  duplicated the prompt, which is now the channel. Break reminders keep theirs.)*

## Design

### 1. The range

`SessionEngine.pendingAwayRange: (start: Date, end: Date)?` — non-nil only in
`.awaitingUserDecision`, computed from `decisionStartDate` (the return moment) and the
away length: `(returnedAt − away, returnedAt)`. `SessionStore` publishes it as
`pendingAwayRange` beside `pendingAway`, set in the same two places.

### 2. `AwayAnswerGrid` (Design/Components/AwayAnswers.swift)

```swift
struct AwayAnswerGrid: View {
    let away: TimeInterval
    var range: (start: Date, end: Date)?
    var showsCaptions: Bool = false     // full prompt: yes; cards and quick prompt: no
    var compact: Bool = false           // quick prompt: tighter padding, smaller type
    let onAnswer: (UserDecision) -> Void
}
```

Header: `moon.zzz.fill` (hierarchical) · **Away 8m** · `12:41 – 12:49 pm` (secondary;
omitted when `range` is nil). Line: *Not counted. Your session is still running.*
Grid, two rows of two, every button `maxWidth: .infinity`:

| Button | Decision | Caption |
|---|---|---|
| **It was a break** (filled, `.keyboardShortcut(.defaultAction)`) | `.tookBreak` | Not counted, written down as rest |
| **I was working** | `.mergeTime` | Count it as work on this session |
| **I was away** | `.continueSession` | Not counted, nothing recorded |
| **Start fresh** | `.resetTimer` | End that session where you left, begin a new one |

Buttons are `.plain` with a custom body: accent fill + white for the recommended one,
`Surface.control` + primary for the others, `Radius.control` corners, `.help` carrying the
caption when captions are hidden.

`ResolveCard` keeps its name and `framed` flag but takes `range` and a single
`onAnswer: (UserDecision) -> Void`; its body is the grid. Call sites: `HeroCard`,
`DashboardView`.

### 3. Tier rule (Core/AwayPrompt.swift — Foundation only)

```swift
enum AwayPromptTier: Equatable { case quick, full }
extension AwayPromptTier {
    /// `fullPromptAfter == nil` means Never: every absence gets the quick prompt.
    static func tier(forAbsence away: TimeInterval,
                     fullPromptAfter: TimeInterval?) -> AwayPromptTier
}
```

Constants: `FocusConstants.defaultFullPromptAfter = 30 * 60`,
`fullPromptAfterOptions = [20m, 30m, 45m, 60m, 90m, 120m]`. `PersistenceStore.fullPromptAfter:
TimeInterval?` — missing key → default, stored `0` → nil (Never). `SettingsModel.fullPromptAfter:
TimeInterval` with `0` meaning Never, so the picker has a concrete tag; the *Away and breaks*
tab gains **Full-screen prompt after** with a *Never* option and a footer sentence.

### 4. Quick prompt (Surfaces/AwayPrompt/AwayQuickPanel.swift)

A non-activating, first-mouse-accepting panel — the `RewardHUD` classes, made internal
and reused. Content: an upward arrow notch and a material card holding
`AwayAnswerGrid(compact: true)`, width 300. Position: centred under the status item,
found as the `NSStatusBarWindow` in `NSApp.windows` whose frame sits in the menu bar;
fallback: 16pt in from the top-right of the main screen's visible frame. Fades out after
20 s, or the instant an answer lands anywhere.

### 5. Full prompt (Surfaces/AwayPrompt/AwayFullPrompt.swift)

A borderless `NSWindow` subclass that can become key, sized to the screen under the
pointer, level `.screenSaver`, `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`,
transparent, whose content is an `NSVisualEffectView` (`.hudWindow`, `.behindWindow`,
`.active`) with a hosted SwiftUI view on top. The view: a dimming click-catcher (tap =
Later) and a centred 520pt card — `AwayAnswerGrid(showsCaptions: true)` with larger type
and a **Later** button carrying `.keyboardShortcut(.cancelAction)`. Shown with
`NSApp.activate(ignoringOtherApps: true)` then `makeKeyAndOrderFront`, so Return and
Esc work; closed on answer or Later.

### 6. Presenter (App/AwayPrompter.swift, `@MainActor`)

Owns one quick panel and one full prompt, and a Combine sink on
`store.$pendingAway.removeDuplicates()`: `nil` → dismiss both; a value (transition from
nil) → `present(away:range:)`, which picks the tier with `AwayPromptTier.tier(forAbsence:
fullPromptAfter: engine.store.fullPromptAfter)` and shows the matching surface. Answers
call `store.resolve(_:)`; *Later* and the 20 s fade call only `dismiss()`. A question
already pending **at launch** (restored from disk) is presented by the same rule as any
other — the user asked for a long absence to be put to them on a blurred screen, and a
relaunch in the middle of one does not make it shorter. Wired from
`AppCoordinator.applicationDidFinishLaunching` after `store.refresh()`.

### 7. `SessionStore` split

`Sources/App/SessionStore+Dashboard.swift` holds `extension SessionStore` with the
*Timeline inspection* and *Per-app history* sections (hover/select/expand, per-app
sessions and buckets, `refreshDashboard()`, date selection, threads, `totalToday(for:)`).
Members those need — `engine`, `usage`, `tracker`, `cachedWindow`, `earliestDay`, and
`refreshDashboard()` — go from `private` to internal with a one-line comment naming the
extension file as the reason; views still never touch `engine` (a convention this app
keeps by discipline, not by the compiler).

## Known limits

- The status-item anchor is a best effort: `MenuBarExtra` exposes no frame, so the panel
  reads the status-bar window's frame. If that lookup fails the card sits top-right.
- The full prompt blurs one display — the one under the pointer.
- Neither prompt renders in the snapshot harness as a window; the hosted SwiftUI views do,
  and the harness renders both (`awayPrompt-full-*.png`, `awayPrompt-quick-*.png`).

## Testing

- 85 `AwayPromptTier.tier`: below → quick, at/above → full, nil → quick; and
  `PersistenceStore.fullPromptAfter` — missing → 30 min, `0` → nil, value → value.
- 86 `SessionEngine.pendingAwayRange`: nil while running; after a 22 min lock, equals
  (now − 22 min, now); nil again after the decision.
- 82 gains one write (`fullPromptAfter`), so `changes == 9`.
- 84 (13" fit) still passes with the 2 × 2 grid in the hero.
- Harness renders the two prompt views; live: quick prompt under the item after a 16-minute
  idle stretch (default thresholds), full prompt after 31 minutes, Esc dismisses, Return
  answers break, answering in the prompt clears the popover card.

## Addendum — continuity (2026-08-22, later)

The user's brief, clarified: *after a kitchen break I want to continue the session I was
in, from where I left off.* The thread model already carried the work across a break; the
UI did not show it — the hero clock restarted at zero — and the list of recorded breaks
in Continue today read as if the breaks were the sessions.

- **The clock is the stretch; the thread total is its own line.** *(Revised the same
  evening: a clock that could span the whole day read as a day total — "why is my
  session 6h 55m?" — and the user had earlier asked that the menu bar show the running
  session.)* Hero, menu bar and dashboard show `elapsed`, the current stretch. Beneath
  the intent, when the work has more than one stretch today: `6h 55m on this today · 6
  stretches since 9:10 am` (`threadSummaryLine`, from `threadElapsed`, gated on state
  because the engine's `elapsed` keeps counting after a stop).
- **The card says what happens.** Its second line is `Not counted. Deep work continues —
  2h 14m so far.` — or, when the user came back into different work, `Not counted. You're
  in Dia now — Deep work stays in Continue today.`
- **App-aware continuity.** "It was a break" and "I was away" keep the thread when the
  user returns in the app they left in, or in one of the work's apps today (the store
  answers that through `SessionEngine.threadContextMatcher`); returning in an unrelated
  app starts a new thread with an empty intent, and the old thread is one click away in
  Continue today. "I was working" never re-threads; "Start fresh" always does. Without a
  matcher (no usage data) the thread is kept.
- **Break records are not Continue rows.** Rest is not resumable; a break record stays on
  the timeline and in the log.

Tests 87 (thread clock) and 88 (app-aware continuity).
