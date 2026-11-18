# Design review: origin mark, contradiction line, correction suggestion

Date: 19 November 2026. Reviewed from `docs/screenshots/2026-11-19-origin-mark/storyOrigin-compact-light.png` and `-dark.png` (Phase B, Task 4 at ca936b4).

Verdict: ships as built.

- The mark is quiet: caption size, supporting ink, a symbol plus words, right-aligned under the duration. It reads after the name, category and time, which is the right order. Never the only carrier: the words say it, and VoiceOver reads the whole sentence.
- Two facts on one row join with a middle dot ("Started by you · Carried on after you were away (your answer)"). Long, but it fits the compact width without truncation in the fixture.
- In the report each fact stacks under the figures, then the contradiction line ("Mostly media: 37 of 60 minutes") in the same quiet style: a fact, not a warning, as the spec asks.
- The correction suggestion sits above the report header with a single text button ("Use Learning"). Acceptable: it is the one action in the report and is dismissible by ignoring it.

Accepted minors (not blocking): "media" rather than "video" until the site signal (Phase D) can tell them apart; a rule with a long name will truncate on narrow rows (the tooltip and accessibility label keep the full sentence).
