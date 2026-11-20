# Whole-gap away, phase 1: a return is a person, and is recorded at once

Spec: `docs/specs/2026-11-20-whole-gap-away-design.md` (approved 20 November
2026). Branch: `claude/activity-detection-session-timing-e6c90e`.

Phase 1 is the proven bug fixes, with no new interface. The whole-gap question
and the agent-only rule ship in phase 3 together with the split-answer card,
because a whole-gap question with one answer would leave no way to keep an
agent's hour as work.

## Root causes, proven by probe (20 November)

A Core probe drove `SessionEngine`, `QuietSampler` and
`AgentPresence.lastSeen` once a second through the morning, as
`SessionStore.observeIdle` does.

1. **Phantom return (P2).** With no reset, the engine ends the session at the
   cap and asks nothing. With one system idle-timer reset at 11:10:26 and no
   key, click or scroll (the beats' counters show none between 09:51 and
   13:01), the idle pause ends and the question opens for 10:51:02 to
   11:10:26, 1,164 s, at 11:10:26: exactly what the owner saw. Something
   reset the HID idle timer without input (an app declaring user activity
   does this); `PresenceGate.observe` treats any reading under 5 s as a
   person.
2. **The answer restarts the session from the phantom (P4).** After "Brunch"
   at 13:22 the engine's running session starts at 11:10:26, so the
   unattended 11:10 to 13:01 stretch can be counted. Input from 13:01 to 13:22
   records nothing while the question waits (P3).
3. **The 19-minute loss (P5)**, traced by a full-store probe: the question
   opened without input, so the quiet sampler was never reset and still
   measured from where the agent stopped (10:51:02). While the question was
   up, `noteQuietWhileAwaiting` opened a second absence back-dated to
   10:51:03, inside the absence already banked; an hour later it was held
   there, and the answer subtracted the 1,163 s twice. Any delivered app
   activation while idle-paused does this (`(.paused(.idle), .appActivated)`
   treats an activation as input); an idle-timer reset alone does not,
   because the presence path resets the sampler. So the live trigger at
   11:10:26 was most likely the assistant activating itself, not the reset.

## Outcome (20 November)

Built and checked, uncommitted, 1771 checks passing before the last review
fix: the gate carries quiet across uncounted idle resets (and a wake's
second drop needs input); an activation while idle-paused with no counted
input waits for the first counted input; the second absence is floored at
the later of the return and the restore anchor; the quiet sampler never
reports under five seconds. Fix-reviewer findings and a second-model review
(GPT fix first; one approve; one request changes on points by design) were
applied. Task 3's background recording is largely met by these fixes (the
question now opens at the real return, and time after it is credited on
answering); the menu bar still shows the question rather than a running
count while it waits, which phase 3 revisits.

## Tasks

Each task: a check that fails on the old code first (mutation-tested in a temp
copy), then the change, then `./build.sh --check` with the sandbox disabled.

### Task 1. The 20 November replay check

`Sources/Verification/AwayGapReplayChecks.swift`, registered at the end of
`registeredTests`. A fixture drives the engine second by second from
`SelfTest.base`-relative times (09:03:26 becomes base, all others offsets, so
it holds in any time zone): input to +47:37, agent quiet with Claude in front
to the cap, a phantom reset at +2:07:00, real input from +3:57:34, answer at
+4:18:34. It reports the engine's state changes and records. Phase 1 asserts
are added by tasks 2 to 4; the fixture alone reproduces today's numbers.

### Task 2. A return needs input, not just a reset idle timer

- `Sources/Core/InputDensity.swift`: `InputCounters` gains `rightClicks` and
  `mouseMoves` (`CGEventSource.counterForEventType`, no permission needed, as
  for the existing three).
- `Sources/Core/PresenceGate.swift`: `observe` takes `inputMoved: Bool` (any
  counter advanced since the previous sample). After quiet of at least 60 s
  since the last confirmed input, a reading under 5 s confirms presence only
  when `inputMoved`; otherwise it is quiet measured from the last confirmed
  input (the existing `quietSeconds` rule). Wake suppression is unchanged.
- `Sources/App/SessionStore+Presence.swift` `observeIdle`: reads the counters
  each sample and passes the delta.
- Checks: phantom reset, no counter change: still quiet, idle pause holds,
  no question. Reset with one key: return. Reset with mouse moves only:
  return. A wake with the old suppression still behaves as before.

### Task 3. A return is recorded from its second, question or not

- `Sources/Core/SessionEngine+Absence.swift` and
  `SessionEngine+AwayDecision.swift`: while `.awaitingUserDecision`, the
  first confirmed input sets `awayReturnedAt` to that moment (today it stays
  at the decision start). Answering then resumes counting from
  `awayReturnedAt`, never from the decision start, so unattended time between
  is never work.
- The open question no longer holds recording: from `awayReturnedAt` the
  session's time after the return is counted live (the menu bar shows it),
  and the answer only settles the gap before it. Exact mechanism (a running
  state with a pending decision versus counting inside the awaiting state)
  is settled in the task after reading `SessionEngine+Corrections` and
  `+Restore`, where the awaiting state is saved and restored; the snapshot
  format must stay readable by 1.3.5 (no new enum cases).
- With no session running when the person returns, activity-rule automation
  runs as on any other return, from the return second.
- Checks: return at +3:57:34, answer at +4:18:34: the session counts from the
  return, the 21 minutes before the answer are work, nothing between the
  phantom and the return is. Relaunch with the question open and a return
  recorded: the return moment survives. Midnight between gap and return.

### Task 4. The 19-minute loss

Written from the probe agent's report: the path, the fix at its root, and a
check that the Coding session keeps its counted 6,456 s (to the second) when
"Brunch" is answered for the slice the old engine asked about.

### Task 5. Review and ship gates

- `fix-reviewer` agent on the diff (persistence, session state, time
  arithmetic).
- Deliberation code review of the diff.
- `./build.sh --check`, and `TZ=Europe/Berlin ./build.sh --check`.
- Commit subjects written for users; ship with the `ship` skill when the
  owner says so.

## Files this phase may touch

`Sources/Core/InputDensity.swift`, `PresenceGate.swift`, `QuietSampler.swift`,
`SessionEngine+Absence.swift`, `+AwayDecision.swift`, `+PausedTransitions.swift`,
`+Transitions.swift`, `+Restore.swift`, `+Corrections.swift`,
`Sources/App/SessionStore+Presence.swift`, `+Away.swift`, `+Automation.swift`,
`AwayPrompter.swift`, new checks. Not: Phase C files (`AIAssignSetting`,
`CategoryAssistant*`, `AILabel*`, `SettingsGroups+AICategories`,
`SessionStore+AILabels`), `SessionEngine+AwayCorrections.swift` (Phase C
branch edits it), `enum Diagnostics` (phase 2 session).
