# Whole-gap away: one question per absence, return counts at once, answers in parts, labels learned

Date: 20 November 2026. Status: approved by the owner on 20 November 2026,
with the agent-ask threshold at 30 minutes and the label-approval setting in
section 6. Phase 1 in progress.

Related: `2026-08-22-away-prompt-design.md` (the question and its two
surfaces), `2026-11-17-self-answering-away-design.md` (unbuilt draft: clear
absences recorded without a question), `2026-11-17-activity-aware-sessions-design.md`
sections 6 and 7 (corrections store, the on-device model),
`2026-10-12-name-suggestions-design.md`.

## Why: what happened on 20 November

Read from the live data folder (beats, machine events, sessions, metadata
journal); nothing was changed. Settings at the time: long-away cap 1 hour,
`countsAgentAppInFront` and `countsKeepAwake` on, idle threshold 5 minutes.
KeepingYouAwake held the display on all morning: no lock, sleep or display
sleep after 09:03:26.

| Local time | Evidence | What Daybook did |
|---|---|---|
| 09:03:26 to 09:50:30 | Keyboard and mouse in Claude and Codex | Coding session running |
| 09:52 to 10:50:30 | No input, Claude in front | Counted as an agent at work |
| 10:50:30 | Quiet reaches 3,600 s, the cap | `AgentPresence.lastSeen` returns nil (`quiet < cap` guard) |
| 10:51:03 | Quiet | Coding session ends |
| 10:51:03 to 11:10:26 | Quiet | The away question covers only this, 19 min 23 s |
| 11:10:26 to 13:05 | Quiet, display on | Never asked about |
| 13:06 to 13:22 | Finder, Gemini, Claude in use | Paused behind the open question; nothing recorded |
| about 13:22 | Owner answers "Brunch" | Break record 10:51:03 to 11:10:26 |
| 13:23:05 | Input | A new session begins |

The Coding session 09:03:26 to 10:51:03 lasted 6,457 s and its activity shape
counted 6,424 s, yet it was saved with `workSeconds` 5,294 s. The 1,163 s missing
is the Brunch record's length to the hundredth of a second.

## Problems

- **P1. Agent credit ends at the cap, silently.** After an hour of quiet the
  agent stops counting, whatever is running, and nothing tells the person.
- **P2. The question covers a slice, not the absence.** The person was away
  from 09:50:30 to about 13:05:40; the question covered 19 minutes in the
  middle. What closed the away interval at 11:10:26 is not yet known.
- **P3. An open question blocks recording.** Sixteen minutes of hands-on use
  after return were recorded as nothing.
- **P4. The new session starts at the answer**, not at the return.
- **P5. Answered away time is subtracted twice.** Probable cause: `resolve(away:)`
  adds the absence to `totalPausedDuration` and the paused spans at once; the
  answer then ends the session at the absence's start, so the same seconds are
  both outside the session and deducted from it.
- **P6. The app logs about 500 lines an hour at error level**, in bursts of
  about 35 roughly every 15 minutes, with all text private, so neither the
  owner nor a developer can tell what they are.

## The owner's rulings (20 November)

1. Screen on with no input is not a session by itself: a phone call with the
   display on records nothing.
2. An agent at work may be left alone for minutes or hours, while the person
   watches TV or sleeps, across several apps. Daybook cannot tell these apart
   from evidence alone, so it asks, about the **whole** gap, once.
3. The answer may be in parts: a 9 to 11 gap can be answered "9 to 10 TV, 10
   to 11 brunch", any number of parts, each with an optional note.
4. On return, keyboard and mouse use on an unlocked, lit screen is activity
   and is recorded from that second, in the background, whether or not the
   question is open. The question's two surfaces (menu bar when the screen
   stayed on, centred over a blurred screen after a lock or sleep) stay as
   they are; neither blocks recording.
5. Daybook learns from what the person names and how they file it, by app,
   weekday and time of day, says plainly that it is learning, and files on its
   own only what it is sure of.
6. The log flood is found and fixed.

## Goals

1. One absence, one question, covering from the last human input to the first
   returning input, to the second.
2. Recording restarts at the first returning input, at that second.
3. The answer can be split into parts that tile the gap exactly.
4. No answered second is counted twice or lost.
5. Labels and away answers are suggested from the person's own history, and
   applied without asking only above a stated confidence.
6. Every diagnostic line says where it came from, at the right level.

## Non-goals

- No new event source or permission.
- No change to the cap's meaning for ending a session: a gap at or past the
  cap still ends the session where the person left.
- No proposed Activity Rules (activity-aware sessions section 6 stands).
- No model-written figures or times; the model only proposes labels.

## Anti-goals (a failure even if it works)

- Agent-only time recorded as work after the person said they were away.
- A question that names a range the person cannot recognise.
- A return the person spends working that is recorded as nothing.
- An answer left alone treated as evidence of preference.
- Learning the person cannot see, or cannot forget.

## Design

### 1. The absence and its edges

The absence starts at the last human input (HID) before quiet and ends at the
first confirmed human input after it. Agent credit, keep-awake and watching
can sit inside an absence but never move its edges. Each absence keeps the
stretches inside it, in order, with their evidence: `agent` (which apps, from
beats), `watched`, `quiet`, `locked`, `asleep`.

Agent-only time (no input, an agent or keep-awake as the only evidence) is
treated by length:

- **Short** (under the agent-ask threshold, proposed 30 minutes, the existing
  full-prompt default): counts as work silently, as today. Reading a long
  answer while Claude works is not an absence.
- **Long** (at or past the threshold): the whole agent stretch becomes
  provisional. The menu bar shows it as "Claude working, not yet counted"; it
  is not banked into work, goals or totals until the person answers. The
  question pre-fills it as a part ("Claude was working, 09:50 to 10:50") so
  keeping it is one click. Answering any part as away or a break moves that
  part out of work atomically.
- An absence left unanswered never banks agent-only time as work.

Past the cap, agent evidence is still shown in the gap's evidence.

### 2. One question for the whole absence

The question opens at return (quick or full surface by the existing tier
rule) and covers the absence as defined in section 1. Inner events (the cap
reached, the session ended at the cap, a second quiet) do not open a second
question or narrow the first. The 11:10:26 closer is found by replaying 20
November in a check before any change. Candidates, from the review: an app
activation while idle-paused ending the pause without HID input; a low or reset
HID reading taken as input; a timer calling `resolveAway()`.

The pending question is durable: saved with its range, parts and evidence so it
survives relaunch and midnight. Real input ends an absence; a second absence
after real input is a second question, never merged into the first. A second
absence with no real input between (only machine events) extends the first.

### 3. Return records at once

The first confirmed human input on an unlocked, lit screen:

- with no session running: the auto-start rules run from that second, with
  their `startAfter` back-dated to it, exactly as on any other return;
- with a session that was running before the absence and has not ended (gap
  under the cap): that session resumes counting from that second, the gap
  excluded as a pause until answered (the review was unanimous: resume, not
  fresh, so pre-absence work is not orphaned);
- with a session the cap ended: a new automatic session starts from that
  second when the auto-start rules match.

The open question stays open and answerable; answering it later never moves
the return's start.

### 4. Answers in parts

The card shows the absence as one bar with its start and end to the minute
(seconds kept internally). "Add a part" splits the selected part at a time the
person picks. Each part has a time range, an answer (the existing answers:
break kinds, away, "I was working"), and an optional note. Parts always tile
the absence: no gaps, no overlaps; removing a part merges it into its
neighbour. A single-part answer is today's one-click answer, unchanged.

Parts are half-open intervals `[start, end)` with second-precision edges; the
card edits to the minute and keeps the absence's own outer seconds. A part is
at least one minute long; a part shrunk below that merges into its
neighbour. Each part maps to one effect: a break kind makes a break record
(`breakOrigin = .answered`, no new enum case), "away" makes uncounted time,
"I was working" puts the part back into the session's work. Notes use the
existing per-session note store. All parts, notes and any learned correction
from one answer are committed as one journal change, and Undo removes them
as one change. Edges that cross midnight split at midnight for the day's
records only; DST uses absolute time, never wall-clock arithmetic.

### 5. No double counting

Answered absence time is excluded from a session once: either inside it as a
paused span, or outside it because the session ends at the absence's start,
never both. P5 is plausible, not proven: the review also named a stale
pause, a shadow absence, restore accounting or a wrong return anchor. The
replay check first reproduces today's 5,294 s, then requires, on the new code:

- a single "Brunch" answer for 19 min 23 s inside the old behaviour's range:
  the session keeps its 6,457 s minus its own counted pauses, no less;
- a whole-gap answer 09:50:30 to 13:05:40 as Brunch: work ends at 09:50:30
  and the agent hour is not counted;
- the same gap split "09:50:30 to 10:50:30 Claude working, rest Brunch": the
  agent hour is counted once, the rest is one break record.

### 6. Learning labels

Extends the corrections store (`corrections.json`, activity-aware sessions
section 6); no second store.

- **Context.** A learned entry adds weekday group (weekday or weekend) and a
  time-of-day bucket (night, morning, midday, afternoon, evening) to the
  existing fingerprint.
- **What is learned.** Session categories and names the person chose, per-app
  activity names within a session, and away-part answers (for example "Lunch"
  on weekdays around 12:30 for 45 to 75 minutes).
- **How it is offered.** Suggestions pre-fill the split card's parts and the
  category picker, marked with the existing sparkle.
- **Filing without asking.** Only when the same context has at least 5 answers
  from the person, at least 90% agreeing (so 5 of 5, or 9 of 10), none
  vetoed, and the last one within 30 days. The record carries
  `source = correction` and the sparkle; one click changes it. For one person
  this is mostly suggestion-only for weeks, which is intended.
- **Negative feedback.** Changing an auto-filed label vetoes that label for
  the context and resets its agreement count, so a wrong pattern is not filed
  again. Answers the person merely left alone never count.
- **Cold start.** A context with no history falls back to the same app's
  history without the weekday and time buckets, as a suggestion only.
- **Transparency.** Settings gets a "What Daybook has learned" list: each
  pattern in plain words, how many answers it rests on, and Forget. The first
  time a suggestion appears, one line says "Daybook suggests this from your
  past answers. Settings › Learning shows what it has learned."
- **Model role.** The on-device model (activity-aware sessions section 7) may
  propose a label for a session no learned pattern covers. It never writes
  times or figures and never files an away part.
- **The person decides who applies labels** (owner ruling, 20 November).
  Settings › Learning has one choice, "Labels Daybook suggests":
  - **Apply when sure** (the filing rule above; marked with the sparkle,
    one click to change);
  - **Ask me first** (default): suggestions wait in a short review list on
    Today and on the session, each with Approve and Change; nothing is filed
    until approved;
  - **Off**: no suggestions.
  It covers learned labels and model labels alike. It never covers times:
  edges and lengths come only from evidence and the person's answers.
  Builds on Phase C's "Let AI assign categories" switch (`AIAssignSetting`,
  `fc.aiAssignsCategories`): its off state already behaves as Ask me first
  (suggestion with Use, nothing written, ruling C8) and on as Apply when sure,
  so the change is a three-way setting with a true Off that stops asking.
  Confirmed with the Phase C session on 20 November.

### 7. Diagnostics

`Diagnostics.log` gains a public call-site tag (file and line) and a level:
routine events (auto-paused, recovered records) at `info`, failures at
`error`. The message text stays private. Once a build with tags runs for a
day, the burst source is identified from the live log and fixed at its root.

## Phasing (each ships on its own)

| Phase | Contents | Gate |
|---|---|---|
| 1 | 20 November replay check; a return needs counted input (the phantom reset); a return is recorded from its second while the question waits (P3, P4); P5. Plan: `docs/plans/2026-11-20-whole-gap-away-phase-1.md` | Replay reproduces today's numbers on old code; new asserts pass; relaunch with an open question; fix-reviewer; a second-model code review |
| 2 | Diagnostics tags and levels; then the burst fix | Burst source named from a tagged live log |
| 3 | The whole-gap question (sections 1, 2) with answers in parts (section 4), the agent-only rule (P1) and the section 5 targets | Checks for tiling, minimum part, undo as one change, relaunch, midnight, DST |
| 4 | Learning context, suggestions, filing when sure, Settings › Learning | After Phase 3. Checks for thresholds, veto, cold start, forget |

Re-sequenced on 20 November after the probes: the whole-gap question ships
with parts, because a single answer for a whole gap could not keep an agent's
hour as work.

Probe findings (20 November): the 11:10:26 question came from a system
idle-timer reset with no key, click or scroll; `PresenceGate` took it as a
person. The last real input was about 09:51:03, not 09:50:30 (beats are
30-second buckets), and the owner was back at 13:01:00. Phase 2 can run in parallel with Phase 1. Phase 4 must not touch
files the in-progress model phase (activity-aware sessions section 7) is
changing.

## Open questions for the owner

- The agent-ask threshold (section 1): 30 minutes proposed.

## Review record

20 November 2026, plan-reviewer panel on the first draft.

| Model | Verdict | Confidence |
|---|---|---|
| GPT (gpt-6.1-terra) | Reject | 0.91 |
| DeepSeek (v4-pro) | Approve with changes | 0.80 |
| Second approving reviewer | Approve with changes | 0.85 |
| Gemini | Did not run (headless permission error) | n/a |

Adopted: agent-only time held provisional past a threshold (GPT, DeepSeek);
the 6,424 s target replaced, as it contradicted a whole-gap answer (GPT);
resume, not fresh, under the cap (unanimous); P5 treated as a hypothesis to
prove by replay (GPT); durable pending question and the second-absence rule
(GPT); half-open parts, minimum length, effect mapping, atomic commit (GPT,
DeepSeek); veto resets and cold start for learning (all); Phase 1 includes P1,
Phase 4 after Phase 3, fixture first (all).

Not adopted: keeping all agent credit counted until answered (one reviewer):
it would bank unclaimed time on an unanswered gap, against the anti-goals.
Holding all agent time uncounted (GPT) was narrowed to long stretches, so
reading while an agent works is not turned into a question.
