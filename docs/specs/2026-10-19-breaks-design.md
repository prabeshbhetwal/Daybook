# Breaks: taking, timing, recording and reviewing them

Date: 19 October 2026. Status: draft for approval.

Research behind this design (local, gitignored, about 200 sources):
`research/2026-10-19-breaks/01-science.md` (psychology, ergonomics, occupational
health), `02-apps-and-users.md` (competing apps and what their users say) and
`03-nudges-and-macos.md` (interruption design and macOS APIs). The key sources are
cited inline below, so this document stands without them.

## Why

Daybook is for the general public. It already knows when someone has been at the
Mac for a long time, but breaks are only half a feature. A break exists only after
the fact, when someone answers "It was a break" or a long Away is saved as one.
Nobody can start one. Nothing times it, nothing says when it is over, and the
reminder is a twelve-second HUD with no buttons. Rhythms are fixed. Nothing shows
how someone actually rests across a day, week or month.

The goal is that people take breaks more often, including short ones, because
Daybook makes it easy and well timed, not because it nags. Every break is
recorded honestly and can be reviewed. The person sets the rhythm, and it can
differ by weekday, for one week or for one month.

## What the evidence allows us to say

- **Breaks reliably lift energy and reduce fatigue.** The effect is small to
  moderate (Albulescu et al. 2022, *PLOS ONE*, meta-analysis, N = 2,335: vigour
  d = 0.36, fatigue d = 0.35). The same meta-analysis found no significant effect
  on performance. Longer breaks help more after demanding work.
- **No rhythm has been shown to be best.** Pomodoro, Flowtime and self-paced
  breaks came out level on output in Biwer 2023, Smits 2025 and Göksu 2026. The
  best-supported shape comes from regulators: about 5 to 10 minutes off per 50 to
  60 minutes of screen work (HSE, OSHA, CCOHS; Galinsky 2000 field study).
- **The 90-minute "ultradian" waking cycle is weakly supported.** Vendor ratios
  such as 52/17 are marketing; the vendor later published 80/17 and 112/26. The
  20-20-20 eye rule is folk advice and rests on one uncontrolled study of 29
  people. AAO says screens do not permanently damage eyes.
- **Movement needs minutes, not seconds.** In lab trials, 2 minutes every 20
  (Dunstan 2012) or 5 minutes every 30 (Duran 2023) changed glucose and blood
  pressure. A 30-second prompt is not a sitting break.
- **Autonomy matters.** A break the person chose restores more (Trougakos 2014;
  Hunter & Wu 2016). Psychological detachment from work predicts recovery
  (Wendsche & Lohmann-Haislah 2017, N = 38,124). Scrolling a feed restores less
  than a walk or nature (Grobelny 2024). Ego depletion and the idea of
  "refilling willpower" did not replicate.
- **Timing of a prompt matters more than its wording.** Interrupting mid-task
  costs 3 to 27% more time, twice the errors and up to 106% more annoyance than
  waiting for a breakpoint (Bailey & Konstan; Iqbal & Bailey; Adamczyk & Bailey).
- **Users' complaints across Stretchly, Workrave, Time Out, LookAway, BreakTimer
  and the Pomodoro apps are consistent.** Prompts during calls, screen sharing,
  full screen and typing. Real breaks the app failed to count. Unlimited skip
  that becomes a reflex, and strict modes with no exit. Startling sounds. Streaks
  and guilt. Rigid Pomodoro. Nobody offers week or month rhythms, or break stats
  tied to what the person was actually working on. Daybook has the data to do
  both.

Copy rules that follow from this:

- **Daybook may say:**
  - "short breaks lift energy and reduce fatigue"
  - "about 5 to 10 minutes an hour is what HSE and OSHA recommend"
  - "moving for a few minutes every half hour helped blood sugar and blood
    pressure in lab trials"
- **Daybook never says:**
  - "boosts productivity"
  - "optimal ratio"
  - "90-minute brain cycle"
  - "prevents eye damage"
  - "willpower"

## Goals

1. Starting a break takes one action from anywhere, and the break is timed.
2. A break-over moment that is gentle and offers to resume the work.
3. Reminders that arrive at a good moment, can be acted on (Start, Later, Skip)
   and hold off during calls and full-screen presentations.
4. A rhythm the person chooses: presets, or their own numbers, assigned per
   weekday and overridable for today, this week, this month or a date range.
5. Every break and every reminder outcome is recorded with where it came from.
6. Day, week and month views of breaks, in neutral language, compared with the
   person's own rhythm and their own previous period.

## Non-goals

- Locking the screen, blocking apps, or any "strict mode" that cannot be dismissed.
  This is a founding rule (`docs/specs/2026-08-13-glance-and-breaks-design.md`,
  "never blocking").
- Calendar access, Screen Recording, Accessibility permission, and
  `timeSensitive` notifications. Focus-mode integration is deferred to a spike
  (see Open spikes).
- Mood or energy ratings after breaks. That comes later, once the base exists.
- Posture or sitting detection. Daybook sees screen activity, not bodies.
- A phone companion.

## Anti-goals (a failure even if it works)

- Streaks, points, scores, red or green compliance colours, "you skipped 6 breaks"
  copy, or any wording that blames the person.
- A prompt over a video call or a shared screen.
- A reminder system that silently stops firing, or that fires on the dot
  regardless of what the person is doing.
- A recorded break length that is the planned length instead of the actual one.
- Starting the next work stretch for the person.

## Design

### 1. Rhythm

A rhythm is a work length, a break length, and an optional long break every N
cycles.

| Preset | Work | Break | Long break | Evidence note shown in Settings |
|---|---|---|---|---|
| Steady (default) | 50 min | 5 min | none | "Close to HSE and OSHA guidance: 5 to 10 minutes an hour." |
| Pomodoro | 25 min | 5 min | 15 min after 4 | "A popular fixed cadence. Studies find it about as good as choosing your own breaks." |
| Deep work | 90 min | 15 min | none | "Longer blocks for focused work, with a proper reset." |
| Flow | self-paced | about 1/5 of the stretch, 5 to 20 min | none | "You decide when to stop; Daybook suggests a break length." |
| Custom | 10 to 180 min | 1 to 30 min | optional, every 2 to 8 | none |

Flow has no due time. When a stretch ends (the person stops, goes idle, or starts
a break), the break length offered is a fifth of the stretch, clamped to 5 to 20
minutes. Its only prompt is the long-stretch guard below.

There are two add-ons, each independent of the preset:

- **Eyes.** Every 20 minutes, a small HUD that disappears on its own:
  "Look at something far away for 20 seconds". It has no buttons and no
  notification. It never fires within 5 minutes of a main break being due. It is
  framed as comfort, not health. Default: on. This is what the micro tier becomes.
- **Long-stretch guard.** One clearer prompt after an unbroken stretch
  (default 90 minutes, settable from 60 to 180), whatever the preset, Flow
  included. It offers "Start break" and "Remind me in 15 min". Default: on. This
  is what the ultradian tier becomes.

**What resets what.**

- **Main clock.** Resets on any credited rest (section 2), and also on Skip.
- **Long-stretch guard.** Measures real rest only. It resets on a credited rest,
  never on Skip or Later. Under a fixed preset, someone who takes the suggested
  breaks never sees it, which is the intent.
- **Eyes.** Resets on any gap of at least the idle cutoff, or on any credited rest.
- **Pomodoro cycles.** A cycle is a credited rest after at least one work length.
  The cycle count returns to zero after any rest of at least the long-break
  length, early or not.

**Schedule (day, week, month).** A weekday plan gives each weekday a rhythm or
"No reminders". By default every day is Steady. Reminders only ever come from
computer use, so a weekend away from the Mac is quiet anyway.
Overrides sit on top, and the most specific one wins. Each override gives a
rhythm or "No reminders" for one of:

- Today
- This week
- This month
- A date range

Optionally, reminders run only inside a working-hours window (for example 08:00
to 18:00), so a late-night session follows the person's chronotype rather than
nagging.

Month-level behaviour beyond an override is insight only (section 7). It never
enforces anything.

The per-category "Remind me to take breaks during this category" switch stays as
it is. Meetings are off by default.

**Migration from tiers** (`fc.breakTiersDisabled`), applied once:

Each tier maps on its own, so every combination is covered and nothing that
was off turns back on:

| Old tier | On | Off |
|---|---|---|
| Micro | Eyes on | Eyes off |
| Cognitive | Steady every day | "No reminders" every day (main rhythm only) |
| Ultradian | Guard on at 90 min | Guard off |

`remindersEnabled` stays as the master switch.

### 2. One rule for "a break counted"

The same rule must do three things. It must:

- reset the reminder clock
- close an open reminder as taken
- feed the analysis

A credited rest is either a recorded break (section 3), or an off-screen gap of
at least the current rhythm's break length. An off-screen gap means idle, locked,
asleep, or a declared Away, taken from the usage stretches as `BreakReminder`
already does. A gap shorter than the idle cutoff (3 min, `AppUsageTracker.idleCutoff`)
can never credit a rest, because the archive cannot tell it from noise. That rule
exists today and stays. Eyes resets on any gap of at least the idle cutoff.

The work clock is computer use from the usage stretches, session or not. That is
also unchanged. A Flow suggestion of N minutes is credited by a gap of N minutes.

### 3. Taking a break

**Start break** is available from:

- the popover (a button beside the break line)
- the main window's Today
- a Session-menu shortcut, ⌥⌘B. It works only while Daybook's window is in
  front, like ⌥⌘A for Away. *My call:* a second system-wide hotkey needs a
  recorder and conflict handling, and the popover is one click away.
- the reminder HUD

It starts at the rhythm's break length. A small menu offers 5, 10, 15 or 30
minutes. It works whether or not a session is running.

**While on a break:**

- **Running session.** The session pauses with a new pause reason, `.onBreak`.
- **Menu bar label.** Shows a cup glyph and the time left. It updates once a
  minute while more than a minute is left, then every second (WCAG 2.2.2, and
  energy). A setting hides the countdown.
- **Popover.** Shows a break card with:
  - time left
  - one suggestion line (section 8)
  - **End break**
  - **+5 min**

**When the planned time is up:**

- **At the Mac:** one soft sound, which is optional, defaults to the system's
  quietest sound and can be set to silent. Plus a HUD:
  - "Break's over. Back to *<thread name>*?"
  - **Resume**
  - **+5 min**
- **Not at the Mac:** nothing until they return. Then the same HUD.
- **Either way:** the menu bar counts overtime as "+3m". Daybook never resumes
  work or starts a new stretch on its own.

**During the planned time,** only an explicit action ends a break:

- End break or Resume
- Start, Continue, or Stop on a session

Opening a work app does not end it. Unlike other pauses, `.onBreak` is not
resumed by a work app coming to the front, because glancing at Slack is still a
break. Automatic sessions and activity rules neither start nor resume anything
until the break ends.

**After the planned end:**

- **The break closes when work is sustained.** Input on at least 60 of 90 seconds
  closes the break, backdated to when that activity began.
- **If a session was running,** it resumes as a new stretch on the same thread,
  because the foreground evidence shows work. That is Daybook's premise and is
  not starting work for anyone.
- **If no session was running,** nothing starts.
- *My call:* without this, a forgotten break would read as hours.

**Nobody comes back.**

- **Recorded end.** The recorded end is the return or the planned end plus
  `longAwayCap` ("End session after"), whichever comes first.
- **When the cap is reached,** a running session ends exactly as a long absence
  ends it today.
- **The same cap** applies to a break recorded after a prompt (section 4).
- **A break across midnight** follows the existing midnight rules for running
  breaks (see the `runningBreakEndedAtMidnight` check).

**Recording.** A break is recorded as a `.breakTime` `SessionRecord` with the
**actual** start and end. It is named "Break", or with the label the person
typed. It is recorded if it lasts at least `minimumRecordedSession` (30 s), even
below `breakThreshold`. *My call:* the person said it was a break, so a
four-minute break is a break. A running session's stretch closes at the break's
start and resumes as a new stretch on the same thread, exactly as
`endDeclaredAway` does for long absences. Rename, change and undo work as they
do for breaks today.

### 4. Reminders

**When.** A main break becomes due once work since the last credited rest reaches
the rhythm's work length. Due opens a grace window: 2 minutes for Eyes, 5 minutes
for main breaks and the guard. The prompt shows at the first breakpoint inside
the window:

- a foreground app switch
- an input lull of at least 5 seconds
- the end of a hold (see below)

At the window's end it shows anyway, unless a hold is active. Do not build a
classifier. Breakpoint detection is only about 55% accurate even in research,
and transparent signals plus a deadline do as well.

**Holds.** These need no new permission, are checked in this order, and each
defers a prompt rather than cancelling it:

1. Idle, locked, display or machine asleep: no prompt. The absence is probably
   the rest, and section 2 credits it.
2. Camera or microphone in use by another app
   (`AVCaptureDevice.isInUseByAnotherApplication`; CoreAudio
   `kAudioDevicePropertyDeviceIsRunningSomewhere` on the default input). When it
   ends, if a break is still due, the prompt says "After that call, a 5-minute
   break?".
3. The frontmost app is full screen or has hidden the menu bar
   (`NSApplication.currentSystemPresentationOptions`), or another process holds a
   display-sleep assertion (IOKit) while a media or presentation app is in front:
   no HUD and no dim. The menu bar cue only.

A hold lasts at most 15 minutes per due break. After that, only the passive menu
bar cue remains, and the prompt is logged as "held". The menu bar or popover says
why it is quiet ("Holding: call in progress"), so silence is never a mystery.
Treat a meeting signal as "others can see the screen". There is no API that
detects sharing, and `sharingType = .none` is legacy.

**How it shows (the escalation ladder).** Each rung adds visibility, never
pressure:

0. **Menu bar cue.** The glyph's due state and the popover line "Break due". This
   is always shown while a break is due.
1. **HUD** (today's 12 s panel, now with buttons):
   - **Start break**
   - **Later** (10 min)
   - **Skip**
   
   It names why it is showing now ("52 minutes in Xcode"), shows on the display
   with the pointer, and posts a VoiceOver announcement.

   **Break reminders no longer post notifications.** Today a notification goes
   out only when the person is locked, asleep or away. Under hold 1 that absence
   is the rest, so the notification arrives stale in Notification Centre.
   *My call:* retire it, and with it the notification-permission row in
   Settings. No `UNUserNotificationCenterDelegate` is needed.
2. **Gentle dim**, opt-in in Settings ("Dim the screen if I don't respond"). It
   applies only when the HUD went unanswered and the break is still due 2 minutes
   later, at the screen and with no hold. The screen dims to about 30% over 60
   seconds using a click-through window on each display. Any input after the dim
   finishes, or any HUD button, clears it. With Reduce Motion it is one instant
   step. It never blocks input and never appears during a hold.

**Later and Skip:**

- **Later** snoozes for 10 minutes. The popover's Later menu also offers 5 or 30
  minutes.
- **Snooze cap.** At most two Laters per due break. The third prompt offers only
  Start break and Skip.
- **Skip** means "not this one". The clock restarts as if a rest had been
  credited, but nothing is recorded as rest. The copy is neutral: "OK. Next one
  around 15:40."
- **Repeated skips.** After three Skips of main breaks in one day, the next
  prompt offers once: "Breaks less often today?" That switches today's override
  to the next longer preset. Daybook adapts rather than escalates.

**Pause reminders** for 1 hour, until tomorrow, or until a chosen time. They
resume on their own, and the popover shows "Reminders paused until 15:00 ·
Resume".

**Prompt copy.**

- **Offer, don't instruct:** "Good moment for a 5-minute break?"
- **Give the reason:** "52 minutes in Xcode."
- **After a Skip or a miss:** "No problem."
- **Never:** "you must", or loss framing.

**Prompts and absences.** If a prompt was shown and the person leaves within its
grace window, and the absence reaches the break length, it is recorded as a
break automatically, with no away question. A notice "Recorded a 12-minute
break · Undo" follows. *My call:* the question is redundant when Daybook just
suggested the break. Every other absence keeps today's away question unchanged.

### 5. What gets recorded

**Break records.** These are `SessionRecord`s with `.breakTime`, plus two
optional fields that old data decodes as absent:

- **`breakOrigin`**, one of:

  | Value | Meaning |
  |---|---|
  | `started` | Start break |
  | `prompted` | taken by leaving after a prompt |
  | `answered` | "It was a break" |
  | `away` | a long declared Away |
  | `watching` | a long Watching pause |
  
  Absent means it was recorded before this change.
- **`plannedLength`**, for `started` only.

The builder picks where these live. Fields on the record are the obvious place,
provided `sessions.json` stays readable by older builds (unknown keys ignored).

**Reminder log**, new. For each prompt:

- **Kind:** main, long, eyes or guard.
- **Times:** due, shown and outcome time.
- **Holds:** the hold reasons and the total time held.
- **Outcome**, one of:
  - started
  - left (taken by leaving)
  - later (count)
  - skipped
  - unanswered
  - held
  - credited (a rest arrived before it showed)

**Rhythm in force.** The log also stores, per calendar day, the rhythm in force:

- preset and numbers
- the override, if any
- guard minutes

Write it at the day's first evaluation and rewrite it when settings change
(latest wins). Past figures use the stored rhythm. Days before this feature
existed fall back to the idle cutoff, so they show records and gaps but no
rhythm. *My call:* recomputing history against today's settings would rewrite
the past.

Keep 400 days. This is new live data, so `.claude/hooks/guard-live-data.py` must
learn its path. Eyes prompts are logged as counts per day only.

**Which records count as breaks in section 7:**

- Counted: `started`, `prompted`, `answered` and `away`, plus older records with
  no origin unless they are named "Watching".
- Not counted: `watching` (an evening film is not a work break). Today keeps
  showing those rows as it does now.

No break is ever inferred from a short gap and written as a record. Short gaps
count in the analysis (section 7) from the usage stretches, the same evidence
that resets the clock.

### 6. Menu bar and popover

- **Menu bar label.** It stays as it is (goal ring, session elapsed) with three
  additions:
  - the cup glyph and time left during a break, then overtime
  - a subtle due state while a break is due
  - a paused-reminders mark
- **Popover break line** (today's `FocusBreakLine`) becomes two items:
  - "Next break in 12m · last break 38m ago", or "Break due · Start", or
    "Holding: call", or "Reminders paused until 15:00"
  - a **Start break** button
  
  The time since the last break is the main signal for people with time
  blindness (Pandan and ADHD feedback), more than alerts are.
- **During a break**, the popover leads with the break card from section 3.

### 7. Reviewing breaks

These figures are computed in Core from records, usage stretches and the
reminder log, and published by `SessionStore`. Views never calculate them.

**Today** (day story):

- **Summary line:** "3 breaks · 22 min · longest stretch without a break 1h 40m
  (10:05–11:45)". The stretch is tappable and scrolls the timeline to it.
- **Lunch:** "Lunch away 35 min" when a gap of at least 15 minutes falls between
  11:00 and 14:30. *My call* on the window; the builder may make it follow the
  working-hours window. If it is 14:30, there has been no such gap, and the
  rhythm is on, the next main prompt reads "No lunch break yet. 15 minutes away?".
- Short pauses (rest that was credited but not recorded) are shown as a count:
  "+ 4 short pauses".

**History week and month** cards gain a Breaks section:

- **Totals:** total break time, number of breaks and average length.
- **Rate:** breaks per focused hour.
- **Longest stretch without a break,** with its day.
- **Reminders:** "14 of 20 suggested breaks taken, 3 held for calls". Held and
  skipped are counted neutrally; no percentage is coloured.
- **Lunch:** "Lunch away on 4 of 5 workdays".
- **Rhythm** the week or month ran under, including overrides.
- **Comparison** only with the person's own previous week or month ("2 more
  breaks than last week"). Never a universal norm.
- **At most one sentence of insight,** chosen by a rule, not a model. For
  example: "Your longest stretches were after 14:00." or "Most breaks you took
  were ones you started."

Fix today's limitation: the History journal's day rows show their break count
outside search too (`JournalDay.breaks`, always 0 today).

**Ask Daybook** gets the same figures as facts for a range: breaks, average,
longest stretch, reminder outcomes and lunch days. These sit beside today's
`.breakTaken` events.

There is no month enforcement, but the month card says which rhythm and
overrides the month ran under, so a "lighter month" is visible afterwards.

### 8. What to do on a break

Each prompt and each break card shows one line, chosen by break length and
rotated. A switch in Settings turns it off. The starting set (*my call*; the
copy can be edited before shipping):

- **Under 1 minute:**
  - "Look at something far away and drop your shoulders."
  - "Blink slowly a few times and look out of a window."
- **2 to 5 minutes:**
  - "Stand up and walk for a couple of minutes."
  - "Refill your water."
  - "Stretch your neck, wrists and back."
- **10 minutes or more:**
  - "Step outside if you can."
  - "Talk to someone about anything but work."
  - "Eat away from the desk."
  - "A short walk does more than scrolling."

The tips never suggest checking email or "a quick task", and never shame screen
use.

### 9. Settings

Rename the group "Away & Breaks" to two groups, "Breaks" and "Away".

- **Breaks:**
  - Remind me to take breaks (the master switch)
  - Rhythm (preset picker with its evidence note; Custom shows its fields)
  - Weekday plan (seven rows)
  - Override (none, today, this week, this month or dates)
  - Working hours (off, or from and to)
  - Eyes
  - Long-stretch guard and its minutes
  - Dim the screen if I don't respond
  - Break's-over sound
  - Show countdown in menu bar
  - Suggestions on breaks
  - Pause reminders
- **Away:** everything the group holds today except the break reminder rows:
  - Pause after no input for
  - Ask me after
  - End session after
  - Full-screen prompt after
  - Apps working for you

Clean-ups:

- `fc.workInterval` is dead. Remove the key and its property.
- The setting stored as `fc.breakLength` actually means "End a paused automatic
  session after". Rename the property (for example `autoSessionPauseLimit`) and
  keep the stored key, so existing preferences carry over.

### 10. Accessibility and energy

These are acceptance criteria:

- **VoiceOver:** an announcement for every HUD.
- **Reduce Motion:** dim in one step, no pulsing.
- **Reduce Transparency:** an opaque HUD.
- **Differentiate Without Colour:** every due state carries a glyph and text.
- **Countdown:** it can be hidden from the menu bar.
- **Timers:** no new timers in the UI. Everything runs off `SessionStore`'s 1 Hz
  ticker. The menu bar label model publishes only when the shown text changes,
  so it updates once a minute until the last minute.

## Constraints (from `CLAUDE.md`)

- **Layering:** Core, then App, then Design and Surfaces.
  - Rhythm, schedule resolution, the credit rule, prompt state, the reminder log
    format and every figure in section 7 are Core, pure and tested with
    `TestClock`.
  - Hold signals (camera, microphone, presentation options, IOKit) are App, behind
    a protocol that tests can fake.
- **Session state** stays behind `SessionEngine` and `SessionStore`. Add the
  `.onBreak` pause and break start and end as methods on the owner. Respect
  `keep_internals`.
- **Lengths and zoom:** lengths in Surfaces are tokens or `N.zoomed`. The menu bar
  stays `// zoom: fixed`.
- **Checks:** for every behaviour, in any time zone, with `MemoryDefaults`.
  - Write the clock-edge checks first: sleep and wake, lid open, lock,
    daylight-saving change, midnight crossing, a break across midnight, and a
    relaunch mid-break. These are the bugs every competitor shipped.
  - Each fix comes with a check that fails on the old behaviour.
- **Before commit:** run `fix-reviewer` on anything touching persistence,
  settings, session state or time.
- **Public repository:** no personal data in fixtures or screenshots.

## Phasing (each phase ships on its own)

1. **Take a break:**
   - `.onBreak`, Start break everywhere, timer, break-over HUD, end rules
   - recording with `breakOrigin`
   - menu bar countdown
   - reminder HUD actions (Start, Later, Skip), and break notifications retired
   - the reminder log, including the rhythm in force each day
2. **Rhythm:**
   - presets, Custom and Flow
   - Eyes and the guard
   - weekday plan, overrides, working hours
   - migration
   - Settings regrouped, plus the two clean-ups
3. **Timing:**
   - grace window and breakpoints
   - holds and hold explanations
   - pause reminders
   - gentle dim
   - repeated-skip adaptation
   - auto-recording breaks taken after a prompt
4. **Review:**
   - Today line and lunch
   - History week and month section
   - journal break counts
   - Ask facts
5. **Suggestions and copy pass** against the copy rules above.

## Left to the builder

- Where `breakOrigin`, `plannedLength` and the reminder log are stored, and their
  file format. They must remain readable by older builds and be atomic like the
  existing archives.
- Exact HUD layout and button styling, within the design tokens.
- The shortcut, if ⌥⌘B is taken.
- Whether `.onBreak` reuses the legacy `PauseReason.extendedBreak`, which nothing
  sets and restore reads as "nobody here", or sits beside it. Old data must
  restore the same way either way.
- How "input lull" is measured, as long as it reuses the existing idle source.
- Whether Flow's suggestion appears in the HUD, the popover or both.

## Open spikes (do before the phase that needs them)

- **Camera and microphone, phase 3.** Detect them when actually in use, and check
  for false positives from Continuity Camera, virtual cameras, dictation and
  Siri. Probe with a real capture.
- **Presentation options, phase 3.** Check whether
  `currentSystemPresentationOptions` changes for native full screen, Keynote
  play, a Zoom share and PowerPoint.
- **Menu bar label refresh, phase 1.** Check whether a once-a-minute publish is
  enough for the label, or whether `Text(timerInterval:)` works inside it.
- **Focus mode integration, later and outside this design.** Check whether
  `SetFocusFilterIntent` works in a swiftc-only build; if not, fall back to
  `INFocusStatusCenter`, which adds a permission prompt.
