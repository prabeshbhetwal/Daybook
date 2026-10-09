# Ask Daybook

Date: 2026-10-09
Status: approved in conversation 2026-10-09; spec awaiting review

## Why

Daybook already knows how long you focused, on what, when and in which apps,
but finding an answer means reading charts or scrolling History. Ask Daybook
lets you type a question ("When do I focus best?", "How long on thesis this
week?") and get a one-to-three sentence answer drawn from your own history.

Goal: a small agent that chooses which of Daybook's figures to look up, chains
lookups when a question needs two, and phrases the result, without sending
anything off the Mac and without being able to change any data.

This is the first of three projects. The daily review note (project 2) and
background tidying of names and rules (project 3) get their own specs and
reuse what this one builds.

## Decisions

| Question | Decision |
|---|---|
| Model | Apple's on-device model (`FoundationModels`, `SystemLanguageModel.default`). Free, no API key, nothing leaves the Mac. |
| Rejected: cloud model (e.g. Claude Haiku over `URLSession`) | Costs per call, needs a Keychain-held key, and sends session names and notes off the Mac, which breaks the README's privacy statement. No official Swift SDK. |
| Rejected: both behind a provider interface | One implementation is enough until a need appears. |
| First job | Answering questions about history. Read-only. |
| Surface | A fourth main-window sheet beside Insights, Awards and Settings, opened with ⌘K (free; no existing ⌘K binding). |
| Rejected: History search field | Gives one field two meanings. |
| Rejected: menu-bar popover | Too small for answers. |
| Approach | Tools return finished facts. Code computes and formats every number; the model chooses tools and phrases the answer. |
| Rejected: facts pasted into the prompt | Not agentic, and the model's small context limits how much history fits. |
| Rejected: model fills a query form, templates answer | Exact but rigid; only templated question shapes work. |
| Threads | Held in memory while the app runs. "New question" or quitting clears them. Never written to disk. |
| Minimum macOS | Unchanged at 14. Ask needs macOS 26 and says so on older systems. |

## Evidence

Probe on 2026-10-09, M1 Pro, macOS 27.2, built with plain `swiftc` (no Xcode
project), in a temporary folder since deleted:

```
availability=available
reply=You are currently working on writing a thesis using Xcode and Safari. secs=4.93832802772522
```

The probe defined one tool with a `@Generable` argument struct; the macro
expanded under `swiftc`, the model called the tool, and the reply used its
output. 4.9 s is the first, cold call.

## 1. Parts

| Layer | File | Responsibility |
|---|---|---|
| Core | `Sources/Core/AskFacts.swift` | Pure functions from the session archive, a range and optional words to a short finished text. No `FoundationModels` import, so it passes the standalone Core typecheck. |
| App | `Sources/App/AskTools.swift` | Four read-only tools, each `@available(macOS 26, *)`, each calling `AskFacts` through `SessionStore`. |
| App | `Sources/App/AskModel.swift` | Owns the `LanguageModelSession`, the availability state, the busy flag, and the answer and provenance the sheet shows. |
| Surfaces | `Sources/Surfaces/Ask/AskSheet.swift` | The sheet: field, answer, "Used:" line, "New question". |
| App | `MainWindowModel.swift` | One new sheet case, `ask`, beside `insights`, `awards`, `settings`. |
| build | `build.sh` | Weak-link `FoundationModels` so the app launches on macOS 14–25. |

Rules kept:

- Views never read storage or compute figures; the sheet binds to `AskModel` only.
- No tool writes. Nothing in this project calls a `SessionStore` action.
- `AskModel` is created on the first ⌘K. With the sheet closed nothing runs, so idle CPU is unchanged.
- Lengths are design tokens or `.zoomed`, and text uses the type roles, so the build's zoom and raw-size guards pass.

## 2. Facts and tools

Range is a closed set the model picks from:
today, yesterday, this week, last week, this month, last month, last 30 days,
all time. Boundaries come from the calendar the rest of the app uses, so a
week here is the same week History shows.

| Tool | Arguments | Returns (example) | Built on |
|---|---|---|---|
| `focusTotals` | range, words (optional) | `Thesis, this week: 6 h 40 m over 5 sessions; longest Tue 7 Oct, 2 h 05 m. By day: Mon 1 h 30 m, Tue 2 h 05 m, …` | `PeriodStats`, `SearchWords`, `DurationText` |
| `bestHours` | range | `Most focus 8–11 am (68%). Strongest days: Tue, Thu.` | `Rhythm`, `HourlyWork` |
| `findSessions` | words, range | Up to 10 lines: date, name, duration, first 80 characters of the note. | The History search behind `HistorySearchHit` |
| `appTime` | range, app (optional) | `Safari, this week: 3 h 12 m in front; used in 4 focus sessions.` Without an app: the top five apps by time. | `AppUsage`, `HistoryAppLens` (same per-session matching as History's app view) |

Every tool's output:

- is at most 1 KB, so several calls fit the on-device model's context;
- formats every duration and percentage in code, so the model copies text and never does arithmetic;
- says `No sessions match` (or the tool's equivalent) when there is nothing, never an empty string or a bare 0.

## 3. Flow

1. Opening the sheet calls `prewarm()` on the session.
2. On ↩, the question goes to the model with fixed instructions: answer only from tool output; copy durations and percentages exactly; if tools find nothing, say so; one to three sentences.
3. The model calls one or more tools, possibly chaining them (for example `findSessions` then `focusTotals` with the names it found). Tools read through `SessionStore` on the main actor.
4. The answer streams into the sheet. The "Used:" line lists the tools called and their ranges, read from the session transcript's tool-call entries.
5. Follow-ups continue the same session. "New question" replaces it.

While an answer is in progress the field is disabled and ↩ does nothing.

## 4. When it cannot answer

| Case | Shown |
|---|---|
| macOS 14–25 | "Ask needs macOS 26 or later." No field. |
| Apple Intelligence off | "Turn on Apple Intelligence in System Settings › Apple Intelligence & Siri." and a button that opens that pane. |
| Model not ready (downloading) | "The on-device model is still downloading. Try again shortly." |
| Context window exceeded | Starts a new session and shows "Started a new thread — the last one was full." |
| Guardrail violation | "Can't answer that one." |
| Any other generation error | One plain line; the previous answer stays. |

Availability-to-message and error-to-message are plain functions so the checks
can cover every case without a model.

## 5. Privacy

The README's "Private by construction" paragraph gains one sentence: Ask
Daybook answers with Apple's on-device model, and your question, history and
answers are not sent anywhere.

## 6. Checks

New suite `AskChecks`, appended at the end of `registeredTests`.

| Check | Fixture | Fails when |
|---|---|---|
| Totals per range | Archive built from `SelfTest.base` with the app's calendar | Any range total differs from the History figure for the same span |
| Range edges | Sessions either side of week and month starts; suite also run with `TZ=Europe/Berlin` | A session lands in the wrong range |
| Nothing found | Empty range; words with no match | Output is empty or a bare zero |
| Size cap | 2,000 sessions | Any tool output exceeds 1 KB |
| Tool wiring | Each tool's `call(arguments:)` invoked directly, no model | Tool output differs from `AskFacts` output |
| Read-only | Every tool run against a scratch store | Archive bytes or the isolated defaults suite change |
| Messages | Every availability case and error case | A case shows the wrong line or none |
| Sheet | `--gallery` / `--snapshot` entry with a fixed answer | Layout breaks at 80% and 140% zoom; VoiceOver labels missing |

Tool checks need macOS 26 at run time; CI's runner is `macos-26`. No check
calls the live model: its answers are not deterministic and the CI runner is
not expected to have Apple Intelligence on.

Mutation test before commit: shift the week boundary by one day in a temporary
tree copy; the range-edge check must fail.

## 7. Hand checks

Run on a Mac with Apple Intelligence on, before merge. Record each answer here.

| # | Question | Passes when |
|---|---|---|
| 1 | How long did I focus today? | Equals the dashboard's figure |
| 2 | When do I focus best? | Hours agree with Insights' rhythm chart |
| 3 | What did I note about *(a word from a real session)* last month? | Quotes a real note with its date |
| 4 | How much Safari time this week? | Equals History's app view for the week |
| 5 | What did I do on 31 Feb? | Says it found nothing; invents nothing |

## Out of scope

- Daily review note (project 2) and background tidying (project 3).
- Commands that change state (start, pause, rename). The model gets no write tools.
- Cloud models, API keys, saved threads, voice input.
