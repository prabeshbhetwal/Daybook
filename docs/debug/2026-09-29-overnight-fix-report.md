# Fix report: a session left paused or waiting survives the long-away cap (2026-09-29)

Follows `docs/debug/2026-09-29-overnight-session-survives-cap.md` (the investigation, in the investigating worktree). All four approved items are implemented, test-first.

Branch: `worktree-agent-a78877eb1ffcc58a9`, from local `main` at `b8d2739`.

## What changed

All product changes are in `Sources/Core/SessionEngine.swift`.

### One shared ending: `endStretch(leftAt:)` (line 788)

- A new private helper. It turns whatever the stretch is doing into an away pause from `left`, then calls the existing `completeLongAway(intent: .endOnly)` → `endAbsentSession()`.
- The record ends at `left`. Its work is exactly the work before `left`, because `elapsed` already subtracts the live pause.
- Before ending, it banks `shadowAway` (second absences the card already sat through stay excluded). It also clears the pending-question fields: `decisionStartDate`, `awayReturnedAt`, `pendingDecisionID`, `workBeforePendingAway`, `departureApp`, `pendingAwayLabel`.
- **If the save is refused**, the stretch stays `.paused(.away)` from `left`, `lastLongAwayTransition` is `.refused`, and `awayDecisionError` is set. That is the state the existing Retry surface already handles: `SessionStore.applyLongAwayResult` → `.longAway` retry → `retryLongAwayTransition`, whose `absenceOutgrewCap()` guard holds for an `.away` pause past the cap. Any later paused event also judges the cap again.
- Everything below routes through this helper. No new terminal path was added.

### 1. Offline gap at restore (the root cause)

`restore(from:awayAtLaunch:)`, lines 1799-1826 and 1887-1892.

- Before the switch on the snapshot kind, the gap is measured from `absentSince`. For the stretch's `left`:
  - `absentSince` is the earliest of `pauseStart`, `awayStart` and `savedAt`, as the investigation proposed.
  - One refinement: for a `.distractionApp` or `.watching` pause, the pause start is left out of `absentSince`. The user was present for those pauses (see item 2), so only the write says when they left.
  - `left` is `min(pauseStart ?? absentSince, absentSince)`. The work stopped where any pause began.
- If `now − absentSince ≥ longAwayCap`, it calls `endStretch(leftAt: left)`, persists, emits, and returns. This applies to every non-idle kind: `.paused` (any reason), `.awaiting`, and `.running`.
  - `.running` includes the committed-answer path, where the original snapshot was `.awaiting` and the checkpoint was running. That path used to bank the gap with no cap.
- **Exception: a saved answer.** This is an `.awaiting` snapshot whose answer is already in the archive, detected by a record id equal to `pendingDecisionID` or `activeRecordID` (the investigation's S5).
  - The existing replay runs first, so the answer's break and pre-away records stand.
  - After the replay (line 1887), the replayed successor is ended at `left`. Its offline gap, banked by the awaiting branch, is un-banked into the closing pause first.
- `.running` snapshots still end with the same record as before. The one difference: a locked relaunch (`awayAtLaunch: true`) past the cap now ends at launch, rather than waiting for the unlock to do it. The record is identical.

### 2. Live pause past the cap

`absenceOutgrewCap()` (line 726) and a new `pauseMeansNobodyHere(_:)` (line 735).

**Now end at the cap:** `.manual`, `.away`, `.idle`, `.systemSleep`, `.extendedBreak`.

- `.manual` is the user's decision. The old comment's premise ("the user is still sitting in front of it") does not hold past the cap, and the comment now says so.
- `.systemSleep` and `.extendedBreak` are never entered by the current engine. They exist only as persisted legacy reasons. Both mean the machine or the person was gone, so they end like `.away`.

**Still exempt:** `.distractionApp` and `.watching`.

- In both, the user is at the Mac: looking at a break app, or watching a video or call.
- "Nobody is here" does not hold, and each already ends through the user's own next move. A work app lifts a distraction pause. Input ends watching, writing a "Watching" rest.

Because every existing caller of `absenceOutgrewCap()` now covers a pressed pause past the cap, the following all end the session where the pause began:

| Event | Intent |
|---|---|
| Resume, or work-app activation | `.beginFreshSession`, same thread |
| Unlock, or any idle sample | `.endOnly` |

### 3. Live unanswered question with a second absence past the cap

`secondAbsenceOutgrewCap()` (line 809) returns where the open second absence began, once it has run past the cap.

It is checked at three points, and each calls `endStretch(leftAt:)` at that start:

- `.awaitingUserDecision` + `.awayEnded` (line 536), a lock or sleep the card sat through.
- `noteQuietWhileAwaiting` (line 856), checked first on every idle or watching sample, as the paused path does. This covers a quiet absence both while it is still open and when input closes it.
- `apply(_:)` (line 939): an answer given before any sample saw the absence close.

A second absence shorter than the cap keeps today's behaviour. It is banked to `shadowAway` and excluded from whichever stretch the answer continues.

### 4. Refused archive in `resolve(away:)`

Line 897.

- **Before:** the cap branch banked the absence, then `guard archiveCurrentSession(…) else { return }` left the session running and silent. No `lastLongAwayTransition` was set, so no Retry was offered.
- **Now:** the cap is judged before the absence is banked, with the same condition as before (`away ≥ breakThreshold && away ≥ longAwayCap`), and it goes through `endStretch`.
  - On success, the record matches the old path: same end (`now − away`) and same work.
  - On refusal, the session sits `.paused(.away)` with `.refused` and the error, exactly as `endAbsentSession` refusals do. `transition(on:)`'s existing `forceEmit` on `.refused` makes the store surface the Retry.
- The long comment explaining the cap moved with the check, unchanged, plus one sentence on why it comes first.

## How pending questions and receipts are treated

Past the cap, a pending question is **dropped unanswered**. No receipt is created and no user-facing answer is chosen. Two existing precedents say this is how the engine treats a long away:

- `resolve(away:)` never asks about an absence past the cap. It just ends the session.
- `stop()` and `.resetSession` while the card is up end the stretch through `archiveCurrentSession` with no receipt.

The record then spans the first (asked-about) absence with that absence excluded as paused time. Its work is pre-away work plus the post-return work before `left`.

**Already-answered questions are never re-decided.** If the answer is in the archive (the S5 replay), the replay commits as before and keeps its receipt sequence. Only the successor it opens is ended at `left`.

`archiveCurrentSession`'s terminal checkpoint (the journalled `.endStretch` operation) is unchanged. It still owns the ending whenever the decision history requires one.

## Checks

The new file is `Sources/Verification/LongAwayRestoreChecks.swift`, registered at the end of `SelfTest.run()`'s list, so existing test numbers are unchanged. It uses its own fixture with a `correctionWriteOverride` hook, the same pattern `DecisionRecoveryChecks` uses to force a journal refusal. Relaunch is `persist()`, then a new engine, then `store.loadState()`, then `restore(from:awayAtLaunch:)`, as in `AppCoordinator.restorePersistedEngine`.

| # | Check | Covers |
|---|---|---|
| 485 | A pause carried across a long quit ends where the pause began | `.manual` pause, quit, relaunch 10 h later, then Resume. Expects: idle at restore, record start→pause start with 1200 s, nothing spans the offline gap. |
| 486 | A question left up across a long quit cannot carry work across it | (a) Card up at quit, answered after a 10 h relaunch: no record or live stretch spans the gap, and 1500 s of focus is kept. (b) Answered, but the launch reads the pre-answer snapshot (S5 replay): nothing spans the gap, and the recorded break survives. |
| 487 | A running stretch carried across a long quit still ends where it was left | Control, for an unlocked relaunch and a locked relaunch followed by unlock. Record start→quit, 1200 s. |
| 488 | A pressed pause past the cap ends the session; a shorter one resumes it | Past the cap: record ends at the pause start with 1200 s, and a fresh stretch starts now. Control: a 10-minute pause resumes the same session with 1200 s. |
| 489 | A second absence past the cap while asked ends the session where it began | Quiet (idle-sampled) and locked variants: record ends at the second absence's start with 1500 s, and nothing spans it. Control: a short second lock is still excluded from the successor, which starts at the return with 300 s. |
| 490 | A refused long-away end stays paused with its Retry, never silently running | A committed answer makes the end journalled, then the journal is refused on a lock past the cap. Expects: `.refused`, not running, error set, stretch and work intact, no record. After re-enabling the journal, Retry ends it at the lock with 600 s. |

### RED (new checks added, product code untouched)

```
  [FAIL] 485. A pause carried across a long quit ends where the pause began
         - the paused stretch survived a 36000s quit: paused(reason: FocusContinuity.PauseReason.manual)
         - no record for the paused stretch
         - the live stretch (running) began 2026-08-29 10:40:00 +0000, before the absence ended
  [FAIL] 486. A question left up across a long quit cannot carry work across it
         - the live stretch (running) began 2026-08-29 11:30:00 +0000, before the absence ended
         - replayed answer: the live stretch (running) began 2026-08-29 11:30:00 +0000, before the absence ended
  [PASS] 487. A running stretch carried across a long quit still ends where it was left
  [FAIL] 488. A pressed pause past the cap ends the session; a shorter one resumes it
         - a pause past the cap resumed the old session instead of ending it
         - resuming past the cap kept the old stretch open from 2026-08-29 10:40:00 +0000
  [FAIL] 489. A second absence past the cap while asked ends the session where it began
         - quiet: the live stretch (running) began 2026-08-29 11:30:00 +0000, before the absence ended
         - quiet: ended 2026-08-29 11:00:00 +0000 with 1200.0s; expected 2026-08-29 11:35:00 +0000 and 1500s
         - locked: the live stretch (running) began 2026-08-29 11:30:00 +0000, before the absence ended
         - locked: ended 2026-08-29 11:00:00 +0000 with 1200.0s; expected 2026-08-29 11:35:00 +0000 and 1500s
  [FAIL] 490. A refused long-away end stays paused with its Retry, never silently running
         - a refused end left the session running with no Retry
485/490 passed
```

All 484 existing checks passed, and so did control 487.

### First GREEN attempt: three existing checks had to change

The first run after the fix failed three existing checks. Each was asserting an intermediate state that the approved restore rule now changes. Each check's purpose is kept.

**#93 `testUnansweredAwayIsHonest`** (`SelfTest.swift:5462`)

- The check restores an unanswered card 2 days later and asserted `reopened.elapsed == 600`.
- The stretch is now ended at restore. `elapsed` on an idle engine is meaningless.
- It now checks that the archived work plus any live elapsed equals 600. The intent is unchanged: "two days with the app shut must not become work".

**#109 `testIdleThenLockedNightEndsSession`** (`SelfTest.swift:6340`)

- The check asserted "restores paused" for an idle pause restored 8 h later.
- The restore now ends it. The check's real claims still hold and are still checked: the morning sample does not rescue it, and the record holds only the evening's 1800 s.

**#169 `makeAutomatic`** (`SelfTest.swift:9294`), used by "Declared-Away automatic corrections resume tracking exactly once"

- The fixture restored its own snapshot as a device to flag `isAuto`, with the declared away already past the cap. That is now a relaunch past the cap, which ends the stretch.
- The scenario is a live Undo, so the away now runs on the live engine after that restore. The Undo boundaries and expectations are unchanged.

### GREEN

The final `./build.sh --check` run (sandbox disabled) reported `490/490 passed`, `Check succeeded`, and exited 0:

```
  [PASS] 485. A pause carried across a long quit ends where the pause began
  [PASS] 486. A question left up across a long quit cannot carry work across it
  [PASS] 487. A running stretch carried across a long quit still ends where it was left
  [PASS] 488. A pressed pause past the cap ends the session; a shorter one resumes it
  [PASS] 489. A second absence past the cap while asked ends the session where it began
  [PASS] 490. A refused long-away end stays paused with its Retry, never silently running
490/490 passed
```

That is 484 existing checks plus 6 new ones. The sandboxed `swiftc -typecheck … -warnings-as-errors` is also clean.

## Concerns

1. **Behaviour change the user will notice.** A pressed Pause is now ended by any idle sample, unlock, Resume or work-app activation once it outlasts the cap. That includes the case where the user is still at the Mac with the session paused. This is what was approved.
   - The Settings explainer (`SettingsGroups.swift` `awayExplanation`) says nothing about Pause and the cap.
   - Consider adding "A pause past *cap* ends the session too." That was left out to keep scope.
2. **Two changes at relaunch.**
   - A relaunch past the cap now ends the stretch at launch for every kind. That includes a locked relaunch of a running stretch, which previously waited for the unlock; the record is identical.
   - With the ask threshold set to Never, a running stretch restored past the cap now ends. `resolve` never did that, because its cap branch sits behind `away ≥ breakThreshold`. The Settings text already promises "Past *cap* the session ends where you left" in that mode.
   - The live `resolve` still does not end past the cap when the threshold is Never. I kept that condition identical, but it looks like a separate existing gap.
3. **Distraction and watching pauses at restore.** These are measured from the last write, not the pause start, so they stay consistent with the live exemption. This is a small deviation from the literal "earliest of pause/away/saved" rule. Such a stretch still ends at the pause start when it ends.
4. **Uncovered edge.** An `.awaiting` snapshot whose saved answer was `continueSession` (the pre-away record id is in the archive, but there is no break record) is not replayed. It keeps today's behaviour: the card stays up with the gap banked, and a later answer can still continue across the gap. Ending it would write a second record with the saved pre-away record's id. The trigger needs stale preferences, a committed Continue answer and a quit past the cap together.
5. **Double Retry in one rare case.** If the answer-time check in `apply` ends the stretch and the save is refused, `SessionStore.applyAwayDecision` first files an `.awayDecision` retry. Its guard is `pendingDecisionID`, which is now nil, so it fails closed. The async `apply(state)` → `applyLongAwayResult` then replaces it with the correct `.longAway` Retry.
6. **Refusal during restore.** The store is not yet wired when `restore` runs, so a refusal there is not shown at launch. The stretch sits `.paused(.away)` past the cap with the error set. The first paused event after launch (an idle sample, work app, unlock or Resume) retries the ending, and its refusal is surfaced through the normal Retry.

## Commit

This report is committed with the fix, as one commit on `worktree-agent-a78877eb1ffcc58a9`.
