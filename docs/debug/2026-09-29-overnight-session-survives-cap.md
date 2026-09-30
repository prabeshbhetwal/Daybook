# Overnight session survives the long-away cap (2026-09-28/29)

Investigation only. No product code changed, nothing committed.

## Bottom line

- The app did not see the night live. It quit cleanly at 00:16:55, the Mac restarted at 00:17, and it was relaunched at 09:56:07 by a build. So the 00:16→09:56 gap was offline time, and only `SessionEngine.restore(from:awayAtLaunch:)` and the first events after launch ever judged it.
- `restore` applies `longAwayCap` on only one branch: `.running`, through `resolve(away:)` at `Sources/Core/SessionEngine.swift:1820-1824`. The `.paused` branch (1754-1760) and the `.awaiting` branch (1761-1808) carry any offline gap, however long, into a stretch that stays open.
  - On `.paused`, the cap is only judged later by `absenceOutgrewCap()` (723-728). That function exempts every reason except `.idle` and `.away`.
  - On `.awaiting`, the gap is banked into `totalPausedDuration` (1772-1773) and the question stays up. Whichever answer lands later, including the replay at 1795-1801, restarts the successor at the return moment (`apply`, line 990: `sessionStartDate = returnedAt`). One record then spans the night.
- The runtime probe shows:
  - The live and `.running`-restore paths end the stretch correctly at 00:16:40.
  - A `.paused(.manual)` stretch carried across the same quits and relaunches reproduces the record exactly: start 22:46:20.449, end 11:02:20.852, work 4027.607 s against 4027.599 s, with no overnight record and consecutive receipts. This match uses two fitted instants (pause 22:48:01.5, resume 09:56:07.3).
  - The `.awaiting` paths also survive the night, but give 9188.9 s or 3986.4 s of work.
- The Session report's 9h 39m "Not recorded" row and the card's "12:00 am – 11:02 am" are downstream of the one record spanning the night. They are not separate defects.

**Confidence**

- **Medium** that the defect class is "restore keeps a stretch open across an offline gap ≥ cap unless the snapshot is `.running`". This was reproduced at runtime.
- **Low** on which branch the user's night actually took. The power telemetry for the 00:01–00:16 process contradicts every single-store story (see Unverified).

## Evidence gathered (read-only)

### Process timeline

This comes from runningboard in the unified log. Each PID is a separate build. `termination reported by launchd (0,0,0)` is a clean quit.

| PID | tracked from | terminated | note |
|---|---|---|---|
| 25204 | 22:19:32.815 | 23:58:33.450 | answered the 22:21 card; evening |
| 74561 | 00:01:25.958 | 00:16:55.255 | quit before the restart |
| — | — | — | `last reboot`: shutdown 00:16, reboot 00:17; `pmset -g log`: powerd started 00:18:01 |
| 38319 | 09:56:07.314 | 10:32:43.557 | first launch after the restart |
| 97856 | 10:32:45.648 | 10:58:57.179 | |
| 37947 | 10:58:59.177 | 12:53:46.044 | GP card answered in this process |

- The usage "systemLock" end-reasons at 23:58:33, 00:16:40 and 10:32:43 line up with app quits and the restart, not with overnight locks.
- There was **no sleep overnight**. `pmset` shows the display on 00:18–00:47, off 00:47–09:03, and on again 09:03–09:19 and 09:40–11:07. There were no Sleep or Wake entries after 22:47.

### Records and journal

- `sessions.json`:
  - `0522F265` Coding 22:46:20.448953 → 11:02:20.852007, work 4027.599 s.
  - `3D9227BF` "GP - myHealth Rockdale" 11:02:20.852 → 11:13:48.514.
  - There is nothing overnight.
- `correction-history.json` receipts:
  - The 22:21 "Break" receipt is `sequence 96` (sessionStart 22:06:43).
  - The GP receipt is `sequence 97` (sessionStart 22:46:20.449).
  - Before those is `93` (Dinner).
  - The current checkpoint's `savedAt` is 12:47:27.177 with the successor `sessionStart` 11:13:48.514. **So the GP card was answered at 12:47:27, 93 minutes after the return.** Answers can land long after the return.
- `fc.state` now shows the GP successor running, generation 97. There are no `fc.state.unreadable.*` keys.
- Preferences: `fc.longAwayCap` = 3600, `fc.threshold` = 300. `fc.idlePauseThreshold` is unset, so it is 600 s.

### Arithmetic

- Span 22:46:20.449 → 11:02:20.852 is 44 160.40 s. Paused is 40 132.80 s.
- The offline gap 00:16:55 → 09:56:07 alone is 34 752 s.
- If the stretch counted from the 09:56:07.314 launch, the morning gives 3973.54 s. That leaves 54.06 s of evening work.

### Power metadata (`session-metadata.json`, `ambient-power.json`)

- `0522F265` has exactly **one** power sample: 10:58:59.793, boundary `coverageResumed`. That is the first refresh of PID 37947.
- `955C2881` has samples 22:19:33 → 22:45:27, and none after.
- Ambient samples (written only while `engine.state == .idle`, `SessionStore.swift:697-701`) exist at 00:02:25, 00:03:25, 00:04:25, 00:05:25, 00:06:25 and 00:11:25. That is inside PID 74561.
- On mains at 100 % "not charging" there are no power notifications, so after 00:11:25 the samples say nothing.

## Event sequences considered

1. **Live overnight:** lock at 00:16:40, then idle samples, display sleep, dark wakes with small HID idle, unlock at 09:56. This is ruled out by the process timeline: the app was not running.
   - The engine path is also correct. `.running + .awayEnded` goes to `resolveAway` and then `resolve`, which applies the cap. See probe S1.
2. **Quit while running, relaunch at 09:56** (`awayAtLaunch` false or true). `restore .running` goes to `resolve(away:)` and applies the cap, or the unlock closes the open away. This is correct. See probe S2.
3. **Pause with a cap-exempt reason carried across the quits.** This covers `.manual` (the Pause button or hotkey; the legacy detector's `.pause` also maps to `.manualPause` at `AppCoordinator.swift:276-277`), `.distractionApp`, `.systemSleep` and `.extendedBreak`.
   - `restore .paused` keeps it, and neutral apps (Claude, ChatGPT, Dia, WhatsApp) never lift it.
   - In the morning, `manualResume` or a work app (Docker Desktop at 10:13:22 is `.work`) leads to `leavePause()`, which banks the whole night. The session survives. See probe S3.
4. **The 22:21 card left unanswered all night** (`.awaiting` across both relaunches), answered in the morning. The restore banks the offline gaps, but the evening while the card was up counts as ordinary time. The session survives. See probe S4.
5. **The answer landed in the journal, but a pre-answer `.awaiting` snapshot is what a later launch loads.** The restore takes the `.awaiting` branch, banks the gap with no cap, and replays the recorded answer (1795-1801). The successor starts at 22:46:20.449 and spans the night. The replay re-stamps the Break receipt, so the receipts stay consecutive. See probe S5.
6. **`archiveCurrentSession` refused during the morning `resolve`.** `totalPausedDuration += away` happens before the guard at line 855, so the gap is excluded and the stretch stays open. The session survives, but the evening counts as work. See probe S6.
7. **State at 00:16:40 was idle, watching, or `.away` or `.idle` pause.**
   - `.idle` and `.away` pauses end at the cap on the first sample, activation or unlock after launch, through `absenceOutgrewCap()`.
   - `.watching` ends by writing a "Watching" rest record, and there is none in `sessions.json`.
   - None of these can produce the record.

## Probe

- **Source:** throwaway, not in the repo: `…/scratchpad/probe/main.swift`, reproduced in full in the Appendix. It builds against the real sources:
  ```
  swiftc -swift-version 5 -Onone -target arm64-apple-macos13.0 -o probe \
    Sources/Core/*.swift Sources/App/SessionCorrectionState.swift probe/main.swift
  probe <scratch dir>
  ```
- **What it drives:** a real `SessionEngine`, `PersistenceStore` (plist in the scratch directory), `SessionArchive` and `DecisionHistory` with a fake clock.
- **Timestamps:** the real ones from the data files and the runningboard log.
- **Relaunch:** `persist()` at quit, then a new engine plus `store.loadState()` plus `restore(from:awayAtLaunch:)`. That is exactly `AppCoordinator.restorePersistedEngine`.
- **Morning tail:** an idle pause back-dated to 11:02:20.852, return at 11:13:48.514, then the GP break answered at 12:47:27.177.

### Output

Probe output, abridged: receipt sequences are shown unwrapped from `Optional(…)`, and the `final state` and `error` lines are dropped.

```
── S1 live lock overnight, unlock 09:56 (state after unlock: idle)
   22:46:20.449 → 00:16:40.150  Coding work  5200.212
── S2 quit running, relaunch 09:56 awayAtLaunch=false (state idle)
   22:46:20.449 → 00:16:40.150  Coding work  5200.212
── S2 quit running, relaunch 09:56 awayAtLaunch=true (state idle)
   22:46:20.449 → 00:16:40.150  Coding work  5200.212
── S3 paused(.manual) overnight, resumed by manualResume 09:56:07.314 (fitted)
   22:46:20.449 → 11:02:20.852  Coding work  4027.607
   11:02:20.852 → 11:13:48.514  GP - myHealth Rockdale work   687.662
   22:46 stretch: end 11:02:20.852  work 4027.607  (evidence 11:02:20.852 / 4027.599)  MATCHES EVIDENCE
   receipts ["Break#1", "GP - myHealth Rockdale#2"]  consecutive: yes (as evidence)
── S3 paused(.manual) overnight, resumed by manualResume 09:56:09.8
   22:46:20.449 → 11:02:20.852  Coding work  4025.121
── S3 paused(.manual) overnight, resumed by Docker (work app) 10:13:22
   22:46:20.449 → 11:02:20.852  Coding work  2992.876
── S4 card pending overnight, answered 09:58:37
   22:46:20.449 → 11:02:20.852  Coding work  9188.854
── S5 answered 22:48:01.5, stale awaiting prefs at 09:56:07 launch
   22:46:20.449 → 11:02:20.852  Coding work  3986.362
   receipts ["Break#2", "GP - myHealth Rockdale#3"]  consecutive: yes (as evidence)
── S5 answered 22:48:01.5, stale awaiting prefs at 10:58:59 launch
   22:46:20.449 → 00:16:55.255  Coding work  5215.316
   22:46:20.449 → 11:02:20.852  Coding work   214.499
── S6 quit running, morning end refused (after 09:56 restore: running, elapsed 5215.3)
   22:46:20.449 → 11:02:20.852  Coding work  9188.854
```

The 22:06 Coding (880.171 s) and 22:21 Break (1496.420 s) records appear in every run and are left out above. The full raw output is in `…/scratchpad/probe/output.txt`.

### Reading the output

- **Controls (S1, S2).** The cap works on every live and `.running` path. The stretch ends at 00:16:40 and the next app use starts fresh.
- **S3 (cap-exempt pause through `restore .paused`).** This is the only path that reproduces all of the following:
  - start, end and work to 8 ms;
  - no overnight record;
  - no journal commit between the two answers.

  The pause instant (22:48:01.5, the same instant as the fitted answer) and the resume instant (the 09:56:07.314 launch) are **fitted**, not observed. Any pause P and resume R with `(P − 22:46:20.449 − 46.98) + (11:02:20.852 − R) = 4027.6` fits.
- **S4 (card left up overnight).** The session survives the night, which is the same defect, but gives 9188.9 s. This is ruled out as the user's path.
- **S5 (awaiting replay).** The session survives the night, again the same defect. It reproduces 4027.6 s only if the stale snapshot was saved at 22:48:01.5, which is also a free parameter.
  - The 10:58:59 variant is ruled out: it leaves a second 22:46 record ending 00:16:55, and `sessions.json` has none.
- **S6.** The session survives, but gives 9188.9 s. This is ruled out as the user's path.

## Root cause

**`Sources/Core/SessionEngine.swift`: `restore(from:awayAtLaunch:)`, lines 1749-1825**

Offline time is compared with `store.longAwayCap` only in the `.running` case, through `resolve(away:)` at 1823. The other kinds keep the stretch open whatever the length of the gap:

- **`case .paused` (1754-1760).** This case re-enters the pause unchanged. The cap is judged later by `absenceOutgrewCap()` (723-728), which returns false unless `reason == .idle || reason == .away`.
  - Exact surviving condition: the restored snapshot is `.paused` with reason `.manual`, `.distractionApp`, `.systemSleep` or `.extendedBreak`.
  - Then any later `leavePause()` (440-447, 420-432, 435-439, or `adopt` at 1337) banks the whole night: `totalPausedDuration += interval(from: start)` at 605. The session keeps its 22:46 start.
- **`case .awaiting` (1761-1808).** Line 1772-1773 does `totalPausedDuration += shadow + interval(from: awayStart ?? savedAt)` with no cap check.
  - The replay (1795-1801) or any later answer (`apply`, 972-994) starts the successor at `returnedAt` (990). That successor spans the whole offline gap.
  - The live `.awaitingUserDecision` state has the same gap: `noteQuietWhileAwaiting` (803-815) and `.awayEnded` (531-540) bank absence into `shadowAway` with no cap.

**Why the cap logic "that is supposed to prevent this" did not run**

- `resolve(away:)` (833) is reached only from `.running` (restore 1823, `resolveAway`, `endIdlePause`).
- `absenceOutgrewCap()` deliberately skips `.manual`. Its comment says a manual pause "is a deliberate act about a session the user is still sitting in front of". That premise is false once the app has been closed for more than an hour, because nobody is sitting in front of it.
- The overnight evidence contains no `.running` restore, because a `.running` restore would have ended the stretch at 00:16:40, as S2 shows.

**Secondary finding (not the survival mechanism)**

`resolve(away:)` line 855: when `archiveCurrentSession` is refused, `totalPausedDuration` has already absorbed the absence (840-841) and the session silently stays open (S6). `endAbsentSession` (734-738) returns `.refused` instead, which surfaces a Retry. The two refusal paths disagree.

## Downstream symptoms (not separate defects)

- **"12:16 am – 9:56 am · Not recorded · 9h 39m"** in the Session report. `SessionReportView.swift:321` labels as "Not recorded" any interval of the record's span that has no app-usage (`SessionShape.swift:64`, `isGap = bundleID == nil`). The record spans the night, so the night is listed as a gap.
- **Card "12:00 am – 11:02 am", "Recorded app use: 1h 14m across 11h 2m elapsed. 9h 47m … has no app recording"** (`SessionShape.swift:259`). The day view clips the 22:46→11:02 record to today (00:00→11:02 = 11h 2m). App use inside that window: 00:00–00:16 plus 09:56–11:02, about 1h 14m.
- **The length "1h"** is `workSeconds` 4027.6 s, which is correct for the work actually recorded.

All of these are correct renderings of a record that should not exist in this shape. They go away once the stretch ends at the offline gap.

## Proposed minimal fix (at the shared function)

`restore(from:awayAtLaunch:)` is the one place that sees offline time. It should apply the same cap rule `resolve(away:)` applies, **before** it switches on the snapshot kind:

- Let `left = snapshot.pauseStart ?? snapshot.awayStart ?? snapshot.savedAt`, taking the earliest known moment nobody was producing input for this stretch.
- If `now() − left ≥ store.longAwayCap`, end the stretch there through the existing terminal path and go idle. Use `completeLongAway(intent: .endOnly)` or the `resolve` cap branch, so the record ends at `left` with `elapsed` excluding the gap. This applies to every kind.
- For `.awaiting`, do not answer the question. Keep the pending receipt answerable as a historical correction, but end the post-return stretch at `left` rather than letting a later answer restart it at `returnedAt`.

This is one helper called at the top of `restore`. It also closes the S5 replay and S6 variants, because both enter through `restore`.

Two related gaps sit outside the offline path. Whether to close them is a product decision, flagged here and not fixed by the helper above:

- `absenceOutgrewCap()` exempting `.manual` while the app is running;
- the live `.awaitingUserDecision` state having no cap.

## Regression checks that fail today

These mirror the existing self-test pattern (`SelfTest.makeEngine`, `Clock`). Each builds a second engine on the same store and archive and calls `restore`.

1. **Paused across a relaunch.**
   - Steps: `start`, work 20 min, `.manualPause`, `persist()`. Relaunch 10 h later with `restore(from:awayAtLaunch:false)`, then `.manualResume`.
   - Expect: the archived record ends at the pause start, with work of about 20 min, and the running stretch (if any) starts after the relaunch.
   - **Today:** one record spans the 10 h, as probe S3 shows.
2. **Awaiting across a relaunch.**
   - Steps: `start`, work 20 min, idle pause, return after 30 min (card up), `persist()`. Relaunch 10 h later, then `decide(.tookBreak)`.
   - Expect: no record, and no live stretch, whose span contains the 10 h offline gap.
   - **Today:** the successor starts at the return and spans the gap, as probe S4 and S5 show.
3. **Control that must keep passing:** the `.running` relaunch, probe S2.

## Unverified / contradictions

**Ambient samples at 00:02–00:11 put PID 74561's engine at `.idle`.** Every single-store lineage that later yields a live `0522F265` needs 74561 to have held that stretch, whether paused or awaiting. Two further observations make this harder:

- An idle engine persists `fc.state` on every app activation (`recordApp` → `persist`, line 793).
- Every idle transition from a live stretch commits a journal generation. That contradicts receipts 96 → 97, unless it happened before a replay re-stamped them, as in S5.

So either:

- the preference snapshot that 74561 and the morning launches read was not the one the previous process wrote, which suggests stale or lost `fc.state` writes and a possible separate defect; or
- the builds that ran overnight behaved differently from HEAD. Each PID is a different agent build, and their commits were not identified.

I could not determine which. There are no Time Machine snapshots, no historical `fc.state`, and the app's unified-log diagnostics are private.

**Other points I could not pin down:**

- **Power metadata.** It shows `0522F265` first sampled live at 37947's launch (10:58:59, `coverageResumed`) with nothing from 38319 or 97856. That fits a stretch that appeared at 10:58:59, as in the S5 replay, better than one carried from the evening, as in S3. It is weak evidence, because pending-transfer and retention rules can hide samples.
- **What paused the stretch, if S3.** Probably the Pause button or hotkey around 22:48. The FocusContinuity window was not frontmost then; only the menu-bar panel could have been used.
- **The exact moment of the 22:21 answer.** It is not recorded anywhere.

## Appendix: probe source

```swift
import Foundation

// Throwaway probe: drives the real SessionEngine through the 2026-09-28/29
// night with a fake clock and the real timestamps, including the app quits
// and relaunches seen in the runningboard log. Nothing touches real data.

final class Clock { var t: Date; init(_ r: Double) { t = Date(timeIntervalSinceReferenceDate: r) }
    func set(_ r: Double) { t = Date(timeIntervalSinceReferenceDate: r) } }

let predStart   = 812290003.857623 // 22:06:43.857 Coding 955C2881 start
let breakStart  = 812290884.028544 // 22:21:24.028 input stopped (break start)
let returned    = 812292380.448953 // 22:46:20.449 return == record start
let lidLock     = 812292393.273333 // 22:46:33.273 lock (lid)
let unlock      = 812292440.255208 // 22:47:20.255 unlock
let quit1       = 812296713.45     // 23:58:33.450 app quit (build)
let launch1     = 812296885.958    // 00:01:25.958 relaunch
let nightLock   = 812297800.150329 // 00:16:40.150 lock before restart
let quit2       = 812297815.255    // 00:16:55.255 app quit, Mac restarts
let launch2     = 812332567.314    // 09:56:07.314 relaunch (morning)
let docker      = 812333602.04522  // 10:13:22.045 first work-category app
let quit3       = 812334763.557, launch3 = 812334765.648
let quit4       = 812336337.179, launch4 = 812336339.177
let gpAway      = 812336540.852007 // 11:02:20.852 GP break start == record end
let gpReturn    = 812337228.513696 // 11:13:48.514
let gpAnswer    = 812342847.176761 // 12:47:27.177 (checkpoint savedAt)
let evidenceWork = 4027.599318265915
let scratch = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

func hhmm(_ d: Date) -> String {
    let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; f.timeZone = TimeZone(identifier: "Australia/Sydney"); return f.string(from: d)
}

struct Rig {
    let clock: Clock
    let suite: String
    let dir: URL
    var engine: SessionEngine
    init(_ start: Double) {
        clock = Clock(start)
        suite = scratch.appendingPathComponent("prefs-\(UUID().uuidString)").path
        dir = scratch.appendingPathComponent("fc-probe-\(UUID().uuidString)")
        engine = Rig.make(clock: clock, suite: suite, dir: dir, override: nil)
        engine.store.removeAll()
        engine.store.longAwayCap = 3600      // fc.longAwayCap
        engine.store.breakThreshold = 300    // fc.threshold
    }
    static func make(clock: Clock, suite: String, dir: URL, override: (() -> String?)?) -> SessionEngine {
        let store = PersistenceStore(defaults: UserDefaults(suiteName: suite)!)
        return SessionEngine(store: store, archive: SessionArchive(directory: dir, now: { clock.t }),
                             ownBundleID: "com.prabesh.focuscontinuity", schedulesDwell: false,
                             correctionWriteOverride: override, now: { clock.t })
    }
    /// Quit (persist, as applicationWillTerminate does) and relaunch through
    /// `AppCoordinator.restorePersistedEngine`'s one call.
    mutating func relaunch(quitAt q: Double, launchAt l: Double, awayAtLaunch: Bool = false,
                           staleState: PersistedState? = nil, override: (() -> String?)? = nil) {
        clock.set(q); engine.persist()
        if let staleState { engine.store.saveState(staleState) }
        clock.set(l)
        engine = Rig.make(clock: clock, suite: suite, dir: dir, override: override)
        if let snap = engine.store.loadState() { engine.restore(from: snap, awayAtLaunch: awayAtLaunch) }
    }
    func at(_ r: Double, _ e: SessionEvent) { clock.set(r); engine.transition(on: e) }
    func cleanup() { }
}

func eveningPrefix(_ rig: inout Rig) {
    rig.clock.set(predStart)
    rig.engine.start(workType: .deepWork, intent: "Coding")
    rig.at(breakStart + 600, .idleObserved(seconds: 600))            // idle pause back-dated to 22:21:24
    rig.at(returned, .appActivated(bundleID: "com.anthropic.claudefordesktop", name: "Claude"))
    rig.at(lidLock, .awayBegan(trigger: .screenLock))
    rig.at(unlock, .awayEnded)
}

func answerBreak(_ rig: Rig, at r: Double, label: String? = nil) {
    rig.clock.set(r); _ = rig.engine.decide(.tookBreak, label: label)
}

func morningTail(_ rig: Rig) -> SessionRecord? {
    rig.at(gpAway + 600, .idleObserved(seconds: 600))
    rig.at(gpReturn, .appActivated(bundleID: "com.anthropic.claudefordesktop", name: "Claude"))
    answerBreak(rig, at: gpAnswer, label: "GP - myHealth Rockdale")
    return rig.engine.archive.records.first { abs($0.start.timeIntervalSinceReferenceDate - returned) < 0.001 }
}

func report(_ name: String, _ rig: Rig, _ rec: SessionRecord?, note: String = "") {
    let recs = rig.engine.archive.records.sorted { $0.start < $1.start }
    print("── \(name) \(note)")
    for r in recs {
        print(String(format: "   %@ → %@  %-24@ work %9.3f", hhmm(r.start), hhmm(r.end), r.name as NSString, r.workSeconds))
    }
    if let rec {
        let match = abs(rec.workSeconds - evidenceWork) < 0.5 && abs(rec.end.timeIntervalSinceReferenceDate - gpAway) < 0.001
        print(String(format: "   22:46 stretch: end %@  work %.3f  (evidence 11:02:20.852 / %.3f)  %@",
                     hhmm(rec.end), rec.workSeconds, evidenceWork, match ? "MATCHES EVIDENCE" : "differs"))
    } else {
        print("   22:46 stretch: no record that starts at 22:46:20 survived to the GP answer")
    }
    print("   final state \(rig.engine.state), error: \(rig.engine.awayDecisionError ?? "none")")
    let seqs = rig.engine.awayDecisions.map { "\($0.insertedRecord?.name ?? "?")#\($0.sequence)" }
    let breakSeq = rig.engine.awayDecisions.first { $0.insertedRecord?.name == "Break" }?.sequence ?? -1
    let gpSeq = rig.engine.awayDecisions.first { $0.insertedRecord?.name.hasPrefix("GP") == true }?.sequence ?? -1
    print("   receipts \(seqs)  consecutive: \(gpSeq == breakSeq + 1 ? "yes (as evidence)" : "no")")
}

// S1 control, app alive overnight.
do {
    var rig = Rig(predStart); eveningPrefix(&rig); answerBreak(rig, at: 812292481.5)
    rig.relaunch(quitAt: quit1, launchAt: launch1)
    rig.at(nightLock, .awayBegan(trigger: .screenLock))
    rig.at(launch2, .awayEnded)
    let state = rig.engine.state
    report("S1 live lock overnight, unlock 09:56", rig, nil, note: "(state after unlock: \(state))")
}

// S2 control, quit while running, relaunch unlocked / locked.
for locked in [false, true] {
    var rig = Rig(predStart); eveningPrefix(&rig); answerBreak(rig, at: 812292481.5)
    rig.relaunch(quitAt: quit1, launchAt: launch1)
    rig.at(nightLock, .awayBegan(trigger: .screenLock))
    rig.relaunch(quitAt: quit2, launchAt: launch2, awayAtLaunch: locked)
    if locked { rig.at(launch2 + 3, .awayEnded) }
    report("S2 quit running, relaunch 09:56 awayAtLaunch=\(locked)", rig, nil, note: "(state \(rig.engine.state))")
}

// S3 paused(.manual) kept across both quits, lifted in the morning.
for (label, resume) in [("manualResume 09:56:07.314 (fitted)", launch2), ("manualResume 09:56:09.8", 812332569.8),
                        ("Docker (work app) 10:13:22", docker)] {
    var rig = Rig(predStart); eveningPrefix(&rig); answerBreak(rig, at: 812292481.5)
    rig.at(812292481.5, .manualPause)
    rig.relaunch(quitAt: quit1, launchAt: launch1)
    rig.at(launch1 + 1, .appActivated(bundleID: "com.openai.codex", name: "ChatGPT"))   // neutral
    rig.relaunch(quitAt: quit2, launchAt: launch2)
    if resume == launch2 { rig.at(resume, .manualResume) }
    rig.at(launch2 + 2, .appActivated(bundleID: "com.openai.codex", name: "ChatGPT"))   // neutral
    if resume == launch2 { }
    else if resume == docker { rig.at(docker, .appActivated(bundleID: "com.docker.docker", name: "Docker Desktop")) }
    else { rig.at(resume, .manualResume) }
    rig.relaunch(quitAt: quit3, launchAt: launch3); rig.relaunch(quitAt: quit4, launchAt: launch4)
    report("S3 paused(.manual) overnight, resumed by \(label)", rig, morningTail(rig))
}

// S4 the 22:21 card left unanswered all night, answered at 09:58:37.
do {
    var rig = Rig(predStart); eveningPrefix(&rig)
    rig.relaunch(quitAt: quit1, launchAt: launch1)
    rig.relaunch(quitAt: quit2, launchAt: launch2)
    answerBreak(rig, at: 812332717.399)
    rig.relaunch(quitAt: quit3, launchAt: launch3); rig.relaunch(quitAt: quit4, launchAt: launch4)
    report("S4 card pending overnight, answered 09:58:37", rig, morningTail(rig))
}

// S5 answered at D, but a launch loads the pre-answer awaiting snapshot.
for (dLabel, d, l, lLabel) in [("22:48:01.5", 812292481.5, launch2, "09:56:07"),
                               ("22:48:01.5", 812292481.5, launch4, "10:58:59")] {
    var rig = Rig(predStart); eveningPrefix(&rig)
    let preAnswer = rig.engine.snapshot()
    answerBreak(rig, at: d)
    rig.relaunch(quitAt: quit1, launchAt: launch1)
    if l == launch2 {
        rig.relaunch(quitAt: quit2, launchAt: launch2, staleState: preAnswer)
        rig.relaunch(quitAt: quit3, launchAt: launch3); rig.relaunch(quitAt: quit4, launchAt: launch4)
    } else {
        rig.relaunch(quitAt: quit2, launchAt: launch2)
        rig.relaunch(quitAt: quit3, launchAt: launch3)
        rig.relaunch(quitAt: quit4, launchAt: launch4, staleState: preAnswer)
    }
    report("S5 answered \(dLabel), stale awaiting prefs at \(lLabel) launch", rig, morningTail(rig))
}

// S6 running at quit, morning terminal checkpoint refused.
do {
    var rig = Rig(predStart); eveningPrefix(&rig); answerBreak(rig, at: 812292481.5)
    rig.relaunch(quitAt: quit1, launchAt: launch1)
    rig.relaunch(quitAt: quit2, launchAt: launch2, override: { "probe: journal write refused" })
    let s = rig.engine.state, e = rig.engine.elapsed
    rig.relaunch(quitAt: quit3, launchAt: launch3); rig.relaunch(quitAt: quit4, launchAt: launch4)
    report("S6 quit running, morning end refused", rig, morningTail(rig),
           note: String(format: "(after 09:56 restore: %@, elapsed %.1f)", "\(s)", e))
}
```
