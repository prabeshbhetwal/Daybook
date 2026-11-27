# Agent lane: what you did, and what your agent did

Status: approved, 27 November 2026.

## Why

One session last night (26 Nov 20:03 to 27 Nov 16:30) showed 11.95 h on the
clock. The evidence the app itself recorded (30 s beats) splits it:

| Presence while the session ran | Hours |
|---|---|
| Keyboard or mouse input | 5.55 |
| Short quiet, under the 5 min idle threshold (reading, thinking) | 2.65 |
| AI agent working, no input | 3.46 |
| Screen kept awake by media, no input | 0.04 |

Sleep itself was handled: the screen lock at 04:48 paused the session until
08:48. The inflation came from the agent rule: `AgentQuietPolicy` defaults to
`countAsWork` with no limit, so every minute an agent worked while nobody
touched the Mac went on the session clock and into History, indistinguishable
from hands-on work. Daily goals were mostly spared, because they intersect
the session with app-use spans that end on idle (`FocusedActiveTime`).

## The model: two lanes

A session keeps one wall clock, as now. Inside it, time belongs to one or
both of two lanes:

- **You**: time with input, plus short quiet (under the idle threshold).
  Categorised by the foreground app, as app categories already are.
- **Agent**: time an agent was observed working (pings on
  `com.prabesh.daybook.agent-activity`, or detection in `AgentPresence`).
  Categorised by the agent app's own category.

The lanes can overlap. An agent coding while you watch YouTube is both:
Agent lane in Coding, You lane in Watching. Totals therefore never add the
lanes; the panel and History show each lane and, where they overlap, say so.

## Scenarios

| Situation | You lane | Agent lane | Session clock |
|---|---|---|---|
| Coding by hand | Coding | nothing | runs |
| Agent codes, you sit idle at the Mac | nothing after the idle threshold | Coding | runs |
| Agent codes, you watch YouTube for fun | Watching (not focus) | Coding | runs |
| You watch a YouTube tutorial while coding | split by foreground app: Learning slices and Coding slices | as observed | runs |
| Agent codes, you watch a full-screen film, no input | Watching (screen kept awake by media) | Coding | runs |
| Agent waits on a long cloud task, nothing local happens | nothing | nothing observed, unless you declared a hand-off | pauses on idle as today, unless handed off |
| You lock the screen or the Mac sleeps | nothing | nothing (agents on a locked Mac are not observed) | pauses, as today |

Learning versus leisure on YouTube needs the site signal, which is still off
pending its probe and consent. Until then a browser counts by its app
category, as today.

## Hand off to agent

A new action beside Step Away: **Hand off to agent**. It tells Daybook "my
agent is working, I am stepping back". While handed off:

- the session keeps running in the Agent lane, even with no local signal
  (covers the cloud-task case), labelled as declared rather than observed;
- the You lane stops; no away question is asked;
- input brings you back: the You lane resumes and the hand-off ends;
- it ends on its own after the limit below, back-dated to the limit.

## Settings (Settings, Tracking group)

**Agent at work** (replaces the current three choices):

1. Track separately (default): Agent lane recorded and shown; goals count
   only the You lane.
2. Count with my time: goals count You and Agent lanes in each category,
   as a union, so an overlap in the same category is never counted twice.
3. Pause the session: today's `pauseQuietly`.
4. Treat it as time away: today's `ignore`, kept so nobody's behaviour
   changes without their say.

Existing `countAsWork` users move to Count with my time, so their goals do
not drop overnight; the update notes say where the switch is.

**Unattended agent time counts for at most**: 30 min, 1 h (default), 2 h,
4 h, no limit. Past it, with no input, Agent lane time is still recorded and
shown, but stops counting toward goals; a declared hand-off ends.

## Where it shows

- Menu panel hero: the session clock stays the big number. Beneath it:
  `You 8h 21m · Agent 3h 28m`, hidden when the Agent lane is empty.
- History: each session shows both lanes; old sessions without lane data
  show no split at all (never "0m agent").
- Goals card: per goal, the You part of the bar, plus an Agent part in a
  lighter tint when it counts.

## Data

- `SessionRecord.agentSpans: [DateInterval]?` plus a declared flag per span,
  and the same on the live checkpoint, so a relaunch or crash keeps them.
  Spans, not a total, so midnight splits, session splits, merges and trims
  slice them exactly as they slice `pausedSpans`. `nil` means recorded
  before this change.
- A span opens at the first agent signal after the last input and closes at
  the last agent signal, not when the five minute presence window expires.
- On crash restore an open span closes at the checkpoint's `savedAt`.
- Beats stay evidence only (they expire after about nine days).

## Reviewed by

Codex (GPT, architect) and Gemini 4 Neon (high), 27 November 2026. Both
agreed on persisted spans, the setting, short quiet as You, and exact span
edges. They split on a cap; the owner chose a user setting.

## Decisions (owner, 27 November 2026)

1. Agent lane time takes the agent app's own category (T3 Code, Claude,
   Codex: whatever app categories assign them), not the session's.
2. A hand-off ends on the same limit as unattended agent time (one setting).
   Hand off to agent ships under a new **Labs** settings section for
   experimental features, so users know it is still being tried out.
3. Two releases:
   - **Phase 1**: observed Agent lane, persisted spans, You/Agent split in
     the panel hero and History, the Agent at work setting and the
     unattended limit, goals per the setting.
   - **Phase 2**: Labs section, Hand off to agent, overlapping lanes in
     different categories (agent in Coding while you are in Watching).
