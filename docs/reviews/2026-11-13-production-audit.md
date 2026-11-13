# Production audit, 13 November 2026

Audit of HEAD `dabd00a` by six read-only lanes (Core probes, App layer, two UI
lanes, accessibility and copy, performance). Each finding carries a ruling:
ACCEPT (fix now), DEFER (real, not in this pass) or REJECT (with the reason).
Paths are under `Sources/`. Line numbers are from `dabd00a`; a fixer must find
the code by its text and skip a finding whose code no longer matches.

The design language in DESIGN.md does not change. Fixes use existing tokens and
components only.

## C. Core (each reproduced by a probe)

- C1 P0 ACCEPT. `Core/DecisionHistory.swift:66,72-77`, `Core/SessionEngine+Sessions.swift:34-62`. An unreadable or newer-version `correction-history.json` sets `error`, which makes `requiresTerminalCheckpoint` true, so every ending (`stop`, reset, long-away end, break end) fails, and a relaunch fails the same way. Probe: `stop()=false state=running records=0`, relaunch identical. Fix: in `DecisionHistory.init` set an unreadable file aside with `UnreadableFile.setAside(url, prefix: "correction-history-corrupt-", ...)` and start from an empty document, as the other archives do; keep `error` only if the move fails. For a newer-version file, leave the file alone, stay read-only for corrections, and keep `error` out of `requiresTerminalCheckpoint` so plain endings use the `archive.edit` path. Check: write `{` and separately `{"version":2}`, start, advance 1 h, assert `stop() == true` and 1 record.
- C2 P1 ACCEPT. `Core/SessionEngine+Absence.swift:196`. `if away >= breakThreshold, away >= store.longAwayCap` ties the long-away cap to the ask threshold, so with "Ask me after: Never" a 10 h sleep does not end the session (record spans 21:00 to 08:30). Fix: judge the cap on its own. Check: `breakThreshold = FocusConstants.never`, run 1 h, sleep 10 h, unlock, assert `.idle` and a 1 h record.
- C3 P1 ACCEPT WITH LIMIT. `Core/SessionEngine+Elapsed.swift:132-138`, `Core/SessionEngine+Sessions.swift:17-18`. Clock set back past the session start: `interval(from:)` clamps to 0, elapsed is under `minimumRecordedSession`, no record is written, `stop()` returns true. Probe: `stop()=true records=0`. Fix must not change a persisted format unless old files still load and an older build still loads the new file; if that cannot be met, do not fix, and report why.
- C4 P2 ACCEPT. `Core/BreakLog.swift:242-246`. Retention cutoff is counted from the saving moment, so one save with the clock 401 days ahead erases the log. Fix: count the cutoff from `min(moment, newest entry already in the log)`. Check: 5 prompts, `noteRhythm` 401 days ahead, reload, assert 5 prompts.
- C5 P2 ACCEPT. `Core/SessionArchive.swift:231-248`. One malformed record sets the whole `sessions.json` aside and nothing reads it again. Fix: decode record by record, keep the readable ones, and set the original aside so nothing is lost. Check: 50 records, one bad id, assert 49 visible after load and after relaunch, and the set-aside copy exists.
- C6 DEFER. A journal line from a newer build goes to `app-usage-journal-corrupt-*.jsonl`, which `recoverSetAsideFiles` never reads. Read from code only.
- C7 DEFER. `DataBackup.pruneAutomatic` reads folder stamps in local time. Read from code only.

## A. App layer

- A1 P1 ACCEPT. `App/SessionStore+Refresh.swift:80-90` (`ticks`). With app-use recording off the tracker is `.stopped`, so the ticker stops when a session pauses for idle or watching, `observeIdle()` never runs, and the session never resumes on input in the same app. Fix: keep ticking while `engine.state` is `.paused(reason: .idle)` or `.paused(reason: .watching)`. Check: recording off, pause by `.idleObserved`, `store.refresh()`, assert the ticker is scheduled.
- A2 P1 ACCEPT. `App/AppCoordinator.swift:762-773`. Unsaved note drafts (`SessionStore.sessionNoteDrafts`) are dropped on quit. Fix: save every draft in `applicationWillTerminate` before `engine.persist()`.
- A3 P2 ACCEPT. `App/AppCoordinator.swift:437-440`. A hot-key press whose save fails shows nothing when the window is closed, and `.stoppedPendingFinalisation` plays the success haptic. Fix: show the HUD with `store.correctionError` for `.saveFailed`; no success haptic for either.
- A4 P2 ACCEPT. `App/AppCoordinator.swift:305-317,325-332`. `startAutomatically` returns nothing and `engine.stop(endingAt:)`'s Bool is discarded, so the HUD can say "session started" when it did not, and a failed automatic end credits the learner and resets the detector. Fix: return a Bool from `startAutomatically`; act on both results.
- A5 DEFER. A read-only app-use archive is reported only in Settings, Privacy. Needs a new notice surface.
- A6 DEFER. Backup failures are visible only in Settings, Privacy. Same surface as A5.
- A7 P2 ACCEPT. `App/SessionStore+Metadata.swift:27-33`. `pendingPowerObservations` grows without bound while the metadata archive is read-only, and the whole array is rewritten to preferences each time. Fix: cap the queue at 200, dropping the oldest.
- A8 P2 ACCEPT. `App/AskModel+Answer.swift:51-54,111-119`. A stream that ends with no text marks the turn `.answered` with an empty answer and no retry. Fix: end with the existing cannot-answer failure when the answer is empty.
- A9 P2 ACCEPT. `App/NameSuggester.swift:182-204`. A timeout or transient model error is cached as "nothing to suggest". Fix: do not cache on timeout or when `NoteWriter.repeats(error)` is false.
- A10 DEFER. `SettingsModel.defaultAppTab` is stored and never read.

## U. UI, main surfaces (`Surfaces/Main, Today, Story, Dashboard, Popover, Focus`)

- U1 ACCEPT. `Main/StoryChromeBar.swift:185-188,201-204`. History link pads `Space.s`, Go to Date pads `Space.m`. Use `Space.s` on both. Leave the ink alone.
- U2 ACCEPT. `Today/DayStory.swift:204-207`. The quiet-run row uses `chevron.down` rotated 180; every other disclosure uses `chevron.right` rotated 90. Match the others.
- U3 ACCEPT. `Main/StoryChromeBar.swift:235-250`. On History the capsule says "Start Focus" but opens the session controls. Title it "Start Focus…" (the Mac convention for an action that needs more input) and keep the behaviour.
- U4 ACCEPT. `Focus/FocusHero.swift:906-935` and `Story/StoryColumns.swift:268-286` both render `store.correctionError`. Show one: `StoryCorrectionNotice` shows nothing while the hero underline is showing the failure.
- U5 ACCEPT. `Today/DayStory.swift:1005-1010`, `Story/SessionNoteEditor.swift:122-140`. Save Name/Done and Save/Cancel are default bordered with mixed fonts beside `StoryActionStyle` buttons. Primary gets `StoryActionStyle`, secondary gets `StoryLinkStyle`. Remove the name field's "Done" (the checkmark and Return already finish), and keep the pencil and checkmark glyphs at one size.
- U6 ACCEPT. `Today/DayStory.swift:960-987`. Category chips in an `HStack` cannot wrap. Use `ChipFlow`.
- U7 ACCEPT. Text actions drawn as muted text: `Focus/FocusHero.swift:748-757` (Undo), `Today/DayStory.swift:939-946` (note Edit), `Story/StoryRail.swift:186-194` (Reset Order), `Story/StoryRail.swift:620-631` (Awards, a hand copy of the link style). Use `StoryLinkStyle`. `Popover/PopoverFooter.swift:27-34`: `StoryPressStyle(hovers: true)`, and title "Updates" as "Check for Updates…".
- U8 ACCEPT. Close buttons have three looks: `Main/MainWindowView.swift:336-345`, `Design/Components/Components.swift:238-247` (the reference), `Story/StoryAppDetail.swift:89-97`. Extract the `PanelHeader` close as one `CloseButton` and use it in all three.
- U9 ACCEPT. Truncated text with no tooltip: `Focus/FocusHero.swift:384-390`, `Focus/FocusBreakViews.swift:98-101,127-130`, `Story/StoryAppDetail.swift:34`. Add `.help` with the full text.
- U10 ACCEPT. The question card has two renderings: `Today/DayStory.swift:1066-1072` and `Story/StoryDecisionRow.swift:60-63`. One shared modifier with `StoryStyle.entryInsets(for: density)`, `entryRadius`, continuous corners.
- U11 ACCEPT. Story row cards: add `style: .continuous` at `Story/StoryGapCard.swift:46`, `Story/StoryMachineRunCard.swift:24`, `Today/DayMachineEvents.swift:28`, `Story/StoryAppDetail.swift:193`, `Story/StoryDecisionRow.swift:125`; `StoryDecisionRow` uses `entryInsets(for: density)`.
- U12 ACCEPT ONLY WHERE DESIGN.md IS EXPLICIT. `Story/SessionReportView.swift:356-361`, `Today/DayStory.swift:849-854`: section titles set in `caption`. Apply the role DESIGN.md names for that element; if DESIGN.md does not name it, leave it.
- U13 ACCEPT. `Dashboard/DayPickerCalendar.swift:90-98`. "Today" is a hand-built capsule in `caption`. Use `StoryActionStyle(tint: StoryStyle.action)` or the link style, whichever the neighbouring controls use.
- U14 ACCEPT. `Design/Components/Motion.swift:83` `symbolEffect(.bounce...)` in `symbolNod`. The project removed bounce. Make the nod a pass-through or delete it and its two call sites.
- U15 ACCEPT. One action, two names: hero "Away" (`Focus/FocusHero.swift:419,557`) against menu "Step Away" (`Main/SessionCommands.swift:89`, `Settings/SettingsGroups+Keyboard.swift:97`). Ruling: "Step Away" everywhere, and in `docs/usage.md`.
- U16 ACCEPT. `Story/PeriodNote.swift:54,68,89`. A failed note says "Try again" with nothing to press. Add a "Try Again" link.
- U17 ACCEPT. `Main/StoryChromeBar.swift:131-134`. Help "Back to Story", label "Return to Story". Both become "Back to Story (⌘1)".
- U18 ACCEPT. `Story/StoryBreakRow.swift:206,229-230`. `Menu("Change How This Counts")` as text. Use an `ellipsis.circle` menu with `.help("Change How This Counts")` and the same accessibility label, 28 pt frame.
- U19 ACCEPT. Goal wording: `Focus/FocusHero.swift:182,187` "1h 5m / 4h", `:809-810` "1h 5m of 4h", different rounding in `goalPaceLine`. One builder.
- U20 ACCEPT. `Today/DayStory.swift:884-886`. `Button("Remove", role: .destructive, ...)`.

## V. UI, secondary surfaces (`Surfaces/History, Insights, Settings, Onboarding, Ask, Awards, AwayPrompt, Review`, `Design/Components`)

- V1 ACCEPT. `Settings/SettingsSidebar.swift:276`, `Settings/CategoriesView.swift:263`. Selected row is `StoryStyle.well` on `rail`, about 1.05:1. Use `Tokens.Colour.focus.opacity(0.12)` and semibold on the selected title, as History rows do.
- V2 ACCEPT. `Settings/SettingsGroups+Breaks.swift:21-32`. The sound switch sits mid-row. Make it a `preferenceRow` whose accessory holds Play and the switch.
- V3 ACCEPT. `Settings/CategoriesView.swift:370,468` are checkboxes; `Settings/ActivityRulesView.swift:236,377` are `.small` switches. All become `.toggleStyle(.switch)` at `Tokens.Zoom.controlSize(.mini)`.
- V4 ACCEPT. `History/HistoryTreeRow.swift:162-177`. Expandable rows have no chevron. Add the same `chevron.right` the period and session cards use, when the row is not empty.
- V5 ACCEPT. `Review/HistoryFind.swift:84,168-177`. A typed query shows the field's clear button and a "Clear" link. Show the link only when a filter other than the query is active.
- V6 ACCEPT. `Settings/ActivityRulesView.swift:233,371`. Two switches for `isEnabled`. Show the form switch only for a new rule.
- V7 ACCEPT. `History/HistoryPathBar.swift:51-65`. Crumbs can overflow. Wrap in a horizontal `ScrollView` without indicators, anchored trailing.
- V8 ACCEPT. `Design/Components/AwayAnswers.swift:47-55,260-290`: answer cards have no hover or pressed state; add `hoverHighlight`. `AwayPrompt/AwayFullPrompt.swift:33-41`: "Later" uses `StoryLinkStyle`.
- V9 ACCEPT. `AwayPrompt/AwayQuickPanel.swift:30-57`. No Escape and no close. Add `.onExitCommand` that dismisses.
- V10 ACCEPT. `Settings/SettingsGroups+Agents.swift:31-34`: "Copied" never resets; reset after 2 s and use `IconButton` with `doc.on.doc` / `checkmark` and help "Copy Setup Message". `Ask/AskChatView.swift:133`: "Send" becomes the `arrow.up` icon button the away reason field uses, help "Send (Return)". `Ask/AskNewChatButton.swift:11`: `square.and.pencil` icon button, help "New Chat".
- V11 ACCEPT. Text boxes disagree on focus state: extract the halo and border from `Review/HistoryFind.swift:103-108` into one modifier and apply it to `Settings/SettingsView.swift:96-114`, `Design/Components/AwayAnswers.swift:177-218`, `Design/Components/ActivityChooser.swift:88-100`, `Ask/AskChatView.swift:161-164`. Settings search gets a clear button.
- V12 ACCEPT. Hand-built icon buttons where `IconButton` (`Design/Components/Cards.swift:65`) exists: `Insights/InsightSection.swift:64-78`, `Settings/ActivityRulesView.swift:550`, and the `ellipsis.circle` menu at `Settings/ActivityRulesView.swift:238-248` (28 pt frame, `.help("More Actions")`).
- V13 ACCEPT. No tooltips: `Settings/CategoriesView.swift:497-510,641-657`, `Review/HistoryFind.swift:84`. Add `.help`.
- V14 PART. `History/HistorySessionCard.swift:143-150`: legends in an `HStack` truncate; use `ChipFlow`. Unifying bar heights and swatches: DEFER.
- V15 ACCEPT. Field labels: `Settings/ActivityRulesView.swift:348,437,475,543` match `Settings/CategoriesView.swift:452` (`body` + `supportingInk`).
- V16 REJECT. Native `DisclosureGroup` in Awards and Privacy is a correct Mac control.
- V18 ACCEPT. `Settings/ActivityRulesView.swift:554-596`. No empty state for a search with no match. Use the existing `EmptyState`.
- V19 ACCEPT WHERE A TOKEN OF THE SAME VALUE EXISTS. Literal radii at `Settings/SettingsSidebar.swift:267`, `Settings/ActivityRulesView.swift:282,461,499`, `Settings/CategoryEditorPanel.swift:204`, `History/HistoryPeriodRows.swift:13` (add `.continuous`). Do not change a rendered radius.
- V20 ACCEPT. `Settings/UpdateCountdownPanel.swift:124` prints "in 1 seconds". `Design/Components/GoalRing.swift:29` strokes with `Color.accentColor`; use `Tokens.Colour.focus` as line 40's tint does.

## X. Accessibility

- X1 ACCEPT. `History/HistoryDayChart.swift:92-111`. Bars are tap-only inside an ignored element. Keep the summary and expose each day with data as an accessibility child button.
- X2 ACCEPT. `Dashboard/DashboardCharts.swift:33-39`. Hour bars use `onTapGesture`. Make them plain-style buttons, disabled without a handler; the "click to open" tooltip only with a handler.
- X3 ACCEPT. `Surfaces/RewardHUD.swift:67,217-226`, `Surfaces/BreakHUD.swift:107,197-198`. Compact durations are spoken as metres. Pass labels and announcements through `DurationText.spoken(in:)`.
- X4 ACCEPT. `History/HistoryTreeRow.swift:181`, `History/HistoryPeriodCard.swift:66`. Keyboard focus is a 12% tint only. Add the focus-ring stroke `Settings/SettingsSidebar.swift:277-282` uses.
- X5 ACCEPT. `Settings/ActivityRulesView.swift:339-343`. Warning text in `Tokens.Colour.attention` is 2.2:1. Use `StoryStyle.attentionInk`.
- X6 ACCEPT. `Dashboard/DayPickerCalendar.swift:293`. Drop "selected date"/"not selected" (the trait says it) and add "today" for today.
- X7 ACCEPT. `Story/StoryDecisionRow.swift:84-123`. Announce the saved decision once when the success row appears.
- X8 ACCEPT. `AwayPrompt/AwayQuickPanel.swift:213-220`. 60 s under VoiceOver, 20 s otherwise.
- X9 ACCEPT. `Focus/ActivityEditorPanel.swift:242-246`. Focus the name field on appear; Escape closes.
- X10 ACCEPT. Action-blue text on its own tint is under 4.5:1 on some surfaces: `Dashboard/DayPickerCalendar.swift:90-97`, `History/HistoryPeriodCard.swift:41`, `Focus/FocusContinuations.swift:184-188`. Use `StoryStyle.ink(.blue)` for the text.
- X11 PART. Increase Contrast: strengthen the hairline token under `colorSchemeContrast == .increased` only if it can be done in the token. `History/HistoryDayChart.swift:83-84`: give "Outside sessions" the `HatchFill` from `Today/GapTrack.swift:136` so it is not told by opacity alone. Otherwise DEFER.
- X12 ACCEPT. Same as V13, plus `.help("More Actions")` at `Settings/ActivityRulesView.swift:238-248`.
- X13 ACCEPT. `Settings/SettingsGroups+Keyboard.swift:48-50`. Label "Turn Off", hint "Turns the global shortcut off".
- X14 ACCEPT. `Surfaces/RewardHUD.swift:65`: add the escape accessibility action. Scrims at `AwayPrompt/AwayFullPrompt.swift:24`, `Story/SessionReportView.swift:118`: hide from accessibility.

## W. Copy

- W1 REJECT. The away prompt's "It Was a Break / I Was Working / I Was Away" answer a question; the Story rows' "Call It a Break / Count as Focus / Leave Uncounted" are commands. Each fits its context.
- W2 ACCEPT. Buttons say "Stop"; settings say "End session after". Settings become "Stop session after" and "Stop a paused automatic session after" (`Settings/SettingsGroups.swift:171-172,232-233`, keywords at `Settings/SettingsSidebar.swift:160,173`). "End Break" stays.
- W3 See U15.
- W4 ACCEPT. Panel titles in Title Case matching their openers: `Focus/ActivityEditorPanel.swift:36` "Pin Activity", "Pinned Activities"; `Settings/CategoryEditorPanel.swift:71-72` "New Category", "Edit Categories"; the menu item at `Design/Components/Components.swift:144` becomes "New Category…".
- W5 ACCEPT. Action tooltips in Title Case: `Dashboard/DayPickerCalendar.swift:99,101`, `Settings/ActivityRulesView.swift:551`, `Ask/AskChatView.swift:131`, `Story/StoryAppDetail.swift:96`, `Settings/CategoriesView.swift:579`, `Focus/FocusBreakViews.swift:59`. `Design/Components/AwayAnswers.swift:199` "Save Reason (Return)". `Main/StoryChromeBar.swift:207` "Go to Date (⌘J)".
- W6 ACCEPT. Error text runs `localizedDescription` into the next sentence: `Core/SessionMetadataArchive.swift:267`, `Core/AmbientPowerLog.swift:83`, `Core/BreakLog.swift:260`, `Core/DecisionHistory.swift:76,162`, `Settings/SettingsGroups.swift:108`. One helper that ends the description with a full stop; then "X couldn't be saved. <description> Check free space and folder access, then try again."
- W7 ACCEPT. `App/SettingsModel.swift:144-153,211`, `Core/SessionArchive.swift:253`: say "session history", not `sessions.json`, and point to Reveal Data Folder in Settings, Privacy.
- W8 ACCEPT. "Power readings" everywhere the user reads it: `Core/SessionMetadataArchive.swift:134,167,170,172`, `Today/DayStory.swift:923,928`.
- W9 ACCEPT. "couldn't" and "can't" throughout user-facing errors.
- W10 ACCEPT. Next steps: `App/SpeechDictation.swift:145`, `App/AskModel+Notices.swift:25,72`.
- W11 PART. `Design/DesignTokens.swift:150` speech form mixes "hours" and "min": fix. Converting about 80 hand plurals to inflection: REJECT, the app is English only and the plurals are correct.
- W12 ACCEPT. `Core/AskFacts.swift:229-239`, `Core/NoteFacts.swift:78-80`: hand-written am/pm. Use the project's clock-time formatter so a 24-hour Mac reads 24-hour times.
- W13 ACCEPT. Two hand ordinals (`Settings/SettingsGroups+Breaks.swift:138`, `History/HistoryAppSessionTile.swift:51-64`). One ordinal formatter.
- W14 REJECT. The timer's `%02d:%02d:%02d` is correct for an English-only app.
- W15 ACCEPT. `Core/AskFacts.swift:74` "By work type:" becomes "By category:".

## P. Performance and redundancy (reasoned from code, not profiled)

- P1 ACCEPT. `App/SessionStore+Refresh.swift:162,168,189`. With no session the store still publishes `elapsed` (it grows while idle), `longestToday` and `trackedToday` every second; the last two have no production reader. Publish 0 for `elapsed` while idle and remove the two unread publishes with their producers, updating the checks that read them.
- P2 DEFER. One whole-store `ObservableObject` at 1 Hz (105 published properties, 46 observing views). Open item 4.1 of `docs/debug/2026-09-30-perf-check.md`; a large change.
- P3 DEFER. Today's day projection is never cached (`App/StoryDayProjection.swift:89`).
- P4 ACCEPT IF PROVEN UNREAD. `App/SessionStore+Review.swift:289`. The review live tail recomputes every second while History shows, and only the date range of `reviewDays` is read (`App/SessionStore+Story.swift:244`).
- P5 ACCEPT. `App/SessionStore.swift:513-523`. Every power notification empties all cached day projections; power readings belong to today, which is never cached. Do not clear the cache there.
- P6 ACCEPT. `App/SessionStore+History.swift:113` `rebuildGlance` builds outputs nothing reads (`glanceApps`, `glanceInsights`, `glanceTimeline`, `glanceBrackets`, `glanceLayout`). Remove them; compute `threadsToday` where `runningThreadUses` needs it.
- P7 ACCEPT. Write-only read models on `SessionStore`: `weekBars`, `previousSession`, `focusBrackets`, `runningApps`, `earlierToday`, `sparks`, `sessionsForSelectedDay`, `longestForSelectedDay`, `longestNameForSelectedDay`, `sessionAppRanks`, `sessionTracked`, `periodDays`, `periodLog`, `periodDayTotals`, `reviewQuality`, `reviewIntegrityNote`, `summarySentences`. Remove each only after confirming no reader outside `Sources/Verification`, with its producer.
- P8 DEFER. `refreshTypical` has no cache key.
- P9 ACCEPT. `App/EditCommands.swift:33`, `Main/SessionCommands.swift:58` hop to main on every `objectWillChange` without coalescing; use the flag `MenuBarLabelModel` uses.
- P10, P11 DEFER. `nettop` cadence; minimised window keeps rendering. Not probed.
- P12 PART. `App/AppCoordinator.swift:534,601`: `usage.sessions.isEmpty` copies the array to test emptiness; add a cheap emptiness test. Rest DEFER.
- R1 ACCEPT. Files referenced only by self-checks or by nothing: `Surfaces/Main/NativeStoryScopeControl.swift`, `Core/StoryHeatmap.swift`, `Surfaces/Dashboard/TimelineGapEvidence.swift`, `Surfaces/Focus/FocusSurfaceLayout.swift`, `Surfaces/Today/TodayInspector.swift`. Move each, with the checks that exist only for it, to `_trash/2026-11-13-dead-code/` (never delete), after confirming no production reference.
- R2 ACCEPT. Zero-reference declarations: `AppSwatch` (`Design/Components/Cards.swift:34`), `HistoryStripAxis` (`Surfaces/Review/HistoryDayList.swift:70`), `Tokens.Motion.slide`, `historyDeepestOpen`, `historyArchiveFacts` and its cache, `gridPeak`, `visibleHours`, `BreakLog.heldSeconds`, `holdReasons`, `DayStoryContext.underCard`. Remove after a reference check.
- R3 DEFER. Review period model used only by self-checks; day-stepping, formatter, rounding and clamp duplicates.

## Outcome of fix batch 1 (13 November, 17:40)

- C3 REVERTED, now DEFER. The fix moved the engine to a shifted clock while App passed wall-clock moments to `stop(endingAt:)` and `endBreak(at:)`, producing zero-length records claiming the full work, and the in-memory offset was lost on relaunch. A safe fix needs the offset persisted in the snapshot and every wall moment translated at the engine boundary.
- C4 REVERTED, now DEFER. Anchoring retention on the newest earlier day blocked legitimate pruning after a long real gap (checks 1247 and 1248 failed) and still erased the log after two wrong-clock days.
- C1, C2, C5 kept after independent review. C5 follow-up (crash window between set-aside and write-back; the Recovery note in Settings) is in batch 2.
