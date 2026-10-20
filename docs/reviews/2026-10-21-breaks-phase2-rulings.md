# Breaks phase 2: decisions made while building

Date: 21 October 2026. Branch `claude/bold-merkle-98e960`, from `main` at a3b8417.
Plan: `docs/plans/2026-10-20-breaks-phase2-rhythm.md` (its ten planning rulings are in the plan itself).

Every decision taken during execution, in the order it was made, each with what it costs if it is wrong. Taken from the execution ledger, which is not kept.

## Rulings

- T7 adds a read-only `SessionStore.isAwaitingPresence: Bool` for the coordinator rather than widening keep_internals — the guard exists to keep presenceGate private — cost if wrong: one accessor.
- T8's shortBreakStaysEnded builds the pre-end state by capturing engine.snapshot() before endBreak and restoring a fresh engine from it over the archive written by endBreak (the triage's "pre-end snapshot plus post-end archive") — cost if wrong: a check that models the kill window less exactly.
- implementers never run fix-reviewer; the controller dispatches it beside the task reviewer for T2, T3, T4, T5, T7, T8 and the whole branch — same as phase 1 — cost if wrong: one extra seat per task.
- T1 Minor 1 (plan-mandated span formula undercounts a range starting on a day that skips midnight) and Minor 5 (flowSuggestion `* 0.2` → `/ 5`) ride along with Task 2 — both are one-liners Task 2's comparisons depend on — cost if wrong: two lines in a Task-1 file inside Task 2's diff.
- accept workLength(.micro) == nil when Eyes is off (interface listed 1 200 unconditionally) — a tier that is off has no work length, consistent with `tiers` — cost if wrong: none.
- accept the Sao Paulo assertion as a 7-day range vs the overlapping week (tie → week; old code picked the range) — one override per kind makes the 2-vs-3-day form unobservable — cost if wrong: none.
- review Minor 7 — a quiet Eyes still makes `due == .micro` and `next == (micro, 0)`, so "Break due" shows for up to 5 min with no prompt and the countdown stops naming the main break — goes into Task 3 (Core evaluate): a quiet Eyes counts as not due and drops out of `next`; `eyesQuietNearMainBreak`'s "due == .micro" assertion becomes "due == nil, next == (.cognitive, 240)" — user-visible label truth — cost if wrong: one rule in evaluate.
- fix-reviewer (4) joins fix round 1 — dead code restating the old 15-min rule invites its return — cost if wrong: one deletion.
- the Task-2 review Minor 7 rule (quiet Eyes counts as not due and leaves `next`) moves from Task 3 into Task 2's fix round 1 — same code, same implementer context — cost if wrong: none.
- fix-reviewer (2) goes to Task 5: a planned break is never shorter than minimumRecordedSession (startBreak raises the length to it), so a taken break always records and credits — cost if wrong: a Custom 1-minute break runs 2 minutes when the minimum is set to 120 s.
- fix-reviewer (3) is the spec's own rule (§1 "never fires within 5 minutes of a main break being due"); Task 6's Eyes row detail says so ("Quiet within 5 minutes of a break, so short blocks such as Pomodoro rarely show it") — cost if wrong: one sentence.
- accept credits trimmed to 24 h before the credit being recorded (brief: "before the newest") — a far-future credit cannot push out real rests — cost if wrong: one line.
- fix-reviewer (4)'s second half (reach only matters for runs over 24 h) stays unpinned — inert below a day's unbroken run — cost if wrong: a mutation that survives.
- no tolerance on the long rest: a 15-minute break ended 10 s early leaves the long break owed (spec: "any rest of at least the long-break length") — cost if wrong: one extra long-break offer after an early End.
- accept that recording a credit older than a stored one drops the newer (window [moment − 24 h, moment]) — credits are written in time order, and a newer one after a backwards clock jump is "in the future", which sanitized(now:) drops anyway — cost if wrong: one credit lost after a backwards clock change.
- accept that an unreadable fc.breakSchedule is set aside and then read through the old tiers like an absent key — the person's old "cognitive off" intent survives a damaged blob — cost if wrong: none.
- fix-reviewer (2)–(5) join fix round 1 with (1) — each is one function and they share the same code and checks — cost if wrong: a larger fix diff.
- the phase-1 carry-over "BreakLog calendar fixed at launch" (plan Task 7) is settled by fix-reviewer (1) in Task 5; Task 7 drops it — cost if wrong: none.
- run fix-reviewer on Task 6 as well (plan listed 2,3,4,5,7,8) — it writes four settings keys and removes enabledBreakTiers, which is CLAUDE.md's "settings" class — cost if wrong: one extra review seat.
- finding (1) is Task 2's repeat rule reachable only through Task 6's picker; it is fixed in Task 6's fix round by the Task 6 implementer (the loop resumes the task's own implementer) — BreakNotice gains the work length it was raised under — cost if wrong: one more persisted key (fc.lastBreakWork).
- review Minor copy items ("Every this many breaks…", "the shortest wins") join the fix round — user-visible copy in the same file — cost if wrong: two strings.
- Task 7's Watching fix moves the hero's watching predicate into SessionStore.canTakeBreak, startBreak refuses on it, and the reminder HUD omits Start while watching (Later/Skip stay) — one rule for every surface, per the phase-1 ruling — cost if wrong: Start unavailable from a reminder during a film.
- reuse a .later row only when the prompt itself returns after a Later — BreakPrompt carries its Later count from evaluate (the snooze that dropStaleSnooze/credit/skip already clear when a rest or new run came between) and recordShown takes `continuing:`; the brief's Core check passes continuing: true and a negative (Later, rest, new reminder → 2 rows, laterCount 0) is added — the plan's rule was imprecise; the spec wants Later counts per due break — cost if wrong: one prompt field and one parameter.
- a Later'd row whose break ended without the reminder returning (stale snooze dropped, or a rest credited after markRecentPromptStarted) is closed as `.credited` (spec §5: a rest arrived before it showed) — gives every row a final outcome — cost if wrong: phase 4 counts some put-off-then-rested breaks as credited.
- fix-reviewer (3) and (4) join fix round 1 — same files, small — cost if wrong: none.
- kill-window fix = one atomic archive edit for the stretch and its break record (endBreak and expiry), then the stretch-saved restore branch drops unconditionally (only a sub-minimum break can reach it) — the fix-reviewer's probes beat both the savedAt and the reorder options — cost if wrong: one more parameter on archiveCurrentSession.
- task-review Important 2 (idle terminal checkpoint form) joins the round; fix-reviewer (4) is a doc note only — bounded, no data loss — cost if wrong: up to 90 s of one app credited to the next.
- drop the resetSystemTimeZone() call (keep the republish) — the pickers already take their zone from pickerCalendar and phase 1 never reset, so the whole app stays on one zone — cost if wrong: Settings rows after a zone change follow Foundation's own refresh timing.
- final fix wave = final-review Important 1–2, must-fix minors (BreakTier file split, VoiceOver From/To names), whole-branch fix-reviewer 1–3 (incl. plan ruling-5 wording), final-review Minor 5 (same as fix-reviewer 2), Minor 7 doc note, revert SettingsModel.write to private; Important 3 is a report correction (no code) — cost if wrong: one more review loop.

## Parked at the end

- guard hint "1h 45m" reaches VoiceOver unspoken (toggleRow passes the raw detail as the hint; DurationText.spoken exists) — Ruling: accessibility polish, same pattern as the existing awayExplanation; phase 5 copy pass — cost if wrong: VoiceOver reads "1h 45m" literally.
- check 1294 does not pin "work present, workAt absent" (follows from the code) — Ruling: covered by reading; add when lastBreakNotice is next touched — cost if wrong: an unpinned branch.

## Left for later phases (from the final review's triage)

- **Phase 3:** a check that the quiet refresh paths leave the break clock and
  the reminder callback alone; the idle `onBreak` checkpoint rule, if a new
  path ever ends a session without closing its break; a session and a break
  both under the minimum, killed before the state save, which is recorded as a
  cap-length rest; a damaged `floors` value dropping the whole break clock;
  checks for the snooze clamp, a credit at a gap's edge and duplicate credits;
  `logShown`'s internal access.
- **Phase 4:** what `.credited` means for a put-off row closed by a rhythm
  change or a clock that ran ahead; reading `guardMinutes` through ruling 3 to
  get the guard's real time; two day rows for one calendar date after a
  time-zone change; the "run back to the first long gap" walk repeated in
  `BreakCycles` and `BreakReminder`.
- **Phase 5:** "Take N minutes" naming the rhythm's own length when the
  minimum session raises it; the "Working hours" panel title repeating its
  switch; durations in Settings hints read to VoiceOver unspoken.
- **Kept by design:** Pomodoro's long break stays owed after a long break ended
  even seconds early (spec §1: "any rest of at least the long-break length").
