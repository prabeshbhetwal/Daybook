# Ask Daybook v2, part 1: chat, sources and the side panel

Date: 2026-10-11
Status: design approved section by section on 2026-10-11; written spec awaiting review

## Why

Ask Daybook (⌘K, and the ✦ Ask button in the window bar) answers questions
about focus history with Apple's on-device model through read-only lookups.
The verdict after a day of use, 2026-10-11:

- **Slow.** 2.5 to 9 seconds, one model pass per lookup.
- **Unhelpful.** It restates figures the screens already show. That is by
  design: lookups return fixed facts and the instructions forbid reasoning.
- **Not conversational.** One answer at a time, no transcript.

Ask v2 is four projects, each with its own spec, plan and pull request:

1. **This spec.** Ask becomes a chat; every answer lists its sources, which
   open History at the day, session or period; Daybook caps lookups per
   answer; a setting shows Ask as a side panel instead of a sheet.
2. Lookups for everything the app collects, stores and shows: stretches,
   breaks, away answers, app use by hour, machine events, notes, categories,
   goal, streak, awards.
3. Insights: patterns against the usual, what derails focus, advice and
   planning, explaining a day or week. Code computes; the model explains.
4. The user's own OpenAI or Claude key, opt-in, held in the Keychain, with a
   plain statement in Settings of what is sent.

Part 1 changes no lookup's wording and adds no data. It changes how answers
arrive, how they cite where they came from, and where Ask lives in the window.

## Decisions

| Question | Decision |
|---|---|
| Default model | Apple's on-device model stays the default. Cloud models arrive in part 4 as an opt-in with the user's own key. |
| Apple's Private Cloud Compute model | Not an option. `PrivateCloudComputeLanguageModel` is in the macOS 27 SDK (32K context) and reports `isAvailable == true`, but every request from an ad-hoc binary or ad-hoc-signed bundle fails with `ModelManagerError 1046`. Apple limits the entitlement to App Store Small Business Program developers distributing on the App Store (<https://developer.apple.com/private-cloud-compute/>); Daybook ships ad-hoc signed through GitHub and Sparkle. |
| Architecture | Daybook's own small tool loop. Each lookup is defined once (name, description, parameters, call) in a catalogue; thin adapters present it to each model. Part 1 builds the catalogue and the on-device adapter; part 4 adds OpenAI and Claude adapters over plain `URLSession`. No SwiftPM dependency: `build.sh` compiles `Sources/` with `swiftc` and vendors only Sparkle. |
| On-device loop | **The gate** (chosen): the catalogue becomes one dynamic FoundationModels `Tool` per lookup, so Apple's own tool calling still runs, and every call passes through one gate that counts, caps, reports progress and collects sources. |
| Rejected: Daybook drives every on-device step | Each step a guided generation of "look up X" or "answer". Replaces the tool-calling format the model was trained on, so the 25/25 accuracy evidence of 2026-10-10 would no longer hold; more prompt in a 4K context; slower; streaming the final answer is harder. |
| Rejected: `LanguageModelExecutor` (macOS 27) | Chosen against with the architecture above: it ties cloud models to macOS 27 and to Apple's session type. |
| Sources | **Named by the answer** (chosen): lookups return where each fact lives; after the answer, code keeps the places the answer names, in reading order, then each remaining lookup's own place. |
| Rejected: every place a lookup returned | A session list returns ten sessions; most would be unrelated to the answer. |
| Rejected: the model cites markers | The on-device model is unreliable at copying identifiers. Part 4 may revisit for cloud models. |
| Conversation | A chat in the Ask sheet by default; a setting moves it to a side panel beside Story and History. |
| Chat lifetime | In memory while the app runs. "New chat" or quitting clears it. Never written to disk, as in v1. |
| Lookups per answer | Five real lookups. Calls six and seven are told the limit; an eighth ends the answer with a notice. |
| Instructions and sampling | Unchanged, byte for byte, so the accuracy evidence of 2026-10-10 stands. Greedy sampling kept. |

## Evidence

### Baseline, before any change (2026-10-11)

The live on-device model (M1 Pro, macOS 27.2) through the real store, lookups
and instructions, over the fixture history of the 2026-10-10 accuracy pass
(1 August to Saturday 10 October 2026), in a temporary copy of the tree with
an `--askprobe` entry. 37 questions: the 25 of the accuracy pass, three
open questions, and four short chats of follow-ups in one session.

| Measure | Result |
|---|---|
| Time per answer | median 4.8 s, maximum 8.4 s |
| First answer text | median 4.8 s: the text arrives at the end, because the time goes to lookup passes; streaming hides almost nothing |
| Lookups per answer | mean 1.2, maximum 3; no loop with the real lookups |
| Follow-ups in one session | 6 of 6 right ("How much did I focus in August?" then "And in September?", "Which day that month was best?", "What did I work on that day?"); four turns did not fill the context |
| Open questions | "What should I change?" invented "10 consecutive sessions on 6 October": there is nothing to answer it from until parts 2 and 3 |

### The loop

The lookup that looped forever was a throwaway repro, not one of the app's:
a single stub `focusTotals` that returned the same text whatever period it
was given, asked "What should I change to focus more next week?". The model
called it at least 33 times, alternating periods, and never answered. With
the real lookups, no question has looped, before or after the accuracy pass
(at most six lookups before it, two after). An advice question over lookups
that cannot answer it is the shape that loops, and parts 2 and 3 add exactly
those questions, so the cap is in code.

### After (2026-10-11)

The same fixture, questions and live model over the finished tree (the chat,
the gate, the sources and the side panel), in a temporary copy with an
`--askprobe` entry that drives `AskModel.turns` as the chat does. The
baseline table above is the first run's record, kept as written; its log was
lost in a restart, so it can no longer be re-checked. The baseline was therefore
run again the same day from the tree this work branched from (9424aad) with the
same 37 questions, and every comparison below is against those regenerated
runs. On them "What did I work on that day?" reads Parser 2h 00m, which is
wrong (the model read the 2:00pm start as a duration), so the table's "6 of 6
right" holds for the first run only. The speed gate of section 9 (no worse than
4.8 and 8.4 s) was met on the quiet run only: the busy runs measured 5.0 / 9.4 s
and 5.0 / 10.2 s against busy baselines of 4.5 / 8.1 s and 4.5 / 9.5 s. Nothing
from the probe copy is committed.

| Measure | Result |
|---|---|
| Parity, 37 questions, three runs of each build | All 37 answers identical to the baseline in all three pairs, with the same lookups. Only the order of the Used list differs, in 1, 3 and 0 of the 37, always where the model asks two or more lookups in one step (September and August; this week and last week). FoundationModels may run the two tools at once, and the gate records them as they arrive. One such question asked 12 times: the baseline listed September first 12 times; the finished build 9 times and August first 3, with the same answer every time. Sources the answer does not name follow lookup order, so they swap the same way |
| Depth, ten follow-ups in one chat | All ten answered; the context did not fill (no retry, no notice). "And in September?" right (120h 18m) and "Which day that month was best?" right (Tue 15 Sep, 9h). Not right on a careful read: "What did I work on that day?" gave Parser 2h 00m (the lookup lists "2:00pm · Parser · 4h"; the model read the start time as a duration, as it did on the regenerated baseline); "Did I write any notes?" said none in September (it searched the word "notes"; the 23 September note says "chapter three"); "And the week before?" answered with Mon 14 Sep, one day, and "Which app did I use most then?" followed it; "Is that true for Mondays too?" (turn 10) looked up Mon 5 Oct and said it could not confirm (weak) |
| Depth, the same ten three times (30 turns) | The context filled at turn 24. The turn was retried once in a fresh session told the last two finished turns, with no notice, in 7.2 s. The retried "What did I work on that day?" took "that day" to be today although the carried turn said Tue 15 Sep, and the next question, "How long was the longest one?", was answered for today. Turns 11 to 23 repeated earlier questions and were answered from the chat with no lookup. Turn 26 made 5 lookups and a sixth call that met the limit, then answered |
| Carry after Stop | Stop pressed on a second question: "And in September?" right with one turn carried; "Which day in September was best?" right with two carried. "Which day that month was best?" gave October, twice; the same question after an unrelated answered turn, with no Stop, gave August: an implied "that month" is lost across a gap whether or not a session was dropped |
| Cap, stub `focusOutlook` as a sixth entry (probe copy only), "What should I change to focus more next week?" | Stub texts that ask for another period ("Outlook unavailable for this period. Try again with a different period."; "Nothing to report. Look up another period."): the turn ended failed with the "Ask kept looking things up…" notice at the eighth call, five real lookups listed, no answer text, 8.9 s and 8.7 s. A stub that said only "it depends on what you want to change" was answered after one call, and "No outlook is available for that period. Try another period." after six (five real, the sixth told the limit), in 30 s |
| Time per answer, median / maximum | Baseline then finished build. Two runs while other sessions were compiling: 4.5 / 8.1 s then 5.0 / 9.4 s, and 4.5 / 9.5 s then 5.0 / 10.2 s. One run on a quiet machine: 3.6 / 6.4 s then 3.7 / 6.4 s (this finished build was the instrumented probe, which also timestamps each lookup). The finished build is no slower beyond run-to-run spread on a quiet machine; under load it was about 0.5 s slower at the median in both runs, and the cause was not isolated. The probe binaries are unoptimised |
| Time to the first progress line (finished build) | Median 3.0 s and maximum 5.9 s (busy), median 3.1 s and maximum 8.6 s (busy), median 2.4 s and maximum 3.9 s (quiet); the answer text still arrives at the end, as at baseline. One answer in 37 makes no lookup |

What this leaves open: an implied "that day" or "that month" is not reliably
carried into a session rebuilt after a full context or Stop, because the
carried turns are plain text in the instructions. The Parser answer above is
the regenerated baseline's, word for word, so this part did not cause it.

## 1. Parts

| Layer | File | Responsibility |
|---|---|---|
| Core | `AskLookupSpec.swift` | A lookup's name, description and parameters (`AskParameter`: name, description, required). Every parameter is a string, as today. |
| Core | `AskLink.swift` | A source: target (`day`, `session(thread, day)`, `period(HistoryPlace)`, `history`), label, role, and the session's name for matching. |
| Core | `AskSourcePicker.swift` | Pure: the finished answer, the lookups' sources, a calendar and today → the ordered source list and the span of the answer each named source was found at. |
| Core | `AskTurn.swift` | One question and its answer: text, state (looking up, answering, answered, stopped, failed with a notice), sources. |
| Core | `AskFacts.swift` | Gains the limit line and the new notices' wording. Nothing else changes. |
| App | `AskLookups.swift` | The catalogue: today's five lookups with their names, descriptions and guides copied verbatim from `AskTools.swift`, and how each turns arguments into an `AskRequest` or a refusal ("There is no such date as “31 february”."). Replaces `AskTools.swift`. |
| App | `AskGate.swift` | One per answer: counts calls, enforces the cap, publishes the progress line, records provenance and sources. Knows no model. |
| App | `AskOnDevice.swift` | The FoundationModels adapter: one dynamic `Tool` per catalogue entry, the model session, greedy options, the context-full retry. Everything behind `@available(macOS 26, *)`. |
| App | `AskModel.swift` (+ `AskModel+Notices.swift`) | The chat: `turns`, `ask`, `stop`, `newChat`; availability through `ModelGate.modelAvailable`. Notices move to their own file to keep both under 300 lines. |
| App | `SessionStore+Ask.swift` (+ `SessionStore+AskLinks.swift`) | `askLookup` still returns the same text; a sibling returns the text with its sources. |
| App | `MainWindowModel.swift` | Knows the placement; opens or toggles Ask; follows a source into History (`openHistory(place:)` is new). |
| Core/App | `PersistenceStore`, `SettingsModel` | `fc.askPlacement`: `sheet` (default) or `panel`. |
| Surfaces | `Ask/AskChatView.swift`, `AskTurnView.swift`, `AskSourcesView.swift` | The transcript, one turn, one turn's sources. Shared by both placements. |
| Surfaces | `Ask/AskSheet.swift`, `Ask/AskPanel.swift` | The two wrappers. |
| Surfaces | `Main/MainWindowView.swift`, `Main/AskChromeButton.swift` | The panel's slot beside the reading workspace; the button shows when the panel is open. |
| Design | `Components/ZoomWindowFit.swift` | Grows the window when its base grows, as it already does for a zoom step. |
| Surfaces | `Settings/SettingsAskPanel.swift` | The placement picker. |

Rules kept from v1:

- Views bind to `AskModel` and `MainWindowModel` only; they never read storage or work out figures.
- No lookup writes. Nothing in this project calls a `SessionStore` action.
- `AskModel` is built on the first ⌘K. With Ask never opened, nothing of it exists and idle CPU is unchanged.
- Lengths are design tokens or `.zoomed`; text uses the type roles.

## 2. The catalogue and the on-device adapter

```swift
struct AskParameter { let name: String; let description: String; let required: Bool }
struct AskLookupSpec { let name: String; let description: String; let parameters: [AskParameter] }

// App: one entry per lookup
struct AskLookup {
    let spec: AskLookupSpec
    /// Arguments as plain strings, trimmed; an empty one is absent.
    let request: (_ arguments: [String: String], _ period: (String) -> AskRange?) -> AskLookupCall
}
enum AskLookupCall { case request(AskRequest), refusal(String) }
```

The five entries are today's `focusTotals`, `compareFocus`, `bestHours`,
`findSessions` and `appTime`, with the same names, descriptions, parameter
names, parameter descriptions, optionality and order, and the same reading of
periods through `AskRange.resolving`.

The on-device adapter builds one `Tool` per entry:

- `Arguments` is `GeneratedContent`; `parameters` is a `GenerationSchema` built
  from the spec with `DynamicGenerationSchema` (macOS 26): one string property
  per parameter, with its description, optional where it is optional.
- `call` reads each property as a string and hands the name and arguments to
  the gate. Tools are listed in today's order.
- No regex guide, no `toolCallingMode`: both broke the model in the probes of
  2026-10-10 (see the v1 spec, §8).

Acceptance: probe 1 (§9) puts the 37 baseline questions through the dynamic
tools. With greedy sampling the same tool calls and the same answer text are
expected. Any difference is investigated before anything else is built, and
part 1 ships only if every answer is still right.

## 3. The gate

One gate per answer, on the main actor. Every adapter, now and in part 4,
calls `lookup(name:arguments:) -> String` and nothing else.

| Call in this answer | The gate |
|---|---|
| 1 to 5 | Reads the arguments through the catalogue, asks the store, returns the text. Records the provenance and the sources, and publishes "Looking up focus totals (August 2026)…". |
| 6 and 7 | Asks nothing. Returns "Lookup limit reached for this question. Answer from what the earlier lookups returned." |
| 8 | Ends the answer. The turn shows "Ask kept looking things up without answering. Try asking about one period or one thing." |
| Any, after the turn ended (stopped, new chat, a dropped session) | Returns the text if it can, records nothing: the rule v1's `generation` counter kept. |

An unknown lookup name gets "No lookup called “X”." and counts. A refusal
(no such date, a period still to come) counts and is returned as text, as
today. Wording lives in `AskFacts`.

FoundationModels may run tools concurrently; the gate is main-actor, so calls
are taken one at a time and counted in the order they arrive.

## 4. The conversation

- **Turns.** Each question appends a turn. A turn shows its question at once,
  then its progress line from the first lookup, then the answer as it streams.
  Earlier turns never change.
- **One model session per chat.** Follow-ups go to the same session, so "And
  in September?" knows what was asked before (baseline: 6 of 6).
- **Stop.** While answering, the send button is Stop. Stop cancels the
  answer; the turn keeps what had streamed and shows "Stopped.". This also
  covers a model that never finishes, as `toolCallingMode = .required` did, so
  there is no watchdog timer. Stop also drops the model session, and the next
  question builds a new one carrying the last two finished turns, as a full
  context does below: a lookup the stopped answer had already begun could
  otherwise land in the next answer's session and be counted there.
- **Context full.** On `exceededContextWindowSize` (macOS 26) or
  `contextSizeExceeded` (macOS 27): drop the session, build a new one whose
  instructions are today's followed by the last two finished turns as plain
  text ("Earlier in this chat, the user asked … and you answered …"; no lookup
  output), and ask the same question again, once, without telling the reader.
  If that is full too, the turn shows "That question needs more room than
  Apple's on-device model has. Try a shorter question, or start a new chat."
  This replaces v1's "Started a new thread" notice.
- **Midnight.** As in v1, a session built on an earlier day is dropped before
  the next question. Nothing is carried over: the earlier turns' "today" and
  "yesterday" would now mean other days. The transcript on screen stays.
- **Errors.** v1's mapping stays (guardrail or refusal: "Can't answer that
  one."; an unsupported language; anything else worded from the error). The
  notice belongs to the failed turn; earlier turns are untouched.
- **Availability.** macOS 14 to 25, a Mac that cannot run the model, Apple
  Intelligence off and the model downloading keep v1's lines, shown above the
  composer, with the Open Settings button where v1 had it. Ask reads
  `ModelGate.modelAvailable`, the check the Apple Intelligence notes project
  added; the "Use Apple Intelligence" switch does not govern Ask.
- **New chat.** Cancels any answer, clears the turns, drops the session.

## 5. Sources

### What each lookup gives

| Lookup | Sources, in this order (the first is the lookup's anchor) |
|---|---|
| `focusTotals` | the period asked about; the most focused day, week and month it names; the longest session |
| `compareFocus` | both periods |
| `bestHours` | the period asked about |
| `findSessions` | the period asked about; each session listed (at most ten) |
| `appTime` | the period asked about |

A period is a History place when it is a day, week, month or year. "All
time" and "last 30 days" are not; their source is History itself, labelled
with the range's title and dates, and opens History at the top.

Labels use the date forms the lookups already write (`askDay`, `askLabel`):
day `Tue 15 Sep`, session `Thesis · Tue 15 Sep`, week `5 Oct – 11 Oct`, month
`August 2026`, year `2026`.
Roles: Totals, Most focused day, Most focused week, Most focused month,
Longest session, Session, Compared, Best hours, App time.

### Which the answer names

After the answer finishes, `AskSourcePicker` reads it:

1. A **day** is named by its day number and month together, in any order and
   form: "15 September", "Tue 15 Sep", "Tuesday, 15 September", "September
   15", "15th of Sep". A year written with it must match. "today" and
   "yesterday" name those days.
2. A **session** is named by its name as whole words, ignoring case and
   accents (`SearchWords.fold`). When several sources share the name, those
   whose day is also named are kept; when none is, the newest.
3. A **month** is named by its name where no day number is attached to it,
   with its year if one is written. A **year** by its number where it is not
   part of a date. A **week** by its label, by its first and last days
   together, by "week of" its first day, or by "this week" or "last week"
   when it is that week.

### The order

The list is the order a reader can check the answer by:

1. sources the answer names, in the order it names them;
2. then each lookup's anchor not already listed, in the order the lookups were made.

So every lookup the answer rests on appears, and the first row is the first
thing the answer talks about. The list shows five rows; more add "Show N
more". Duplicates (the same target) appear once, at their first place. A
stopped or failed turn has no sources.

Each named source's first mention in the answer becomes a link to the same
place, in the action colour. The list is the complete, keyboard- and
VoiceOver-reachable record; the link serves the reader's eye where it already is.

### Following a source

`MainWindowModel.follow(_:)`:

| Source | Opens |
|---|---|
| Day | History, that day open (`openHistory(day:)`) |
| Session | History, its day open and the session picked, so the rail describes it (`selectHistory(session:on:)`); if the session no longer exists on that day, the day only |
| Week, month, year | History unfolded to that row, focused and scrolled to (`openHistory(place:)`: the path to its first day, cut at its level); a period outside the record opens History at the top |
| History itself | History at the top |

In the sheet the sheet closes first; the chat stays and ⌘K reopens it. In the
panel the panel stays, so the source opens beside the chat. Every source
opens History, today included: one rule.

## 6. The chat surface

Sheet: 640 by 600 points at 100%, shrinking with the window as v1's does
(v1 was 520 tall; the transcript needs the room).

```
┌─ Ask Daybook ───────────────────────────────── New chat  ✕ ┐
│                         ╭ How much did I focus in August? ╮│  question: quiet neutral pill, trailing
│                                                            │
│  In August 2026 you focused 60h 54m over 63 sessions on    │  answer: prose, not a bubble
│  21 days. The most focused day was Mon 3 Aug, 4h 30m.      │  named sources are links
│                                                            │
│  Sources                                                   │
│  1  ▦ August 2026          Totals                       ›  │  each row a button
│  2  ▦ Mon 3 Aug            Most focused day             ›  │
│                                                            │
│                                  ╭ And in September? ╮     │
│  ◌ Looking up focus totals (September 2026)…               │  progress, then the answer
├────────────────────────────────────────────────────────────┤
│ ╭────────────────────────────────────────────────╮ [Stop]  │  composer, pinned
│ │ Ask about your focus…                          │         │
│ ╰────────────────────────────────────────────────╯         │
│ (Apple Intelligence glyph) Answered by Apple Intelligence  │
│ on this Mac. Nothing leaves it.                            │
└────────────────────────────────────────────────────────────┘
```

Empty chat: "Ask about your focus. Each answer lists the days and sessions it
came from." then "Try asking" and v1's four example questions, each asking itself.

- New chat is in the header, beside the close button, in the sheet as in the
  panel (the same button, in the same style): it appears once the chat has a
  turn, and it empties the chat, the draft included. The footer carries only
  the line naming who answers.
- The transcript scrolls and stays at the bottom while an answer streams
  (`defaultScrollAnchor(.bottom)`, macOS 14).
- The field stays editable while an answer is worked out; ↩ does nothing
  until it is done. The cursor returns to the field after an answer only when
  it was in the field when the question was asked, so a finished answer beside
  History does not pull it out of History.
- Source rows: number, glyph (calendar for a day or period, clock for a
  session), label in the label role and the primary ink, role in the body role
  and the supporting ink, chevron. A row is at least the minimum target size.
  The panel always sets the role under the label; the sheet sets it on the
  label's line when every row's label and role fit there, and under it for the
  whole list otherwise, so the rows of one list are never of mixed heights.
- Supporting text (the role, the Sources heading, the footer line, "Stopped.",
  the field's placeholder) is set in the body role or the label role and in the
  supporting ink, `.primary` at 75%, which holds 4.5:1 on every surface Ask
  draws on in both appearances. `.secondary` is 3.9:1 on the light surfaces.
  A stopped answer's partial text is set in the same ink.
- The composer is a single line that grows to four as the question is typed;
  ↩ still asks. In the sheet an answer's prose is held to 480 points (at
  100%) so its lines stay readable; the panel is narrower than that.
- The Apple Intelligence glyph stays only on the footer line that names Apple
  Intelligence; the bar button keeps `sparkles`.
- VoiceOver: a turn is one element, "You asked … Ask answered …"; a source
  row reads "Mon 3 Aug, most focused day. Opens in History."; a finished
  answer is announced with its number of sources.
- Direction: product register, restrained colour. Tinted neutrals; the
  action colour only on links in the answer, "Show N more", Send and the bar
  button while the panel is open; source rows read in the primary ink, so the
  list does not outweigh the answer, and their chevron says they open; indigo
  stays the focus identity; the sparkles gradient only on the bar button. No avatar, no typing
  dots, no persona, no emoji, no gradients, no cards inside cards, no em
  dashes in copy. Anchors: Xcode 26's coding assistant (a chat beside the
  work), the native trailing inspector of Finder and Mail, and the Day as a
  Story prototype for type and the rail's neutral layer.

## 7. The side panel

```
┌ ◂  Today ‹ › · History        ● 1:12:04          (✦ Ask) ⚙ ┐   Ask button pressed while open
├────────────────────────────────┬──────────┬──────────────────────────┤
│ Story column, or History       │ rail     │ Ask Daybook   New chat  ✕ │
│                                │ 300 pt   │──────────────────────────│
│                                │          │   ╭ How much in August? ╮ │
│                                │          │ In August 2026 you…       │
│                                │          │ Sources                   │
│                                │          │ 1 ▦ August 2026   Totals ›│
│                                │          │ 2 ▦ Mon 3 Aug   Most fo… ›│
│                                │          │──────────────────────────│
│                                │          │ ╭ Ask about your focus… ╮↑│
│                                │          │ Answered on this Mac      │
└────────────────────────────────┴──────────┴──────────────────────────┘
                                              360 pt at 100%, rail neutral fill
```

- At window level: below the chrome bar and the session strip, beside the
  reading workspace, so it stays when the window moves between Story and
  History. A source opens History beside the chat.
- Width 360 points at 100% (`.zoomed`), the rail's neutral fill, a divider on
  its leading edge. The same `AskChatView` as the sheet, under a header with
  the title, New chat and a close button.
- ⌘K and the bar's Ask button open and close it; the button looks pressed
  while it is open (in the action colour, so it does not read as hovered). It
  opens with the cursor in the field every time it opens, whether or not the
  chat already has turns and whichever control, such as the bar's activity
  field, had the cursor before. Escape with the cursor in the panel closes it.
  Its close button's help is "Close Ask (⌘K)".
- While it is open the window's minimum width grows by its width (980 to
  1,340 points at 100%). `ZoomWindowFit` grows the window to fit, keeping the
  top-left corner and the screen's bounds, as it does for a zoom step; closing
  never shrinks the window.
- A screen that cannot hold the panel gets the sheet instead. The panel has
  room when the window's minimum with it (1,340 by 680 points at 100%, times the
  zoom) is not held to the screen's visible area less the 40 point margin:
  1,380 by 720 at 100%, 1,916 by 992 at 140%. Where it has none, ⌘K, the bar's
  Ask button and Settings' Open Ask open the sheet whatever the choice, and the
  choice is kept. A panel that is open when the room goes (a zoom step, a move
  to a smaller screen) closes and the sheet opens on the same chat; the next ⌘K
  opens the panel again once there is room. Another sheet over the window, such
  as Settings, stays: only the panel closes.
- Settings, Awards and the session report still cover the whole window, panel included.
  With the side-panel placement, ⌘K over Settings or Awards closes that sheet
  and opens the panel, so the shortcut always lands in the chat.
- It starts closed at each launch.

Settings, in the Ask panel of General: **Open Ask in** `Sheet | Side panel`,
detail "A side panel stays beside Story and History, so sources open next to
the chat. On a screen too small for both, Ask opens as a sheet." Changing it
while the panel is open closes the panel; the next ⌘K uses the new choice.
Disabled on a Mac that can never run Ask.

## 8. Copy

| Element | Copy |
|---|---|
| Empty chat | Ask about your focus. Each answer lists the days and sessions it came from. |
| Field | Ask about your focus… |
| Progress | Looking up focus totals (August 2026)… (the lookup's provenance) |
| List heading | Sources |
| Stop, after | Stop; Stopped. |
| Limit, to the model | Lookup limit reached for this question. Answer from what the earlier lookups returned. |
| Limit, to the reader | Ask kept looking things up without answering. Try asking about one period or one thing. |
| Context full | That question needs more room than Apple's on-device model has. Try a shorter question, or start a new chat. |
| Unknown lookup, to the model | No lookup called “X”. |
| New chat | New chat |
| Panel close help | Close Ask (⌘K) |
| Placement | Open Ask in: Sheet, Side panel |

## 9. Live-model probes

In a temporary copy of the tree with the `--askprobe` entry, over the
baseline's fixture, recorded in this spec before the pull request:

1. **Parity.** The 37 baseline questions through the dynamic tools: same tool
   calls and same answers expected. Differences investigated; every answer
   must still be right.
2. **Depth.** One chat of ten follow-ups: where the context fills, and whether
   "And in September?" is still answered rightly after the carry-over.
3. **Cap.** A stub lookup returning fixed text, through the gate, asked the
   repro's advice question: the answer ends at the eighth call with the notice.
4. **Speed.** Median and maximum time per answer no worse than the baseline's
   4.8 and 8.4 seconds; time to the first progress line recorded.

## 10. Checks

Existing suites keep passing unchanged where they read lookup text
(`AskLookup*`, `AskAccuracyChecks`, `AskEdgeChecks`, `AskOverlapChecks` and
the rest): the text does not change. `AskModelChecks`, `AskThreadChecks` and
`AskEntryChecks` move to the `turns` interface with the same assertions;
v1's "Started a new thread" assertion becomes the context-full retry below.

New suites, appended at the end of `registeredTests`; their numbers are
assigned when they merge:

| Suite | Fails when |
|---|---|
| `AskCatalogueChecks` | an entry's name, description, parameters or order differ from v1's tools; arguments read to the wrong request or refusal; a dynamic schema fails to build (macOS 26 at run time; CI runs macOS 26) |
| `AskGateChecks` | a sixth call reaches the store; an eighth does not end the answer; a call after the turn ended records anything; the progress line or provenance is wrong; an unknown name is not counted |
| `AskLookupLinkChecks` | a lookup's sources miss or misplace the period, best day, week or month, longest session (thread and first day in the range), listed sessions or compared periods |
| `AskSourceOrderChecks` | over a table of the baseline's real answers ("Tuesday, 15 September", "Tue 15 Sep 2026", "Friday 9 October", "September 2026", "5 Oct – 11 Oct", "yesterday"): order is not reading order then lookup order; a name is missed; a wrong year is accepted; an ambiguous session name picks the wrong session; an anchor is missing; a list over five has no "Show N more" |
| `AskChatChecks` | through v1's `responder` seam: a follow-up is not appended; a failure changes an earlier turn; Stop loses streamed text; New chat leaves state; a full context does not carry two turns and retry once; a second full context shows no notice; midnight carries anything over |
| `AskFollowChecks` | a source opens the wrong History place; a missing session does not fall back to its day; the sheet stays open in the sheet placement; the panel closes in the panel placement |
| `AskPanelChecks` | the placement is not saved (`MemoryDefaults`) or does not default to Sheet; ⌘K does not toggle the panel; the window minimum lacks the panel's width while open; changing the placement leaves the panel open; render evidence lacks the panel beside Story or beside History |

Every check uses `TestClock`, `SelfTest.scratchDirectory()` and `MemoryDefaults`,
and builds dates from the calendar the code uses. The suite also runs with
`TZ=Europe/Berlin`.

Mutations before commit, each in a temporary copy of the tree:

- sources sorted by lookup order instead of reading order: `AskSourceOrderChecks` fails;
- the cap one higher: `AskGateChecks` fails;
- the carry-over removed: `AskChatChecks` fails.

Before commit, `fix-reviewer` reviews the change: it touches session state
(the chat) and time arithmetic (dates read from answers).

## 11. Snapshots and design review

`--snapshot` scenarios: the sheet empty, with two turns and sources, with a
failed turn and with a stopped turn; the panel beside Story and beside
History. Light and dark, at 80%, 100% and 140%. The renders get a critique
pass (impeccable critique and design critique) before the pull request;
fixes go in the same pull request.

## 12. Hand checks

On a Mac with Apple Intelligence on, over real history, before merge:

| # | Do | Passes when |
|---|---|---|
| 1 | Ask three follow-ups in the sheet | Each answer follows from the one before |
| 2 | Click each source row of an answer | Each opens the day, session or period it names |
| 3 | Switch to the side panel; open History; click a source | History moves; the chat stays |
| 4 | ⌘K twice in each placement | Opens, then closes |
| 5 | VoiceOver through one turn | Question, answer and each source are read |
| 6 | 140% zoom with the panel open | Nothing is cut off; the window fits the screen |

## 13. Privacy and README

The README's "Private by construction" paragraph opens with "Nothing leaves
your Mac unless you want it to." and keeps each path after it, each one a
choice: the update check, which can be turned off in Settings (Check for
updates automatically); dictation; iCloud Drive backups. Ask's own sentence
stays: on-device, nothing sent. Part 4 adds the cloud key to that paragraph.

## 14. Working beside other projects

- The Apple Intelligence notes project (not yet merged) adds
  `Sources/App/ModelGate.swift`. Ask reads it. If this project merges first,
  it adds that file byte for byte, so the two merge cleanly in either order.
- Overlaps expected when merging main: `MainWindowModel` beside `askModel`,
  the `PersistenceStore` and `SettingsModel` keys, the README's privacy
  paragraph (the notes project adds a sentence after Ask's), and the registry
  tail. Whoever merges second resolves them and renumbers checks.
- Files are claimed on the sessions board; the change ships by pull request
  after merging main.

## Out of scope

- New lookups (part 2), insights (part 3), cloud models and keys (part 4).
- Saved chats, voice input, the model writing anything.
- Citations the model writes itself.
- A watchdog timer: Stop covers an answer that never finishes.
