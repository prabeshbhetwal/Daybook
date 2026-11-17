# Self-answering away: Daybook records clear absences itself

Date: 17 November 2026. Status: draft for the owner's approval. Design only;
nothing here is built.

Related: `2026-08-22-away-prompt-design.md` (the question and its two
surfaces), `2026-10-19-breaks-design.md` (break records and `breakOrigin`),
`2026-10-10-machine-events-design.md` (the event log and `GapAnatomy`),
`2026-11-17-activity-aware-sessions-design.md` sections 2, 4 and 6
(provenance, the origin mark, the corrections store).

## Why

On 17 November 2026 the owner came back to the Mac after 17 minutes and Daybook
asked "What happened while you were away?" with four buttons (It Was a Break,
I Was Working, I Was Away, Start Fresh) and a name field. He judged it a very
poor implementation. Daybook's own machine-event log for that absence reads:

| Time | Event |
|---|---|
| 22:05:43 | Screen locked |
| 22:06:08 | Mac went to sleep |
| 22:23:14 | Mac woke |
| 22:23:37 | Screen unlocked |

Daybook had hard evidence that nobody used the Mac for the whole absence, and
still asked a four-way question with "It Was a Break" filled in as the
suggestion, the same suggestion it gives every absence.

The code confirms the cause. `AwayTrigger` (`screenLock`, `systemSleep`,
`idle`) is held in one slot for the first trigger only, nothing reads it for
logic, and it is dropped when the question is answered. The state
`.awaitingUserDecision(away:lastApp:)` carries no evidence at all.
`AwayAnswerGrid` hardcodes "It Was a Break" as `prominent: true`. Nothing
learns from the person's past answers. Meanwhile the evidence the card needs
already exists in Core: `MachineEventLog.events(in:)` and
`GapAnatomy.of(_:in:events:)`, which the History view uses to say whether a
gap was locked, asleep, off or unexplained.

The owner's ruling: **answer first, ask rarely.** Daybook records a clear
absence itself, says why in plain words, and leaves one Change control. The
sketch he approved:

```
Away 17 min · 10:05 – 10:23 pm · Mac was asleep
Recorded as a break.                  [Change]  [Name it]
```

## What already exists (searched before specifying)

| Need | Already in the code | Used here |
|---|---|---|
| What the Mac did during a stretch | `MachineEventLog.events(in:)` (Core), `GapAnatomy.of(_:in:events:)` (Core) giving `unexplained`, `locked` (lock, display off, other user), `asleep`, `off`, `uncertain` stretches | The clear-absence test. No new event source and no new `AwayTrigger` case |
| A video or call holding the screen | `WatchDetector`, `.watching` pause, `endWatchingPause` writing a "Watching" rest with `breakOrigin .watching`; never asked about | Unchanged. Already self-answering |
| An AI agent at work | `AgentQuietPolicy`: `countAsWork` (no pause, default), `pauseQuietly` (no question), `ignore` (quiet is an absence) | Unchanged. Only `ignore` reaches this design, as an ordinary absence |
| Thresholds | "Ask me after" (`fc.threshold`, 15 min), "Stop session after" (`fc.longAwayCap`, 4 h), under 5 s dropped | Unchanged. Under the ask threshold stays silent; at the cap the session still ends |
| Applying an answer | `SessionStore.resolve(_:label:expectedID:)` → `SessionEngine.decide` → `apply`, writing a receipt (`AwayDecisionReceipt`) through the correction journal (`DecisionHistory`) | Self-recorded answers go through exactly this path |
| Changing a past answer | `reviseAwayDecision`, `undoAwayDecision` (`SessionEngine+AwayCorrections`, `SessionStore+Away`), and in `Sources/Surfaces/Story/`: `StoryDecisionRow` ("Count as Focus", "Call It a Break", "Leave Uncounted"), `StoryBreakRow` ("Change How This Counts", "Name It", "Undo") | The Change control and the timeline use these |
| A transient notice with Undo | `RewardHUD.show(title:detail:symbolName:undo:)`, used for auto-started sessions; the quick panel (`AwayQuickPanel`) | The quick panel shows the recorded line |
| Quick and full prompt tiers | `AwayPromptTier.tier(forAbsence:fullPromptAfter:)`, `fc.fullPromptAfter` (30 min) | Kept for the unclear case only |

Not existing, contrary to what the breaks spec planned: the `.prompted`
auto-record ("Recorded a 12-minute break · Undo" after a break prompt) is
declared in `BreakOrigin` but never written. This design does not depend on it
and does not build it.

## Goals

1. A clear absence is recorded without a question, with its reason on the card
   and one Change control.
2. Break versus uncounted away is chosen by a fixed, tested rule, then by the
   person's own past answers for similar gaps once there are enough of them.
3. The unclear case asks one plain question with three answers, each named by
   what it does to the record.
4. "Start Fresh" leaves the card and becomes an action on the session.
5. Every automatic answer is changeable later from the day's timeline,
   loses no time, and survives relaunch, a second absence and midnight.
6. One provenance vocabulary and one corrections store, shared with
   activity-aware sessions.

## Non-goals

- No change to the thresholds, the cap, idle detection, watching pauses or the
  agent setting.
- No new permission, no new event source, no new `AwayTrigger` or `BreakOrigin`
  case (both decode with no fallback; an older build would set the live
  snapshot aside, as the machine-events spec found).
- No inference of what the person did while away beyond break or away.
- No building of the breaks spec's `.prompted` auto-record.

## Anti-goals (a failure even if it works)

- Daybook counts time as work that the person did not claim. A self-recorded
  answer is never "I was working".
- A self-recorded answer that the person cannot see, or cannot change in one
  click.
- A default that teaches itself: an answer the person merely left alone is not
  evidence of what they want.
- Losing or rewriting counted time. A change of answer moves time between
  states exactly as the existing corrections do and nothing else.
- Any figure or sentence on the card written by the on-device model. All text
  here is code-written.

## Approaches considered

| Approach | Trade-off | Verdict |
|---|---|---|
| **A. Classify at return from the event log, apply through the existing decide path, tag the receipt with its source** | Reuses `GapAnatomy`, the decide path, receipts, the journal and the timeline rows. New code is one pure classifier, a default rule, one source field and the card | **Chosen** |
| B. Carry evidence in the engine state (new `AwayTrigger` cases or a trigger list on `.awaitingUserDecision`) | Puts evidence where the decision is, but changes persisted state that older builds decode with no fallback, and duplicates what the event log already records | Rejected: downgrade risk, duplication |
| C. Keep asking, but preselect the likely answer | Smallest change, but still interrupts after an absence Daybook already understands, which is the owner's complaint | Rejected: contradicts the ruling |

## Design

### 1. Which absences are clear

The classifier runs when an absence reaches the point where today's engine
would ask: at or above "Ask me after" and below "Stop session after". It is a
pure Core function:

```swift
enum AbsenceReading: Equatable {
    case clear(MachineState, covered: TimeInterval)   // locked, asleep, screenOff
    case unclear
}
static func read(_ absence: DateInterval, events: [MachineEvent]) -> AbsenceReading
```

The store passes `machineEventLog.events(in:)` for the absence, widened by the
two seconds `GapAnatomy` already allows. The absence is `pendingAwayRange`: it
ends at `awayReturnedAt`, which the snapshot persists, so a relaunch reads the
same interval.

The reading is built on `GapAnatomy.of(absence, events:)`:

- **Covered time** is the total of its `locked`, `asleep` and `off` stretches.
  `GapAnatomy` already counts display-off inside `locked`. **Live time** is the
  total of its `unexplained` stretches: no event says the Mac was locked,
  asleep or off. No input arrived in any of it, because the whole interval is
  an absence the engine already measured from input; no new input source is
  read.
- **Clear** when all three hold:
  1. live time is at most `clearLiveMax` = min(10 min, max(5 min, 20% of the
     absence)). This allows the usual stretch between the last input and an
     automatic lock or display sleep, and nothing much longer: half an hour of
     a live screen before the Mac slept is not clear, because the person may
     have been reading it;
  2. the last covered stretch ends within `returnGrace` (120 s) of the return,
     so the person came back by waking or unlocking the Mac, not after sitting
     at a live screen;
  3. there is no `uncertain` stretch (a crash found at the next launch).
- **The reason** is the deepest state across the covered time, as
  `GapAnatomy` orders it: `asleep` reads "Mac was asleep"; `off` reads "Mac was
  off or Daybook was closed", the literal meaning of that state (a shutdown
  inside a running session otherwise ends it at the cap or at relaunch, as
  today);
  `locked` from a lock reads "Mac was locked"; `locked` from display-off alone
  reads "Screen was off". When the named state's own time falls short of the
  absence by a minute or more, the reason says how much, counting only that
  state: "Mac was asleep for 14 of 17 min". The words never claim more than
  the events show.
- **Unclear** otherwise. Its reason is just as literal, first match wins: "No
  record of what the Mac did" when there are no events; "Mac activity is
  unclear" when an `uncertain` stretch is inside it; otherwise "Screen stayed
  on". Missing evidence is never described as a screen that stayed on.

**Where it runs (my call).** The engine enters `.awaitingUserDecision` exactly
as today, so the pending question is persisted before anything else happens
and a crash at this point leaves today's behaviour. On the same main-actor turn
in which `SessionStore` publishes `pendingAway`, it reads the absence and
publishes the reading beside it. If the reading is clear and section 2 gives
an answer, the store calls `resolve` with that answer and a source of
`builtIn` or `correction` before returning. `AwayPrompter` presents only after
reading that published reading, so a clear absence never shows the question,
even for a frame: it shows the recorded notice of section 3 instead. Because
the answer is applied in the same turn as the return, the second-absence path
cannot start between them.

The owner's 17-minute case: locked at 22:05:43, asleep from 22:06:08, awake at
22:23:14, unlocked at 22:23:37. Live time is the moment between the last input
and the lock, the last covered stretch ends at the unlock, which is the
return, and nothing is uncertain. Clear, reason "Mac was asleep".

The four kinds the brief names, and where each lands:

| Absence | Today | Under this design |
|---|---|---|
| Locked, asleep or screen off, returned by unlocking or waking | Asked, four ways | **Clear.** Recorded by section 2, the card states the reason |
| An agent kept working | Governed by the agent setting: counted, paused quietly, or (`ignore`) an ordinary absence | Unchanged. With `ignore` the absence is read like any other |
| A video or call held the screen | Watching pause, recorded as "Watching", never asked | Unchanged. It already answers itself; its row gains the source mark (section 7) |
| Screen on, unlocked, no input, nothing holding the screen | Asked, four ways | **Unclear.** Asked with three plain answers (section 4) |

### 2. Break or uncounted away for a clear absence

A clear absence is recorded as one of two uncounted outcomes: **break** (a
`.breakTime` record, today's "It was a break") or **left uncounted** (no
record, today's "I was away"). Daybook first finds a candidate, then checks it:

1. **Candidate from the person's own pattern** (phase 2). Among the last 4
   explicit answers (defined below) for absences with the same fingerprint, at
   least 3 agree. That answer is the candidate, with source `correction`.
2. **Otherwise, candidate from the fixed rule**: up to `breakDefaultCeiling`
   (60 min) is a break; longer is left uncounted, with source `builtIn`. *My
   call:* 15 to 60 minutes with the Mac locked or asleep is what a break is,
   and the breaks analysis should see it; hours are not a break and would
   distort the break figures. The boundary is a cliff on purpose: one
   deterministic number is easier to trust and to check than a blend.
3. **The check.** Daybook records the candidate itself unless the candidate is
   "counted as work" (a pattern can say so; the fixed rule never does) or is
   in the fingerprint's vetoed set (section 8). In either case it records
   nothing and asks with the section 4 card, which has no default, so the
   answer is the person's own. A locked Mac never leads to counted time on
   Daybook's own say, and an answer the person rejected is never recorded
   again by Daybook until they choose it themselves.

**The fingerprint** (all computed by code, all local, coarse on purpose so
that a pattern can form):

| Part | Bands |
|---|---|
| Length | 15 to 30 min, 30 to 60 min, over 60 min |
| Time the absence began, by the calendar the day views use | before 12:00, 12:00 to 17:00, from 17:00 |
| What the Mac did | locked or screen off, asleep |

Unclear absences are always asked and have no default, so they need no
fingerprint of their own; an answer to an unclear card teaches the
fingerprint of its length and time with the Mac state "locked or screen off"
only if live time was under half the absence, and teaches nothing otherwise.

**What counts as an explicit answer.** A choice the person made, not one
Daybook made for them:

- any button on the section 4 card (it has no default);
- any choice under Change on a recorded card (choosing the current answer
  changes nothing);
- any change of an away answer in the day's timeline.

Accepting what Daybook recorded teaches nothing. *My call:* otherwise
Daybook's own guesses would come back as the person's preferences, and the
default would reinforce itself. Learning therefore comes from the
person's own choices, which is exactly what a default should follow. One
absence holds at most one explicit answer: changing it again replaces that
absence's answer, and undoing it removes it, so repeated edits to one gap
cannot manufacture a pattern. Naming a break is not an answer about
counting.

**How the card states its reason** (all strings code-written, figures from
code):

| Source | Answer line |
|---|---|
| Fixed rule, break | Recorded as a break. |
| Fixed rule, uncounted | Left uncounted. No break added. |
| Learned, break | Recorded as a break, as you chose 3 of the last 4 times for an evening gap like this. |
| Learned, uncounted | Left uncounted, as you chose the last 3 times for an evening gap like this. |

Both figures are counted from the entry's actual explicit answers: N agree out
of M (3 or 4). When N equals M the line reads "as you chose the last M times",
otherwise "as you chose N of the last M times". Checks cover 3 of 3, 3 of 4
and 4 of 4.

The time word comes from the band: "morning", "afternoon", "evening". The
title line always carries the reason:
`Away 17 min · 10:05 – 10:23 pm · Mac was asleep`.

### 3. The recorded card and Change

```
Away 17 min · 10:05 – 10:23 pm · Mac was asleep
Recorded as a break.                [Change ⌄]  [Name it]
Recorded by Daybook                    (from your past answers, when learned)
Deep work carries on: 2h 14m so far today.        Start Fresh
```

- **Where it shows.** On return, in the quick panel under the menu-bar item
  (non-activating, as today). The panel's fade pauses while the pointer is
  over it or VoiceOver focus is in it, and never runs while it is key, as
  today. It is a statement, not a question: the full-screen prompt is never
  used for a clear absence.
- **It stays until seen.** The same card is the top card in the popover and
  the dashboard until the person has had it on screen there (the popover or
  the dashboard opened with the card in view). Until then, the menu-bar item
  carries a small mark with the accessibility label "Daybook recorded an
  absence. Open to review." (treatment through design review; never colour
  alone). A person who went straight back to work and missed the panel still
  sees that something was recorded. Unseen answers queue: the card shows the
  latest and a line "1 more recorded while you were away", which opens the
  day's timeline at it. Opening the timeline with a queued answer in view
  marks it seen, as does the next day's first popover opening, so the mark
  never outlives the day after. VoiceOver announces each answer once, at
  return, not on every popover opening. After
  that, answers live in the day's timeline.
- **Change** is a pull-down button with a chevron. Its accessibility label
  names what it changes and the current state: "Change how the 17-minute
  absence counts, now a break". The menu lists the three answers, the current
  one ticked:
  - It Was a Break (not counted, kept as rest)
  - Leave Uncounted (not counted, no break added)
  - Count as Work, Including Away From the Mac (counts on this session)
  Choosing one undoes the receipt and answers it again, the path the timeline
  rows already use (`SessionStore+History`: `undoAwayDecision`, then
  `applyAwayDecision(reviewing: true)`). Counting as work is always reachable
  here and never offered first for a locked or asleep Mac.
- **Name it** shows only for a break and uses today's name field ("Name it:
  dinner, a call, a walk", 24 characters). It renames the break record; it is
  not an answer.
- **"Recorded by Daybook"** is the source mark of section 7, shipped with this
  card in phase 1, so an automatic answer never looks like the person's own.
  Its text meets the app's 4.5:1 contrast rule; quiet means small, not faint.
- **Start Fresh** sits on the session line, apart from the answers: it is
  about the work from now on, not the past (section 5).
- **Left uncounted has no record and still has a row.** The receipt is the
  row; the existing revise path turns a receipt with no `insertedRecord` into
  a break or into counted work (`reviseAwayDecision` builds the record from
  the receipt's range).
- **Undo.** Change is the undo. The existing Edit › Undo chain keeps working
  (`SessionStore+EditUndo` already treats the latest away answer as undoable).
- **Keyboard and VoiceOver.** The popover card is in the popover's normal tab
  order: Change, Name it, Start Fresh. On return VoiceOver announces once,
  source included: "Away 17 minutes. Mac was asleep. Recorded as a break by
  Daybook. Change it in Daybook." The panel itself takes no focus, so the
  popover is the keyboard route, through the existing global shortcut that
  opens it.

### 4. The unclear case

```
Away 22 min · 3:10 – 3:32 pm · Screen stayed on, no input
How should these 22 minutes count?
[It Was a Break]   [Leave Uncounted]   [Count as Work]
```

- Three plain answers, each named by what it does to the record, replacing
  today's four. Captions where captions show: "Not counted, kept as rest" ·
  "Not counted, no break added" · "Counts on this session, including reading
  or work away from the Mac".
- **No default.** No button is highlighted and Return chooses nothing: the
  evidence is unclear, so the answer has to be the person's. Esc is Later. For
  a working pattern, Count as Work is listed first; nothing else changes.
- Each choice is applied with source `user` and is an explicit answer for
  learning (section 2).
- **Start Fresh** is not on this card: the card becomes the recorded card the
  moment it is answered, and Start Fresh is on that card's session line. *My
  call:* a thread change against a still-pending absence would need rules for
  which side of the answer it lands on, for one click saved.
- Dismissing (Later, Esc, the fade) leaves the question pending and the time
  uncounted, exactly as today. The fade of the recorded notice (section 3)
  only hides the panel; the answer is already saved.
- Tiers apply here as today (section 10).
- **Components (my call).** `AwayAnswerGrid` is replaced by two views in
  `Design/Components`: the recorded card and this question. Its call sites
  (`AwayQuickPanel`, `AwayFullPrompt`, the dashboard card, `FocusHero`,
  `DayStory`) and the checks that render it move to whichever applies.

### 5. Start Fresh moves to the session

Start Fresh was never about the past: it chose a new thread for the work after
the return. It leaves the answers and becomes a session action.

- **What already happens without it.** Returning in an unrelated app already
  starts a new thread with an empty name (app-aware continuity, the
  2026-08-22 addendum). Start Fresh is for the other case: the person came
  back in the same app but to new work.
- **Where:** the session line of the recorded card ("Deep work carries on …
  Start Fresh") and the session menu in the popover hero and the dashboard, as
  "Start Fresh From Here". *My call:* the owner ruled it out of the answers;
  the session line keeps it one click away at the moment it was used, without
  making it an answer.
- **When it shows:** the running stretch's start equals the latest resolved
  receipt's range end, and the stretch's thread is still the one `apply` gave
  it. Receipts are persisted, so the test holds after a relaunch. A Change of
  the answer does not hide it. Once used, the thread differs and the item
  hides; the next absence's receipt starts the test again.
- **What it does:** the running stretch moves to a new thread with no name,
  starting at the return, exactly as `.resetTimer` does today. The away answer
  (break, uncounted or work) is untouched.
- **Engine:** a new method on the owner, not a new answer. `UserDecision
  .resetTimer` stays in the enum so old receipts decode, and no new answer
  produces it.
- **Undo:** one `DecisionHistory` transaction of operation `.correction` whose
  before and after states differ only in the live thread id and name; Edit ›
  Undo restores both.

### 6. Copy

| Where | Today | New |
|---|---|---|
| Title line | What happened while you were away? | `Away 17 min · 10:05 – 10:23 pm · Mac was asleep` |
| Recorded, break | (none) | Recorded as a break. |
| Recorded, uncounted | (none) | Left uncounted. No break added. |
| Unclear question | What happened while you were away? | How should these 22 minutes count? |
| Reasons | (none) | Mac was asleep · Mac was locked · Screen was off · Screen stayed on, no input · "… for 14 of 17 min" when partly covered |
| Source mark | (none) | Recorded by Daybook · Recorded by Daybook from your past answers · Your answer |
| Session line, same work | Not counted. Deep work continues, 2h 14m so far. | Deep work carries on: 2h 14m so far today. |
| Session line, other work | Not counted. You're in Dia now, and Deep work stays in Continue today. | You came back in Dia, so this is a new session. Deep work is in Continue today when you want it. |

Every string is built by code from stored values. Capitalisation follows the
app's rule: title case on buttons, sentence case in lines.

### 7. Provenance and the origin mark: one vocabulary

The activity-aware spec gives each session a category source (`user`, `rule`,
`correction`, `ai`, `builtIn`) and an origin (`manual`, `rule`, `automatic`),
shown as a quiet mark. An away answer uses the same source enum, so there is
one vocabulary:

| Away answer came from | Source | Mark |
|---|---|---|
| The person (card, Change, timeline) | `user` | Your answer |
| The fixed rule on clear evidence | `builtIn` | Recorded by Daybook |
| The person's own pattern | `correction` | Recorded by Daybook from your past answers |

- **Stored** on the receipt as an optional `answeredBy` plus the reason, and on
  an inserted break record as an optional field of the same type. Both are
  optional keys; older builds ignore unknown keys. Decoding follows the enum's
  rule below.
- **Shown in phase 1** on the recorded card and on the day's timeline rows for
  away answers (the decision row and the break row), so an automatic answer is
  never mistaken for the person's.
- **The session that carried on** after an away answer gets the activity-aware
  spec's "carried on after an away answer" mark, naming the answer and its
  source: "Carried on after a break (recorded by Daybook)". That mark ships
  with activity-aware Phase B.
- The mark is the same low-contrast component the activity-aware spec
  defines, with an accessibility label, never the only carrier of meaning.
- A Change sets the source to `user`.

If this design ships before activity-aware Phase B, it introduces the source
enum and the mark component; Phase B extends them. The enum is
`enum DecisionSource: String, Codable { case user, rule, correction, ai,
builtIn }`, decoded tolerantly: a missing key reads as `user` (every answer
recorded before this change was the person's), and a present but unknown raw
value reads as `builtIn`, so a newer build's automatic source is never shown
by an older one as the person's own, and no record becomes unreadable. The
activity-aware spec is committed on its own branch
(`docs/specs/2026-11-17-activity-aware-sessions-design.md`, commit 466f2b8);
its origin-mark paragraph is a later amendment.

### 8. One corrections store

The activity-aware spec stores category corrections as
`{fingerprint, chosen, vetoed, count, lastUsed}` with a 90-day expiry. Away
answers use the same store, keyed by a kind (`category` or `awayAnswer`) so the
two never mix. An `awayAnswer` entry:

- `fingerprint`: the section 2 fingerprint.
- `recent`: the last 4 explicit answers, each with its date and the id of the
  absence it answered (one per absence, section 2). An optional field the
  category kind does not use. `chosen` is the answer at least 3 of them agree
  on, or none; `count` is how many agree.
- `vetoed`: a set. An answer joins it when the person changes away from it on
  a recorded card or a timeline row for this fingerprint. It leaves when the
  person explicitly chooses it again, once: their own choice is the best
  evidence that the veto no longer holds. While vetoed, Daybook never records
  it itself (section 2, step 3).
- `lastUsed`: the date of the latest absence with this fingerprint, answered
  or accepted. The entry, its answers and its vetoes expire together 90 days
  after `lastUsed`. *My call:* an accepted answer teaches nothing, but it
  keeps a pattern the person is living with alive; a pattern that stopped
  occurring fades and changes no record when it does.

The store is new live data: `guard-live-data.py` learns its path. It holds
band names, answer kinds and dates only; no app names, titles or personal
data.

### 9. Undo, safety and time

- **No lost time.** An automatic answer is an ordinary `decide` call: the same
  receipt, the same journal transaction, the same records as a click. Change
  is undo plus `reviseAwayDecision`, which already moves time between counted
  and uncounted without touching other stretches.
- **Changeable later** from the day's timeline: the break row's "Change How
  This Counts" and the decision row's three answers already revise receipts.
  The rows gain the source mark; nothing else changes.
- **Relaunch.** The classifier is pure and the event log is on disk, so a
  question restored at launch is read again with the same result. If it is
  clear, it is recorded then, with the same decision id the original pending
  question carried (`pendingDecisionID` and `awayReturnedAt` are both in the
  snapshot), so a replay cannot apply twice: the receipt with that id in
  `awayDecisions` marks it answered whether or not it inserted a record, and
  the existing check in `apply` refuses a decision whose record id already
  exists. Checks cover a replay of an uncounted answer (no inserted record)
  and a crash between the journal write and the snapshot write. A snapshot from
  an older build without `awayReturnedAt` falls back to `decisionStarted` as
  restore does today; if that moves the return outside `returnGrace`, the
  absence reads unclear and is asked, which is safe. The "not yet seen" state
  of the recorded card is kept with the receipt, so the menu-bar mark
  survives a relaunch.
- **Second absence while one is unresolved.** A clear absence is resolved at
  return, so it is never left pending. An unclear question still pending when
  a second absence begins behaves as today: the second absence is banked as
  `shadowAway` and excluded, and its own reading is not used. At the cap,
  `holdSecondAbsence` behaves as today.
- **Midnight.** No change: an absence that spans midnight is one receipt and,
  if a break, one record, which the day views clip, as today. The fingerprint
  uses the time the absence began.
- **Zones.** Lengths come from the engine's own away figure; the time band
  uses the calendar the day views use, so fixtures check it in more than one
  zone.

### 10. Prompt tiers and settings

| Setting | Today | Under this design |
|---|---|---|
| Ask me after (15 min) | Below it, silent exclusion | Unchanged |
| Stop session after (4 h) | At it, the session ends | Unchanged |
| Full-screen prompt after (30 min) | Chooses quick or full for every question | Applies only when Daybook asks (the unclear case, a working pattern, a veto). Its help text says so. A clear absence only ever gets the quick panel's notice |
| Pause after no input for (10 min) | Idle pause | Unchanged |
| Apps working for you (agent policy) | Count, pause quietly, or treat as away | Unchanged |

*My call:* no new setting to turn automatic recording off. Change is one click
on every automatic answer, the card stays until seen, and a switch would bring
back the question the owner ruled out. If the owner wants one, it is a single
Bool in the Away group.

## Constraints (from `CLAUDE.md`)

- **Layering.** The classifier, the default rule, the fingerprint, the
  corrections entry and every string are Core, pure and checked with
  `TestClock`. The store reads the event log and calls `decide`; Surfaces show
  the card.
- **Session state** stays behind `SessionEngine` and `SessionStore`. Start
  Fresh From Here is a method on the owner; any new internal member joins the
  `keep_internals` list.
- **Persistence.** New fields are optional keys; no new enum case in a type
  that older builds decode (`AwayTrigger`, `BreakOrigin`, `UserDecision`).
- **Checks** for every behaviour, in any zone, with `MemoryDefaults`, each fix
  with a check that fails on the old behaviour. Before commit, `fix-reviewer`
  on the decide path, the store and the time bands.
- **Lengths** in Surfaces are tokens or `N.zoomed`.
- **Public repository.** Fixtures use invented times and placeholder app
  names; the owner's event log is never committed.

## Phasing (each phase ships on its own)

1. **Clear absences answer themselves.** Classifier, fixed rule, recorded card
   with Change, Name it and the "Recorded by Daybook" mark, the card kept until
   seen with the menu-bar mark, the source mark on the day's away rows,
   unclear card with three answers, Start Fresh on the session line and in the
   session menu, copy, `answeredBy` on receipt and record, tier help text.
2. **Learned defaults.** The corrections store (shared with activity-aware
   Phase B, whichever lands first builds it), the fingerprint, the learned
   line, the working-pattern ask.
3. **The "carried on after" mark** on the continuing session, with
   activity-aware Phase B's origin mark.

## Left to the builder

- Exact card layout within the design tokens, and how the quick panel's
  existing view hosts a statement rather than a grid.
- Where the corrections store lives and its file format, atomic like the
  existing archives.
- How "seen once" is detected for the popover card.
- Whether Start Fresh From Here reuses the `.resetTimer` thread code in
  `apply` through a shared helper.

## Open spikes (do before the phase that needs them)

- **Coverage on real history, phase 1.** On a scratch copy, read the owner's
  past absences against `machine-events.jsonl` and report how many read clear
  and unclear with `clearLiveMax` and `returnGrace` as set, the unclear ones'
  shapes, and any clear one whose live time is over 5 minutes. Report counts
  only; nothing personal is written to the repository. Adjust the
  constants if the split is far from the owner's sense of it.
- **Return timing, phase 1.** Probe that an idle-triggered absence followed by
  a lock ends at the unlock (the engine ends absences on `.awayEnded`), so the
  return falls inside `returnGrace` of the last covered stretch.
- **Revise after an automatic answer, phase 1.** Probe Change to each answer
  and back, including after a relaunch and after the receipt's record is
  archived, and confirm totals match a person's click on the same absence.

## Review record

- **Builder check (18 November 2026).** Eight questions. Settled from the
  code and written in: where the classifier runs (section 1), which timestamp
  is the return and how a relaunch replays (section 9), mixed answers fall to
  the fixed rule (section 2), an uncounted answer's row and revise path
  (section 3), the components replacing `AwayAnswerGrid` (section 4), when
  Start Fresh shows and how it undoes (section 5), the source enum's shape
  (section 7), and that an uncertain stretch reads unclear (section 1). Its
  claim that the timeline rows do not exist was wrong: they are in
  `Sources/Surfaces/Story/`.
- **Panel (18 November 2026),** UX-designer and behavioural-science
  personas, three rounds. Round 1: GPT approve-with-changes 94, Gemini
  approve-with-changes 92, Nemotron Ultra approve-with-changes 85 (its
  findings cite sections the file does not have, so it did not read it);
  DeepSeek and Nemotron Super could not open the file. Round 2: GPT 94 and
  Gemini 92 approve-with-changes, Nemotron Super approve-with-changes 80,
  Nemotron Ultra approve 92, DeepSeek no answer. Round 3 on the final text:
  Gemini approve 98, DeepSeek approve 90, Nemotron Ultra approve 95, Nemotron
  Super approve-with-changes 92, GPT approve-with-changes 94 with two copy
  blockers (shutdown worded as sleep, a hard-coded "3 of the last 4"), both
  fixed in this text after that round. Every finding was adopted except:
  keyboard shortcut badges on the non-activating panel, veto spill-over into
  neighbouring time bands, an explicit confirmation step to refresh a learned
  pattern, Start Fresh on the unclear card, and a 2-minute floor on live
  time; reasons are in the session report.
