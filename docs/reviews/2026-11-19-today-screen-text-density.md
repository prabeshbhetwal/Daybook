# Today screen: is it too text-heavy?

Date: 19 November 2026. Subject: the Today screen (the day story and the right-hand rail).

Question: would a non-technical person find it overwhelming, given that it carries far more words than visual cues? The owner likes the screen, every area does its job, and the text is wanted.

Method:
- A panel of five models (GPT, Gemini, DeepSeek and two Nemotron models; Grok was off) reviewed the screen's exact content in two rounds. Round 1 was independent. Round 2 put the checked facts and the round 1 clusters to them for keep, modify or drop.
- A MiroFish audience simulation (`mirofish-review`) with a mandatory stress test of its top recommendation.
- The app's own snapshot of the Today screen (default state, dark, comfortable zoom), plus the owner's screenshot of a busy day.

## Verdict

Partly. By default the screen is **not** a wall of text. It reads as text-heavy for three specific reasons:

1. **Every timeline card has the same visual weight and no symbol.** A session, a break, an idle gap, an unrecorded gap, a Daybook update and a rename confirmation all look alike, so the only way to tell them apart is to read them. Coloured dots alone were called "decoration" by the simulated audience.
2. **Two different totals sit side by side without labels.** The headline counts session time (10h 51m in the screenshot). The goal ring counts only focus while an app was in use (6h 28m). Both are right; nothing next to either says so, and the explanation is behind a small (i) that people reportedly skip.
3. **A few lines are technical or repeated.** "Plugged in · 94 W · 80% → 80%", a "Coding" chip beside a card already titled "Coding", "App use outside a session", "stretches", and "not counted as focus" repeated on the break card.

One correction to the premise: in the owner's screenshot "How this day was measured" was open because Expand All had been pressed. The snapshot confirms that by default it is closed, so the headline, the one-line facts and the cards are what a person sees first. Three of five models changed their verdict to "overstated" once told this; two still called the screen dense.

The fix is therefore cues and labels, not removing text. No area should go, and no change below deletes a meaning.

## Highest-value changes

| # | Change | Why it helps | Cost | Risk to "text is wanted" |
|---|---|---|---|---|
| 1 | **Say what each total counts.** Under or beside the headline, a short label ("session time"); on the ring, "focus with an app in use". Add one plain line to the ring's (i) explaining why they differ. | Removes the most-cited confusion (22 of 69 simulated items). Panel: all five ranked it first or second. | S | Low. Adds a few words, explains existing ones. |
| 2 | **A leading SF Symbol per card kind** (focus session, break, idle, not recorded, app use outside a session), and slimmer, lighter one-line rows for "Daybook updated" and the correction record "Session renamed" (keep its Undo). | Lets the timeline be scanned by shape instead of read. Panel: all five; simulated users asked for "small icons per card type". | M | Low. Labels and durations stay. Do not merge "No input" and "Not recorded": they mean different things (idle versus not recording). |
| 3 | **Trim the repeated and technical lines.** Hide the activity chip when it repeats the card title; "App use outside a session" becomes "Outside a session"; the break card drops ", not counted as focus" from its face (the break styling and the measured block already say it; keep it in the card's detail or hover). | Fewer words said twice. Panel: four of five. | S | Low to medium. The break note moves, it is not deleted. |
| 4 | **Power line: plug glyph and percentage on the card; watts and "80% → 80%" in the card's detail.** | Watts are power-user data; non-technical readers want charge state. Panel: four of five (one wanted it kept). | S | Low. Detail stays one click away. |
| 5 | **Fix two small legibility gaps**: a key for the hatched bars in Time of day (in its (i)), and shorten the toolbar subtitle that currently truncates ("Coding · 9h 33m on this activity today · 2 stretches since 11:14…"). | The hatching is unexplained; the subtitle cuts off mid-word. Panel: all five. | S | Low. |

Close sixth, not in the top five: give the rail a clearer order, with Today's goals and On this Mac louder and Top apps, Time of day and Focus streak quieter (lighter headings and spacing, same content). Four of five agreed; it is worth doing once changes 1 to 5 are seen on screen.

## Keep as is

- The headline sentence with the blue number, and the date line above it.
- "How this day was measured" closed by default, with all four rules intact.
- The vertical timeline's chronology and coloured dots (they work once symbols join them).
- The goal ring with its tick, the Top apps rows with icons and bars, the On this Mac stacked bar, the 3-hour Time of day chart, the Focus streak check row.
- Undo on corrections and on the break row.
- The folded "outside sessions · not recorded · stretches" line.
- The (i) pattern for long explanations. Keep it, but do not rely on it for anything a person needs in order to read a number correctly (that is change 1).

## Focus streak line

The panel split on "Today counts. Keep it going tomorrow.": two would cut or shorten it, one would move it into detail, two would keep it. It is a tone choice, not a density fix. Left as is; shorten only if the rail still feels crowded after the changes above.

## What the models said

| Item | GPT | Gemini | DeepSeek | Nemotron Ultra | Nemotron Super |
|---|---|---|---|---|---|
| 1 Label the two totals | Keep | Keep | Keep | Keep | Keep |
| 2 Symbols per card, slim meta rows | Modify (keep Undo) | Keep | Keep | Keep | Keep |
| 3 Shorter labels | Modify (break note to detail) | Modify (note to hover) | Modify | Keep | Keep |
| 4 Power line | Modify | Keep | Modify | Modify | Keep |
| 5 Hatch key, toolbar subtitle | Keep | Keep | Keep | Keep | Keep |
| Rail hierarchy | Keep | Keep | Modify | Keep | Keep |
| Streak line | Modify | Keep line | Shorten | Cut | Shorten |
| "Too text-heavy" after learning the measured block starts closed | Overstated | Overstated | Still dense | Overstated | Still dense |

Round 1 suggestions rejected on checking: emoji labels (the app uses SF Symbols), merging "No input" with "Not recorded" (different causes), and calling "Session renamed" a stale toast (it is a deliberate correction record).

## Crowd view (MiroFish)

| Field | Content |
|---|---|
| Question | Which of three versions would a non-technical Mac user prefer: keep as is, label and cue, or a simple glance view with the rest behind a button? |
| Top recommendation | Label and cue (ranked first, then keep as is, then glance view). Simulation `sim_553c7b8b54b3`. |
| Survived checks | Evidence: 19 of 58 hand-coded posts backed it, 13 of them from the two audience voices (who also gave 8 to a hybrid of labels plus a glance default and 1 to the glance view); no post backed keeping the screen as is. Platform split: Twitter and Reddit agree on direction. Against the plan: consistent with the owner's "text stays, detail may move" rule. Dissent: recorded below. Robustness: not run. |
| Verdict | Adopt with changes |
| Confidence | Low |
| Real-world test | Show the current screen and the changed one to five non-technical Mac users and ask what each big number means. |

Weaknesses to discount: only 11 simulated people, eight of them rival apps; the agents had the seed text, so the evidence is partly circular; the generated report admits it had no direct user reactions (the posts are the evidence, not the report).

Strongest dissent: label and cue is "still a spreadsheet at first glance" and "labels clarify; they don't simplify". The opposing view is that the glance version "looks like it has something to hide" and buries the honesty that makes Daybook worth trusting. That is why the glance version is not recommended; a simpler first impression, if ever wanted, is a separate decision and would be its own design.

Themes from the simulation: the two totals confuse (22 items); dots are read as decoration and people want icons (18); jargon such as "stretches", "recorded" and "No input" (17); (i) tooltips get ignored (12); density (14).

## Follow-ups, each its own change if approved

- Changes 1, 3 and 5 are copy and small view edits with check updates.
- Change 2 needs a design pass for the symbols and the slim row style, in light and dark at 80% and 160% zoom.
- Change 4 touches the power line's display only, not what is recorded.
- Wording to review with real people: "stretches" and "recorded".

Not done: no code was changed, no second simulation was run, and no real-user test.
