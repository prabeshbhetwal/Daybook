# Auto Sessions, Daily Goal and Rewards — Implementation Plan

**Goal:** The app starts a focused session itself when the pattern holds, backdated honestly; ends it when the work stops; measures the day against a target; and marks the moments worth marking in a panel that cannot steal focus.

**Architecture:** Four pure `Core` types, each in its own file and independently testable — `FocusScore` (signals → score with its components intact), `AutoSessionDetector` (hysteresis state machine), `DailyGoal` (target and personal median), `RewardEngine` (gated, rate-limited messages). One AppKit surface, `RewardHUD`, a non-activating panel. Wiring in `AppCoordinator`, `SessionStore` and `PopoverView`.

**Tech Stack:** Swift 5, SwiftUI + AppKit, `swiftc` via `build.sh`. No SPM, no Xcode, no third-party packages, no model of any kind.

## Global Constraints

- `Sources/Core/` imports `Foundation` and `CoreGraphics` only. Never SwiftUI, never AppKit.
- No `@State`, no `@Observable` — this SDK ships no `SwiftUIMacros` plugin. View state is `ObservableObject` + `@Published`.
- Warnings are errors. Files under 500 lines.
- No new TCC permission. No window titles, no URLs.
- Never delete a file; move unwanted files to `_trash/`.
- Not a git repository — "Commit" steps are recorded and skipped.
- Every automatic decision must be able to explain itself in one short sentence built from measured numbers.
- No reward may fire without a real number behind it.

## Constants (already added to `FocusConstants`)

`mediaVetoShare 0.25`, `calmSwitchRate 2`, `switchPenaltyWeight 0.15`,
`focusWindow 900`, `autoStartThreshold 0.65`, `autoStopThreshold 0.35`,
`autoStartDwell 300`, `autoMinRunDwell 180`, `defaultDailyGoal 14400`,
`dailyGoalOptions`, `goalMedianWindowDays 14`, `goalMedianMinimumDays 3`,
`rewardsPerDay 4`, `rewardCooldown 2700`, `musicPairingDwell 1800`,
`hudDisplaySeconds 5`.

## Preferences (already added to `PersistenceStore`)

`dailyGoal`, `autoSessionsEnabled`, `rewardsEnabled`, `rewardLog`.

## Interface contracts

Every task depends on these exact signatures. They are fixed; no task may change one.

```swift
// Task 1 — Sources/Core/FocusScore.swift
struct FocusSignals: Equatable {
    let focusedShare: Double
    let mediaShare: Double
    let activity: InputActivity
    let switchesPerMinute: Double
    let attended: TimeInterval
    let dominantPurpose: AppPurpose
    let dominantApp: String?
    let dominantAppName: String
}
struct FocusScore: Equatable {
    let value: Double
    let signals: FocusSignals
    var explanation: String
    static let zero: FocusScore
}
struct FocusScorer {
    init(purposeOverrides: [String: String] = [:])
    func score(segments: [AppUsageSession], activity: InputActivity,
               window: (start: Date, end: Date)) -> FocusScore
}

// Task 2 — Sources/Core/AutoSessionDetector.swift
enum AutoDecision: Equatable {
    case none
    case start(workType: WorkType, backdatedTo: Date, because: String)
    case pause(because: String)
    case resume
    case end(at: Date, because: String)
}
struct AutoSessionDetector {
    init(breakLength: TimeInterval)
    mutating func evaluate(score: FocusScore, at moment: Date,
                           sessionRunning: Bool,
                           sessionWasAutoStarted: Bool) -> AutoDecision
    mutating func reset()
}

// Task 3 — Sources/Core/DailyGoal.swift
struct GoalProgress: Equatable {
    let goal: TimeInterval
    let achieved: TimeInterval
    let share: Double
    let isMet: Bool
    let typicalByNow: TimeInterval?
    let aheadBy: TimeInterval?
}
struct DailyGoal {
    init(archive: SessionArchive, goal: TimeInterval,
         calendar: Calendar = .current, now: @escaping () -> Date = Date.init)
    func progress() -> GoalProgress
}

// Task 4 — Sources/Core/RewardEngine.swift
enum RewardKind: String, CaseIterable, Equatable {
    case milestone, streakRecord, goalReached, goalPace, mediaEnded, workWithMusic
}
struct Reward: Equatable {
    let kind: RewardKind
    let title: String
    let detail: String
    let symbolName: String
}
struct RewardContext {
    let focusedToday: TimeInterval
    let sameWeekdayLastWeek: TimeInterval?
    let streak: Int
    let bestStreak: Int
    let goal: GoalProgress
    let endedMedia: (appName: String, seconds: TimeInterval)?
    let musicPairing: TimeInterval?
    let isSessionRunning: Bool
}
struct RewardEngine {
    init(log: [String: Date], now: @escaping () -> Date = Date.init,
         calendar: Calendar = .current)
    func next(for context: RewardContext) -> Reward?
    func recording(_ reward: Reward) -> [String: Date]
}

// Task 5 — Sources/Surfaces/RewardHUD.swift
final class RewardHUD {
    func show(title: String, detail: String, symbolName: String,
              undo: (() -> Void)?)
    func dismiss()
}
```

---

### Task 1: FocusScore

**Files:** Create `Sources/Core/FocusScore.swift`.

Scoring order: media veto → base `focusedShare` → activity weight
(`.active` 1.0, `.passive` 0.4, `.absent` 0) → switch penalty → clamp 0…1.
`explanation` reads like `"Warp 6m · 34 switches/min"` — measured numbers only.

- [ ] Implement to the contract above.
- [ ] Tests: media veto forces zero; activity scales; churn penalises; an empty window scores zero without dividing by zero.

### Task 2: AutoSessionDetector

**Files:** Create `Sources/Core/AutoSessionDetector.swift`.

- [ ] Start only after `autoStartDwell` of continuous qualification, backdated to the start of that stretch.
- [ ] Never end a session the user started by hand (`sessionWasAutoStarted == false`).
- [ ] **Flapping test:** a score oscillating between the two thresholds must produce `.none` throughout.
- [ ] Pause on media/communication; end only when the pause outlives `breakLength`.

### Task 3: DailyGoal

**Files:** Create `Sources/Core/DailyGoal.swift`.

`typicalByNow` is the median focused time reached by this hour of day across the
last `goalMedianWindowDays` **active** days; nil below `goalMedianMinimumDays`.

- [ ] Tests: share and `isMet`; nil median with two active days; a real median with five.

### Task 4: RewardEngine

**Files:** Create `Sources/Core/RewardEngine.swift`.

- [ ] Gating: no `streakRecord` unless `streak > bestStreak`; no `goalPace` unless `aheadBy` exists and is clearly positive; no comparison text unless the comparison value exists.
- [ ] Rate limits: `rewardsPerDay`, one per kind per day, `rewardCooldown` between any two.
- [ ] Tests: each gate, the cap, and the cooldown surviving a rebuilt engine from a persisted log.

### Task 5: RewardHUD

**Files:** Create `Sources/Surfaces/RewardHUD.swift`.

`NSPanel` with `.nonactivatingPanel`, `.hudWindow`, floating level,
`canJoinAllSpaces`, `becomesKeyOnlyIfNeeded`. Fades in, holds `hudDisplaySeconds`,
fades out. Clicking dismisses. An Undo closure, when present, renders a button.

- [ ] No logic beyond presentation and timing. No test; verified by running.

### Task 6: Wiring and settings

**Files:** Modify `Sources/App/AppCoordinator.swift`, `Sources/App/SessionStore.swift`, `Sources/Surfaces/PopoverView.swift`, `Sources/SelfTest.swift`.

- [ ] Evaluate the detector on the existing event boundaries — no new timer.
- [ ] `SessionEngine` records which sessions it auto-started.
- [ ] Goal ring or bar in the popover, with the target settable from the settings row.
- [ ] Toggles for auto sessions and rewards.
- [ ] Register every test from Tasks 1–4.

### Task 7: Verification

- [ ] `./build.sh --test`, all passing, zero warnings.
- [ ] `--snapshot`: goal progress populated, met, and with no median.
- [ ] Live: confirm the HUD never takes focus (the frontmost app must not change when it appears).
- [ ] README: auto sessions, hysteresis and why, the goal's personal median, the reward rules, and the explicit statement that no model is used.
