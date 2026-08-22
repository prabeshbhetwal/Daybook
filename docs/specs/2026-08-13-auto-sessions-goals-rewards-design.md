# Auto Sessions, Daily Goal and Rewards — Design

**Date:** 2026-08-13
**Slice:** C + D-adjacent. Follows the purpose/threads slice, which shipped the
`AppPurpose` axis and `InputDensity` this design depends on.

## Goal

The app notices focused work and starts a session itself, backdated honestly;
notices when the work stops and ends it; measures the day against a target the
user sets; and marks the moments worth marking with a message that never steals
focus and never says anything the data does not support.

## Why not a local model

The decision is: given *(purpose mix, input density, dwell, switch rate)*,
is this focused work? Five numbers in, one boolean out. That is a scoring
function with a dozen coefficients.

A local LLM would cost 1–3 GB resident against an app that idles at 17 MB, run
inference on every app switch on battery, require linking `llama.cpp` or MLX
(MLX needs macOS 14; the target is 13; Apple's Foundation Models framework needs
macOS 26), and make the one thing the app sells — a defensible number —
non-deterministic. "Why did it start?" must answer *"Warp frontmost 6 minutes,
34 keys per minute, no media"*, not *"the model decided"*.

The intelligence lives in the design instead: multi-signal scoring, hysteresis,
backdating, and thresholds that move with the user's corrections.

## Layer 1 — FocusScore

Pure, in `Core`, no state. Consumes a window of usage segments and returns a
score with its components intact, so every automatic decision can explain itself.

```swift
struct FocusSignals: Equatable {
    let focusedShare: Double     // attended seconds in focused-purpose apps ÷ total
    let mediaShare: Double       // attended seconds in media apps ÷ total
    let activity: InputActivity
    let switchesPerMinute: Double
    let attended: TimeInterval   // total attended seconds in the window
    let dominantPurpose: AppPurpose
    let dominantApp: String?     // bundle ID, for the explanation
}

struct FocusScore: Equatable {
    let value: Double            // 0…1
    let signals: FocusSignals
    var explanation: String      // "Warp 6m · 34 keys/min · no media"
}
```

Scoring, in order:

1. **Media veto.** `mediaShare` above `mediaVetoShare` forces the score to zero.
   A film playing is not deep work however much typing accompanies it.
2. **Base** is `focusedShare`.
3. **Activity weight** multiplies it: `.active` × 1.0, `.passive` × 0.4,
   `.absent` × 0.
4. **Switch penalty** subtracts `switchesPerMinute` above `calmSwitchRate`,
   scaled — rapid churn between many apps is not deep work.
5. Clamp to 0…1.

Constants live in `FocusConstants`.

## Layer 2 — AutoSessionDetector, with hysteresis

Pure, in `Core`. This is the layer that decides whether an automatic mode feels
intelligent or idiotic. macOS Focus flips on and then off again shortly after;
that is **flapping**, and the cure is asymmetry.

```swift
enum AutoDecision: Equatable {
    case none
    case start(workType: WorkType, backdatedTo: Date, because: String)
    case pause(reason: String)
    case resume
    case end(at: Date, because: String)
}

struct AutoSessionDetector {
    mutating func evaluate(score: FocusScore, at moment: Date,
                           sessionRunning: Bool) -> AutoDecision
}
```

Rules:

- **Start** requires the score at or above `autoStartThreshold` continuously for
  `autoStartDwell`. It backdates to the moment the qualifying stretch began, so
  the dwell is credited rather than discarded.
- **Stop** requires the score at or below `autoStopThreshold`, which is *well
  below* the start threshold. A score drifting in the middle changes nothing.
- **Minimum dwell in each state** — `autoMinRunDwell` before a started session
  may end, so a single trip to Slack cannot undo it.
- **Pause, not end,** when a media or communication stretch begins; it ends only
  if the pause outlives the user's configured `breakLength`. That is the model
  already chosen for manual sessions, reused rather than reinvented.
- Only sessions the detector started may be ended by it. A session the user
  started by hand is never stopped automatically — the app may guess about its
  own guesses, never about a deliberate act.

Sessions it starts are marked, so the learner can tell them apart later and so
the UI can offer Undo.

## Layer 3 — Daily goal

```swift
struct GoalProgress: Equatable {
    let goal: TimeInterval
    let achieved: TimeInterval
    let share: Double            // achieved ÷ goal, uncapped
    let isMet: Bool
    let typicalByNow: TimeInterval?   // median at this hour across active days
    let aheadBy: TimeInterval?        // achieved − typicalByNow
}
```

`dailyGoal` persists in `UserDefaults`, default four hours, options 2/4/6/8.

**"On track" is measured against the user, not against a clock.** A linear
target implies a working day with a fixed start, which is false for most people.
Instead `typicalByNow` is the median focused time reached by this hour of day
across the last fourteen **active** days — the same active-days-only rule the
period average already uses, and for the same reason. With fewer than three
active days there is no median worth quoting, so `typicalByNow` is nil and no
pace message may fire.

## Layer 4 — Rewards

Ambient, never a decision. The away-resolution flow keeps its existing card in
the popover; nothing here asks a question.

```swift
enum RewardKind: String, CaseIterable {
    case milestone, streakRecord, goalReached, goalPace, mediaEnded, workWithMusic
}

struct Reward: Equatable {
    let kind: RewardKind
    let title: String
    let detail: String
    let symbolName: String
}
```

| Kind | Fires when | The number behind it |
|---|---|---|
| `milestone` | Focused time crosses a whole hour while running | today's total, and the same weekday last week |
| `streakRecord` | The streak exceeds its own historical maximum | streak length, previous best |
| `goalReached` | Focused time crosses the daily goal | goal, time taken |
| `goalPace` | Ahead of `typicalByNow` by a clear margin | today vs typical |
| `mediaEnded` | A media stretch ends or its app quits | how long it ran |
| `workWithMusic` | A focused app is frontmost while a music app runs, sustained | how long the combination has held |

**Three rules, all non-negotiable:**

1. **Earned by data.** No reward fires unless the number behind it is real and
   present. Same rule as Insights, which are gated rather than fabricated. No
   `streakRecord` without an actual record; no `goalPace` without a median.
2. **Rate limited.** At most `rewardsPerDay`, never two of the same kind in one
   day, and never within `rewardCooldown` of the previous one. Cheap praise
   stops landing almost immediately, and a reward system that annoys is worse
   than none.
3. **Never fabricated comparisons.** "More than yesterday" requires yesterday to
   have data. Where it does not, the message goes without the comparison rather
   than inventing one.

Cooldown state persists, keyed by kind and day, so a relaunch cannot reset it
into repeating itself.

## Layer 5 — The HUD

An `NSPanel` created with `.nonactivatingPanel`, floating window level, joining
all Spaces, and never becoming key. This is why it is not an `NSAlert`: at the
OS level it cannot take focus, so it cannot interrupt. It fades in, holds for a
few seconds, fades out, and is dismissable by clicking it.

It carries the reward's symbol, title and detail, and nothing else. No buttons,
no decisions. An auto-started session announces itself through the same HUD with
an Undo affordance, which is the one exception that carries an action.

Settings: rewards can be turned off entirely, and auto sessions can be turned
off independently. Both default on.

## Testing

Headless, against the injected clock, continuing the existing numbering:

1. `FocusScore`: media veto forces zero; activity scales; switch churn penalises;
   the explanation names the dominant app and the measured rate.
2. `AutoSessionDetector`: starts only after sustained qualification, and
   backdates to the start of the stretch, not the moment of decision.
3. Hysteresis: a score oscillating between the two thresholds produces no
   decision at all — the flapping regression test.
4. A user-started session is never auto-ended.
5. Media begins → pause, not end; pause outliving `breakLength` → end.
6. `GoalProgress`: share, met, and a nil median with fewer than three active days.
7. `RewardEngine`: gating (no record, no `streakRecord`), the per-day cap, the
   same-kind-once rule, and the cooldown surviving a relaunch.

## Non-goals

- Any local or remote model.
- Any new TCC permission.
- Reading window titles or URLs.
- Auto-starting from a cold machine: the detector only ever reasons about
  stretches the usage tracker already recorded.
