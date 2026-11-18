# Activity-aware sessions: what you did, worked out from evidence

Date: 17 November 2026. Status: draft for approval.

This design was argued over seven review rounds with five outside models. The
round-by-round record is summarised under "Review record" at the end. Facts that
were checked on a real Mac are marked **verified**; everything else that depends
on macOS behaviour is listed under "Open spikes" and must be probed before the
phase that needs it.

## Why

Daybook knows which app is in front and for how long, and nothing about what
the time was. A session's category is whatever the person picked, or whatever an
Activity Rule says about a set of apps. That leaves four gaps:

- **Manual labelling.** Someone who lets sessions run automatically still has to
  say what each one was.
- **No picture of the day by kind of work.** The timeline shows sessions, not
  how much of the day was coding, research, calls or video.
- **No honest quality of time.** The front app lies. An editor left open while a
  video plays counts as coding. A browser is "research" when touched and "media"
  when not, with nothing in between.
- **Automatic sessions pick a category from the app alone**, so the same browser
  is always the same thing.

The goal is that Daybook works out what a stretch of time was from evidence of
what the hands and the screen were doing, labels automatic sessions without
being asked, and shows the breakdown inside every session, while a category the
person chose is never overruled.

## The cases this must get right

These came from the owner and are the acceptance tests. Each becomes a headless
check.

| # | Situation | Must be recorded as |
|---|---|---|
| a | Watching a video titled "Claude Code is great", hands off, nothing else going on | Media. Not coding, whatever the title says |
| b | Working in an editor while a tutorial video plays | Coding. The video is a companion |
| c | Editor in front but untouched while a video plays on and on | Not coding. "It depends how much I use each" |
| d | Code 40 min, browse 10 min, code 30 min | One session with three phases inside |
| e | Watching a film | An entertainment session |
| f | Leaving for something else and not coming back | A new session, starting when the person left |

"Deep Work" is about meaning, not the app: it can be coding, browsing or both.

## Goals

1. Credit time to what the person was doing, from input and screen evidence,
   never from the front app or a window title alone.
2. Keep one session as the unit of meaning, show its phases inside, and split
   only when the activity really changed.
3. Give every session a depth (deep, light, passive) separate from its activity.
4. Label automatic sessions with one of the person's own categories, or with a
   label AI makes when none fits, marked as assigned by AI, and make a wrong
   label a one-click fix that is not repeated. Categories grow from what the
   person actually does, not from a list the app ships.
5. Work at three tiers: no permission and no model; model only; model plus the
   opt-in site signal. Each tier claims only what it can know.
6. Stay cheap: no polling loops beyond the existing 1 Hz session ticker, and a
   measured cost budget (see "Ship gates").

## Non-goals

- Screenshots, screen recording, or reading page content. Permanently out.
- Reading window titles. Deferred to a later phase with its own review.
- Camera detection, window geometry, browser extensions, any cloud service.
- The dashboard redesign. It is a separate project with its own design, started
  once real phase data exists to design against.
- Replacing user categories or changing how Activity Rules are authored.

## Anti-goals (a failure even if it works)

- A category the person chose, or one set by their Activity Rule, changes
  without them asking.
- AI creates or edits an Activity Rule without being explicitly asked.
- An AI-made label enters the person's category list, or fills a focus goal
  with leisure, without the person keeping it.
- The app ships a fixed list of extra categories that most people never use.
- A confident label on thin evidence. "Mixed" and "Unsorted" are correct
  answers; a guess is not.
- A manual session is split without the person accepting it.
- Anything read through Accessibility is stored, logged or sent to the model
  beyond what the consent sheet says.
- The feature claims more than the active tier can know.

## Approaches considered

| Approach | What it is | Trade-off | Outcome |
|---|---|---|---|
| A. Model classifies everything | On-device model reads apps, titles and timings per event | Needs macOS 26, costs battery, cannot be checked headlessly, wrong in ways nobody can explain | Rejected |
| B. Screenshots | Periodic capture analysed on the Mac | Most accurate in theory. Needs Screen Recording, a recurring system reminder, heavy CPU, and breaks the privacy promise outright | Rejected by the owner |
| C. Titles decide | Read the window title, classify from the words | Fails case a directly: a title says what a page is about, not what the person is doing | Rejected |
| **D. Evidence first** | Deterministic credit from input and screen-held signals; phases derived in hindsight; the model only picks a category for an already-computed summary | Thresholds need tuning; some signals need probing; cannot tell a social site from documentation without the opt-in | **Chosen** |

D was chosen because it is the only one that passes cases a to c without
reading content, runs on every supported macOS, and keeps Core checkable with a
test clock. All five reviewing models arrived at the same shape independently.

## What already exists and is reused

Found while mapping the code for the build plan, after the review rounds. The
design below builds on these rather than beside them.

| Exists today | Where | What this design does with it |
|---|---|---|
| Who holds the display awake, with no permission, telling a watched app from a keep-awake utility | `WatchDetector` (App) | It is the screen-held signal. Already in production, so it needs no ship gate |
| Quiet told apart, one sample a second, into idle, watched (a film, a call) and an AI agent at work | `QuietSampler`, `PresenceGate`, `AgentPresence` (Core), fed by `observeIdle()` | Beats record this reading. Nothing here re-decides it |
| Whether quiet time counts: under the person's "pause when idle" setting it counts; at the threshold the whole quiet stretch becomes a pause, backdated to when the quiet began | `SessionEngine` transitions | Unchanged. It is the only rule for what counts |
| A watching pause, and the watched stretch written as its own record | `SessionEngine+Pauses` (`breakOrigin: .watching`) | Unchanged. It is how video inside a session is recorded, and the model for leisure blocks |
| An AI agent at work counting as work, pausing quietly, or being ignored, by the person's choice | `AgentQuietPolicy` | Unchanged. Quiet time the engine counted for this reason is credited to the anchor |
| Categories where watching is the work | `countsWhileWatching` | Unchanged (section 2) |
| A strip of app runs inside a session | `SessionShape.runs`, `StoryShapeChart` | The phase strip is drawn the same way, by activity instead of by app |
| The category last chosen for an app | `CategoryManager.suggestedWorkType(for:)` | The deterministic fallback (section 6) |
| Append-only journal beside a snapshot | `JournalFile` | How beats are written |

## Design

### 1. Evidence: beats

Raw app stretches (`AppUsageSession`) stay exactly as they are. A new, compact
evidence layer is recorded beside them.

A **beat** is a 30-second window on a fixed grid. It holds:

- **Per-app slices**: for each app that was in front during the beat, its
  seconds and its key, click and scroll counts. The counts are deltas of the
  system-wide cumulative counters Daybook already reads without any permission
  (`InputCounters`), sampled at every app-activation boundary and at beat
  edges. A flick to another app shorter than 5 seconds folds into the
  neighbouring slice together with its input, so rapid switching does not
  shred the record.
- **Presence**, as the existing sampler read it for that window: input, quiet,
  watched, an agent at work, or paused. Beats record this reading; they do not
  decide it again.
- **Flags**, all permission-free and content-free:
  - `watchedApps`: the apps holding the display awake, from the existing
    `WatchDetector`.

Daybook reads no audio at all, neither a microphone nor an output device: the
owner ruled on 17 November 2026 that, for privacy, Phase A touches none.

Beats exist only while a session is running or automatic mode is on.

**Verified** on macOS 27.3: a Chromium-based browser playing video appears in
the process power assertions as `NoDisplaySleepAssertion "Video Wake Lock"`
with no permission, and `WatchDetector` already relies on this. It counts only
a visible app that holds the assertion itself, so a browser whose helper
process holds it would read as a keep-awake utility; whether Safari and
Firefox do that is unverified (see "Open spikes").

### 2. Time states and credit

Two words first:

- **Quiet**: no engaged input. Quiet is continuous across apps: it is measured
  from the last engaged slice in any app, so switching apps without engaging
  does not restart it, and a folded flick is part of it.
- **Counted**: whether a second belongs to the session is decided by the
  session engine exactly as today, and by nothing in this design. Quiet shorter
  than the person's "pause when idle" setting (10 minutes by default) counts.
  At the threshold the whole quiet stretch becomes a pause, backdated to when
  the quiet began: an idle pause, or a watching pause when an app holds the
  screen. An AI agent at work counts or not by the person's own setting.
  Paused time is never credited as work here.

Input counts keep the guard `InputDensity` already has: the system counters
also advance for synthetic events, so a slice's counts are discarded when the
system's own idle clock says no real input arrived in that interval.

Every counted second gets exactly one **credit state**. The first rule that
matches wins.

| # | State | When | Credited to |
|---|---|---|---|
| 1 | Engaged | The app's slice has any key event, or at least `engagedClickScrollPerBeat` (3) click or scroll events | That app's purpose. Nothing overrides input |
| 2 | Held | An app holds the display awake and quiet has lasted longer than `watchGrace` (2 min). The whole quiet stretch is then held, from its start, the way the engine backdates a pause: four minutes watched is four minutes of video | The holder: a media player is media; a call app is communication, through its own purpose; a browser is always media ("watching"), refined by site kind when that signal is on. No microphone is read, so a call in a browser reads as video. An unknown holder skips this rule |
| 3a | Quiet-kept | Quiet, and the front app has a fixed purpose in the app-purpose map (an editor, a design tool), or an AI agent is at work and the person's setting counts it | That purpose (for an agent, the anchor's). This is reading, review, thinking and supervising. It lasts as long as the engine keeps counting, so the person's "pause when idle" setting is the only cap |
| 3b | Passive | Quiet, and the front app is ambiguous (a browser) | Its last engaged purpose for `watchGrace`, or none if it has no engaged slice yet; then media, as the app-purpose map already says |

Shares, labels and thresholds use **credited seconds** (engaged, held,
quiet-kept and passive).

Time the engine did not count is shown, never credited as work: a **watching
pause** is drawn as the video or call it was, using the record the engine
already writes for it, and an idle pause is drawn as away time, as today.

One change to today's behaviour is deliberate: for crediting, scroll and
click-only input count as engagement. Today `InputDensity` treats them as
passive, which makes reading and design work look idle. Automatic mode's own
use of `InputDensity` is not changed by this.

How the cases fall out:

- **a.** Browser in front, hands off: passive, so media (rule 3b), or held, so
  media (rule 2). The title is never consulted.
- **b.** Editor receives input: engaged, coding (rule 1). The wake lock cannot
  override it. A four-minute pause to watch becomes a short "video" phase
  inside the coding session.
- **c.** Editor untouched while a video plays: once quiet passes `watchGrace`
  the time is held, so it is video, not coding (rule 2). At the "pause when
  idle" threshold the engine takes the whole quiet stretch out of the session
  as a watching pause, as it does today.
- **e.** A film holds the screen. Inside a session the engine pauses for
  watching and writes the watched stretch as its own record, as today. Outside
  a session it becomes a leisure block (section 4).

**Categories where watching is the work.** A category can already declare that
passive presence counts (`countsWhileWatching`: Meetings and Learning do). In a
session of such a category, held time is inside the working set for depth, is
never a departure, and never triggers the contradiction line in section 6.

**Thin and conflicting evidence.** Under `minCreditedSeconds` (60) of credited
time, the label is "Unsorted". For the counterfactual check, the one weak
signal is site kind (phase D): the dominant label is computed with and
without it, and if the two differ the label is "Mixed". Before phase D there
is no weak signal, so "Mixed" cannot occur.

**Unattended video.** A held screen cannot tell a film being watched from a
film playing to an empty room. The engine already has a rule for this, and it
stands: watching that follows input is a watching pause, ended quietly with
nothing asked; watching that begins after the session has already paused as
idle is nobody's and stays an absence. No new prompt answer is added.

### 3. Two axes: activity and depth

**Activity** is what the time was: the dominant purpose by credited seconds.

**Depth** is how it was spent, and needs one concept first.

A run's **working set** is the set of apps the person is working across. It
starts with the run's **anchor**, the first app with an engaged slice, so one
app alone is a working set. An app outside the set joins when it receives
engaged input and the person afterwards gives engaged input to an existing
member within `returnWindow` of leaving that member. An editor, a terminal and
a browser being alternated between is one working set.

Each counted second falls on one side:

- **Inside**: engaged or quiet-kept on a member.
- **Outside**: every other counted second (held, passive, and engaged or
  quiet-kept on a non-member). Watching a video in a browser that is
  a member is outside.

| Depth | Rule |
|---|---|
| Deep | A run of at least `deepMinRun` (25 min) with at least `deepInsideShare` (70%) inside and under `deepOutsideShare` (15%) outside |
| Light | Credited, but does not meet the deep rule |
| Passive | Held or passive time is dominant |

"Deep Work" is depth over whatever is in the working set, so it can be coding,
browsing or both, and an idle editor can never be deep.

**Stated limitation.** With no permission, engaged browsing of a social site is
indistinguishable from reading documentation and counts inside. With the opt-in
site signal, social, video and shopping kinds are forced outside. The interface
never claims more than the tier can know (see section 9).

The working set is close kin to the existing thread "side apps"
(`ThreadApps`), which is also derived at display time. The builder should reuse
that machinery where it fits rather than build a parallel one.

### 4. Session shape: one envelope, phases inside, split in hindsight

The session record stays the envelope and holds the person's meaning: name,
category, start, end. **Phases** are a derived view inside it, each a stretch
of one dominant activity of at least `minPhase` (3 min), smoothed so brief
flickers do not create phases.

A **departure** is the moment engaged input goes to an app outside the working
set, or a held or passive stretch begins, or the engine's watching pause
begins. Quiet and idle pauses are never departures: a long pause is handled
only by the existing idle, away and break logic.

`returnWindow` (15 min) is measured from a departure.

- Returning with engaged input to a member inside the window makes the detour
  a **phase**. Case d is one session with three phases.
- If the window expires without that, the working run ended at the departure,
  and a split boundary is backdated to it (case f).

Who may split:

| Session started by | Split behaviour |
|---|---|
| The person (manual) | Never split automatically. At the end, a "Split here?" offer; accepting is undoable |
| An Activity Rule | Same as manual: the person authored the rule |
| Automatic mode (`isAuto`) | Splits by itself. Provisional while the window is open; final once it has closed with no return or the session has ended. Every automatic split keeps a one-click "Merge back" |

**Telling the three apart.** A rule-started session is recorded with `isAuto`
true today, exactly like one from the older automatic mode, and the record does
not say which. The record gains an optional `origin` (`manual`, `rule`,
`automatic`); a record without it reads as `automatic` when `isAuto` is true
and `manual` otherwise.

**Origin is shown, quietly (owner ruling, 17 November 2026).** Every session row and session report carries a small, low-contrast mark saying how it began: started by you, started by a rule (naming the rule), or started automatically. A session that carried on after an away answer says so. A name the app chose itself (such as "Browsing" for a browser) is marked as chosen by the app until the person edits it. The mark has an accessibility label and is never the only carrier of the meaning. Visual treatment goes through the usual design review.

**How an automatic split is written.** Nothing is written while a split is
provisional: the records are untouched and the live interface shows only a
provisional phase. When the split becomes final, one engine operation writes
it: the head keeps the original name, category and thread and now ends at the
departure; the tail is a new automatic record starting at the departure, with
its own thread and a category from section 6. If the session is still running,
the running session becomes the tail. "Merge back" is the reverse operation: it
is offered on the tail while both records are adjacent and unedited, and is
also the undo of the split. Goals, breaks and totals follow because they are
read models over the records. This is a session-state change and goes through
the `fix-reviewer` agent.

**Leisure blocks.** With automatic mode on and no session running, held or
passive media lasting at least `leisureMinRun` (10 min) is recorded as its own
block on the timeline. A leisure block never counts toward focus totals, goals
or streaks, and is not a break: it does not appear in break statistics. It is
labelled like any automatic session (section 6). The record the engine already
writes for a watched stretch inside a session is the model to follow.

What the person sees inside a session row on the timeline (sketch; final
visual design is settled in phase A with a design review):

```
Refactor the importer                          Coding   1 h 20 m   Deep
[#### coding 40m ####][= browsing 10m =][### coding 30m ###]
```

### 5. What is stored and what is derived

| Stored | Notes |
|---|---|
| Beats | Schema-versioned. Kept for `beatRetention`, a setting, 90 days by default |
| User overrides | Edited boundaries, accepted or declined splits, category choices. Never rewritten by derivation |
| Session snapshot | Written when a session ends: credited seconds per purpose per phase, depth, the correction fingerprint, the algorithm version, and which signals were on, so a later reader knows what the snapshot could and could not see |

Phases, depth and shares are a **pure function** of beats, overrides and the
algorithm version, memoised per session. While beats exist, a newer algorithm
re-derives the session. After beats expire, the snapshot is the record.

Sessions recorded before this feature keep their category untouched. A second,
simpler derivation gives them phases from app stretches alone, marked lower
fidelity, with no depth claim.

### 6. Categories, provenance and corrections

Precedence, highest first:

1. The person's manual choice
2. An Activity Rule
3. A remembered correction
4. An AI pick among the person's categories, or an AI-made label (section 7)
5. The deterministic fallback
6. "Mixed" or "Unsorted"

Each session stores where its category came from: `user`, `rule`, `correction`,
`ai` or `builtIn`. A session's stored category never changes on its own.

**The deterministic fallback.** There is no table from activity to category,
because categories are the person's own and can be renamed, retired or custom.
The fallback reuses what exists: for the app with the most credited seconds,
`CategoryManager.suggestedWorkType(for:)`, which prefers what the person chose
recently for that app. It applies only when the dominant activity is a focused
purpose (`AppPurpose.isFocused`), which keeps today's behaviour for work. When
the dominant activity is not a focused purpose (media, communication, research
alone, utility), the fallback gives no category: the session shows its activity
name, is "Unsorted", and does not count as focus.

**The AI mark.** An AI-sourced category looks like any category and carries a
small sparkle beside it, with the accessibility label "assigned by AI". One
click confirms it (the source becomes `user` and the mark goes) or opens the
category picker.

**Corrections.** When the person changes a category, Daybook stores
`{fingerprint, chosen, vetoed, count, lastUsed}`. The fingerprint is: purpose
shares bucketed in 20% steps in a fixed purpose order, plus the two apps with
the most credited seconds (ties broken by bundle identifier, padded when there
are fewer), plus the site kind or "none". A matching fingerprint later suggests
the chosen category and never the vetoed one. A correction unused for 90 days
expires, which only stops it steering future suggestions.

**Contradiction.** When a category chosen by the person or a rule maps to a
purpose holding under 30% of credited seconds while another purpose holds over
60%, the label is kept and the session report adds one factual line, for
example "Mostly video: 34 of 48 minutes". Nothing is changed and nothing is
asked.

**Rules.** Activity Rules are created and edited only by the person: in
Settings, through Ask when they ask for one, or from "Make this a rule…" on a
session they have corrected. Daybook never proposes a rule on its own.

### 7. The on-device model

The model does one job: say what an ended session was, in the person's terms.
It either picks one of their categories or, when none fits, proposes a short
new label. No list of extra categories ships with the app: someone who only
codes never sees "Entertainment", and someone who watches films gets it the
first time it is true.

- **When.** At most one call per ended session, and only when the top
  category's share of credited seconds is under `modelShare` (60%), its lead
  over the next is under `modelMargin` (15 points), or the deterministic
  fallback gave no category.
- **Input.** The session snapshot (activities, minutes, depth, app names, site
  kind if on) and the names of the person's categories that can be started.
  Unkept AI-made labels are never in that list.
- **Output.** Constrained to one of those category identifiers, or a proposed
  label, or none. A pick is validated against the list. The model writes no
  figures and no prose: every number shown comes from code, as the written
  notes already require.
- **Skipped** in Low Power Mode, under thermal pressure, for sessions under 10
  minutes, when Apple Intelligence is switched off in Settings › Privacy, and
  below macOS 26 (`ModelGate`). The deterministic fallback then stands.
- **Cached** by fingerprint, so the same pattern is not asked twice.

**AI-made labels.** A proposed label is not a category yet.

- It lives on the session, shown like a category with the AI mark. It is not in
  the person's category list, not in any picker, and not offered to the model.
- The person can **Keep** it (it becomes one of their categories and the mark
  goes; colour and symbol come from the dominant activity and can be changed),
  **Rename** it, **Merge** it into one of their categories, or **Remove** it
  (its sessions become "Unsorted" and the name is never proposed again).
- **Reuse is done by code, not the model.** Each unkept label remembers the
  fingerprint it was made for; a later session with a matching fingerprint gets
  the same label with no model call. This keeps labels stable and stops the
  model reinforcing its own inventions.
- **Limits.** At most `newLabelsPerDay` (1) new labels a day and
  `maxUnkeptLabels` (3) unkept at once; when the limit is reached, the session
  is "Unsorted" with its activity name. An unkept label unused for
  `labelArchiveAfter` (30 days) is archived: it stops being reused, and
  sessions already carrying it keep showing it. History is never rewritten.
- **Names.** One to three words, at most 24 characters, letters in any script
  and spaces only. A proposal that matches an existing category or label
  ignoring case and plural is treated as a pick of that one. Because the model
  never sees addresses, titles or content, a label cannot carry them.
- **Focus.** Code decides, never the model. Time under an unkept label counts
  toward focus exactly when the fallback above would have counted it: the
  dominant activity is a focused purpose. Leisure and other non-focused
  activity never count. Once kept, the category has an ordinary "counts toward
  focus goals" setting the person can change.
- **No model** (older macOS, or Apple Intelligence off): nothing is invented.
  The deterministic fallback stands.

**Shadow mode.** At first the model's pick among existing categories is
computed silently and is shown on automatic sessions only as a one-click
suggestion. Daybook counts how often the
pick matched what the person chose, counting only sessions where the person
made a choice. Settings shows the result in plain words ("matched 17 of your
last 20 choices"), and the person switches "Let AI assign categories to
automatic sessions" on. It is never switched on for them.

### 8. Opt-in site signal (Accessibility)

Off by default. This is the one place Daybook asks for special access.

**Turning it on.** The switch shows Daybook's consent sheet, then the standard
macOS Accessibility grant. Without the grant nothing is read and the switch
shows as inactive.

**Which apps are ever queried.** The consent sheet lists the apps the system
reports as able to open web links, with known browsers ticked and anything else
unticked; the person confirms the list and can change it later. No other app is
ever queried, so terminals, password managers, messaging and one-time-code
windows are untouched by construction.

**What is read.** The address of the front browser tab. It is reduced in memory
to its site name, then to a **site kind** from a built-in table (video,
documentation, code host, social, shopping, mail, AI chat, meeting, and the
sensitive kinds below), and the address is discarded at once. It is never
stored, logged or sent to the model. A read that fails, times out or finds an
unknown site gives no signal.

**Consent text:** "Daybook reads the address of the front browser tab, keeps
only what kind of site it is, and discards the address immediately. It never
reads page titles or page content."

**Remember sites.** A second switch with its own disclosure, off by default.
When on, Daybook keeps a list of site name to kind for sites the person has
corrected, viewable and deletable in Settings. Sensitive kinds (banking,
health, government, sign-in and adult sites) are never added.

**Mechanics.** Reads are event-driven (app activation, tab change), run on a
serial worker off the main thread with a messaging timeout, and a per-app
circuit breaker skips an app for the rest of the session after two timeouts.

**README.** The Privacy section's "No special access" paragraph is rewritten in
the same change that ships this phase: Daybook asks for no special access
unless the person turns on the site signal, which requests Accessibility to
read the front browser tab's address as described above. "Never what is in it"
becomes true with that one stated exception.

### 9. Ship gates and honest tiers

The screen-held signal is already in production and needs no gate. The one
new signal, site kind, sits behind a flag compiled into Core as a table of
signal to passing macOS major versions; a line is added to it only in the same
commit as the passing probe report under `docs/debug/`. No line means off, and
off means no claim: the design works without it.

Settings shows which signals are active, so the person can see what the
current tier knows:

| Tier | Knows | Cannot know |
|---|---|---|
| No permission, no model | Hands-on work, quiet, and video or calls where an app holds the screen | Which site; whether a browser holds a call or a video (it reads as video); a category for unclear sessions |
| Plus model (macOS 26) | A category pick for unclear sessions, or a new label when none fits | Which site |
| Plus site signal | Site kind: video against documentation against social | Page titles and content, by design |

### 10. Constants

Every number in this document is a named constant in Core, with these initial
values: beat 30 s, flick fold 5 s, `engagedClickScrollPerBeat` 3, `watchGrace`
2 min, `minCreditedSeconds` 60, `minPhase` 3 min,
`returnWindow` 15 min, `deepMinRun` 25 min, `deepInsideShare` 70%,
`deepOutsideShare` 15%, `modelShare` 60%, `modelMargin` 15 points,
contradiction 30% and 60%, correction expiry 90 days, `beatRetention` 90 days,
`leisureMinRun` 10 min, `newLabelsPerDay` 1, `maxUnkeptLabels` 3,
`labelArchiveAfter` 30 days.

They are starting points, not findings. Before sections 3 to 5 are built, sweep
checks run synthetic traces and assert the expected label for each:

cases a to f; reading-heavy; click-heavy design; code review; a pause to
watch a tutorial; a browser meeting (read as video); a call app; lunch; a long
pause with no departure; a single-app run; passive browser after coding; a
video opened then walked away from; quiet time on a non-member app; an
untouched editor with no media signal.

Note for the builder: `AppUsageTracker.idleCutoff` (180 s) already ends an app
stretch after three minutes without input, well before the session's own
"pause when idle" threshold. Beats must not depend on the stretch having
stayed open: quiet-kept time runs on while the engine keeps counting.

## Constraints (from `CLAUDE.md`)

- Core stays UI-free and compiles on its own. Beats, credit states, phases,
  depth, fingerprints and the model trigger are Core; reading power assertions
  and Accessibility are App, handed to Core as plain values.
- Views never recalculate time. Phases and depth reach the interface through
  read models published by the App layer.
- No new timers in the interface. Beat edges ride the existing 1 Hz ticker in
  `SessionStore`; flags are sampled at beat edges and app-activation events.
- Checks use `TestClock`, `SelfTest.scratchDirectory()` and in-memory
  preferences, and hold in any time zone.
- Changes to persistence, settings, session state or time arithmetic go
  through the `fix-reviewer` agent before commit.
- New stored files live beside the existing ones in Application Support and
  are covered by the live-data guard.
- Lengths in new interface code are design tokens or `.zoomed`.
- The repository is public: no personal data in fixtures or probe reports.

## Phasing (each phase ships on its own)

| Phase | Contents | Needs |
|---|---|---|
| **A** | Beats, credit states, phases, depth, the phase strip inside session rows, sweep checks | Cost gate |
| **B** | Category provenance and session origin, corrections store, contradiction line, "Split here?" and "Merge back", leisure blocks | Phase A |
| **C** | Model category pick, AI-made labels (keep, rename, merge, remove), AI mark, shadow mode and its Settings line | Phase B; macOS 26 |
| **D** | Site signal: consent sheet, app list, site-kind table, remember sites, README privacy rewrite | Accessibility probe; a security review |

The dashboard redesign follows as its own project.

## Left to the builder

- File and type names, the on-disk format for beats (compact, append-friendly),
  and where the snapshot lives relative to the session record.
- The smoothing method for phases, provided the sweep checks pass.
- How the algorithm version is numbered: any change to a rule or constant
  bumps it.
- Whether and how a helper process is resolved to its app in `WatchDetector`;
  the screen-held probe decides.
- Whether `InputDensity` is extended or replaced by the per-slice counts, so
  long as automatic mode's existing behaviour is covered by its checks.
- Visual treatment of the phase strip, AI mark, offers and Settings rows, each
  through the usual design review before it ships.
- How a leisure block is stored, provided it can never fill a goal, hold a
  streak or be counted as a break, and old builds reading the file do not
  mistake it for focus.
- Where unkept labels are stored, and how "counts toward focus goals" is added
  to a category's definition: today it is fixed in code as "everything except
  Break", so a kept leisure category needs it to be a stored property that
  defaults to true for every existing category.
- The exact engine operations for split and merge, written and checked the way
  the existing away corrections are.

## Open spikes (do before the phase that needs them)

1. **Screen-held probe (phase A, an improvement, not a gate).** Per browser
   (Safari, Chrome, Firefox, Arc) and for one call app and one media player,
   record which process holds the display-sleep assertion while video plays,
   is paused, is music-only, and sits in a background tab. Where a helper
   process holds it, `WatchDetector` today reads a keep-awake utility instead
   of a watched app; if the probe shows that, resolving a helper to its app is
   added in phase A with its own check.
2. **Cost probe (phase A).** Beats with all flags on must add under 1% CPU and
   under 2 MB resident memory against today's idle figures.
3. **Removed by the owner's ruling of 17 November 2026.** Daybook reads no
   audio in phase A, so there is no microphone probe.
4. **Accessibility probe (phase D).** Address extraction success and latency
   per browser, including under a heavy web app; confirm the timeout and
   circuit breaker hold.
5. **Browser list probe (phase D).** What the system returns for apps able to
   open web links on a typical Mac, and which non-browsers appear.

## Review record

Seven rounds, five outside models plus the author voting blind before each
round. The shape (evidence first, envelope with derived phases, hindsight
split, model as category picker) was stable from round 2; later rounds
tightened definitions. Main changes by round:

1. Quiet reading and thinking no longer penalised; allow-list instead of an
   exclusion list; one storage model.
2. Watching became an ordinary detour; a wake lock credits its holder, which
   also detects calls.
3. Credited seconds; input stored per app slice; the quiet cap.
4. Truthful consent wording; fingerprint kept in the snapshot; pre-feature
   sessions.
5. A split needs a real departure; each second counted once for depth.
6. A film counts: a held wake lock suspends idle.
7. Stopped without full agreement. Two reviewers held that suspending idle
   credits a video left playing to nobody. That is a real trade-off, resolved
   after the rounds by the engine's existing rule (see the amendment below).
   One reviewer held that apps able to open web links include non-browsers,
   resolved by the confirmed app list (section 8).

After the draft, a builder read it cold and asked seven questions. Five were
settled from the code and are written in above: the engine's idle handling
stays as it is; a split is written only once final, by one engine operation;
the fallback reuses the existing per-app category suggestion; the record gains
an origin; quiet is continuous across apps, synthetic input is discarded, and
the snapshot records which signals were on.

Two went to the owner. Leisure outside a session is recorded as its own
non-focus block. And no fixed list of extra categories ships: AI makes a label
when none of the person's categories fits. That last point was put to the same
five models, who all approved with one change, adopted here: a label AI makes
stays on the session and joins the person's categories only when they keep it.
Rejected from that round: withholding focus credit from work under an unkept
label (it would remove credit that counts today), and waiting for two hours of
evidence before proposing a label.

**Amendment, same day, from mapping the code for the build plan.** The app
already reads who holds the screen, already tells idle from watched from an
agent at work, already pauses a session for watching and records the watched
stretch, and already lets the person choose when quiet becomes a pause. Neither
the review rounds nor the builder check had found this. Three things changed to
build on it:

- The separate five-minute quiet cap is gone. What counts is the engine's
  decision, capped by the person's own "pause when idle" setting, and an agent
  at work counts as the person has set it. The cap would have contradicted
  both.
- The "I was watching" prompt answer is gone. The engine's existing rule for
  unattended video already answers the round-7 disagreement, with nothing
  asked.
- The screen-held signal needs no ship gate, being in production; the probe
  remains as an improvement for browsers whose helper process holds the
  screen.

Everything else stands: per-app input slices, credit states, phases, depth,
the working set, hindsight splits, labels and the opt-in site signal are new.

**Two rulings from writing the Phase A plan.** Held time is backdated to the
start of its quiet stretch once the grace has passed, so a four-minute watch
is four minutes of video and shows as a phase; before, only the part after
the grace counted and case b's own example could not come true. And a running
microphone alone no longer suggests a call: the owner dictates with a
dictation app, which holds the microphone all day. A browser-held screen is a
call only when that same browser is the app using the microphone for most of
the stretch, read per app; the microphone left the list of weak signals, so a
web call is no longer "Mixed".

**Ruling of 17 November 2026, late evening, from the owner.** For privacy,
Daybook must not touch audio at all in Phase A. This supersedes the microphone
parts of the paragraph above, which stay as the record of what was decided at
the time. The `micApps` and `audioOut` signals are removed, with the microphone
probe (spike 3), the per-app call rule and `callMicShare`. A browser that holds
the screen is always media, so a web call reads as video; a call app is still
communication through its own purpose. The weak signals are now site kind
alone (phase D), so "Mixed" cannot occur before then. Nothing had shipped, so
the algorithm version stays 1.
