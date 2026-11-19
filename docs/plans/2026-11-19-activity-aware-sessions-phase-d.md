# Activity-Aware Sessions, Phase D Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An opt-in site signal: with the person's consent and the Accessibility grant, Daybook reads the address of the front tab in the browsers they confirmed, keeps only a site kind, and uses that kind to credit, label and deepen sessions, with remembered sites and an honest README.

**Architecture:** Core gains the site-kind table, the address-to-kind reduction, a `site` field on beat slices, the recorder rule for labelling a slice, and the credit, depth, label and fingerprint rules that read it. App gains the consent settings, the web-link app list, a read-only Accessibility reader on a serial worker with a timeout and a per-app circuit breaker, and the wiring from app activations and beat edges into the recorder. Surfaces gains a Site signal panel under Settings › Privacy with the consent sheet and the remembered-sites list. Everything below the reader is driven headlessly through fakes; the live path stays dormant until the owner's probe passes and `SignalGate.passing` gains its line.

**Tech Stack:** Swift 5 mode, SwiftUI and AppKit, ApplicationServices (`AXUIElement`), macOS 14, one module built by `build.sh`. No new dependency.

**Spec:** `docs/specs/2026-11-17-activity-aware-sessions-design.md`, binding. Phase D only: section 8 (site signal), the site-kind parts of sections 2, 3, 6 and 9, spikes 4 and 5. Phase A plan: `docs/plans/2026-11-17-activity-aware-sessions-phase-a.md`.

## Rulings

The spec leaves these open or says them in one line. Each was ruled while writing this plan, with its reason; the owner may overturn any.

| # | Ruling | Reason |
|---|---|---|
| R1 | "Site-only Accessibility first" means the reader reads one attribute, `AXURL` of the focused window's web area, and nothing else: no window title, no element below the web area, no address bar text. It never sets an attribute on another app (no `AXEnhancedUserInterface`, no `AXManualAccessibility`). | Privacy first. An address bar holds whatever is being typed (a search), and writing attributes changes how another app behaves. If the probe shows a browser exposes no `AXURL`, that browser gives no signal; an address-bar fallback needs its own review. |
| R2 | Sensitive sites (banking, health, government, sign-in, adult) are not `SiteKind` cases. They are a separate table marker that yields no signal, so no type exists that could write one to a beat. | A stored "health" or "adult" kind would itself be sensitive. The spec lists them only so they are never remembered; giving no signal is the strictest reading. |
| R3 | Kinds map to purposes: video, social, shopping are *leisure* and read like a browser whose active and passive purpose are both media; documentation is research, code host coding, mail and meeting communication, AI chat writing and AI, each read like an app with that fixed purpose. | Reuses `PurposeRule` (`.ambiguous`, `.fixed`) instead of a new rule set, so engaged, quiet-kept and passive fall out of the Phase A rules unchanged. |
| R4 | A purpose override the person set for a browser beats the site kind. | Anti-goal: nothing overrules what the person chose. |
| R5 | A held browser run is media, except when the holder's slices in the run carry mostly the meeting kind: then communication. | Spec: "a browser is always media, refined by site kind". Holding the screen on any other kind is still watching. |
| R6 | "Social, video and shopping are forced outside" applies to depth only. The working set and departures are unchanged. | The spec states it in the depth section; the phase strip already shows such time as a media phase through R3. Smallest change. |
| R7 | Reads happen at an app activation and at each beat edge, only while beats are being recorded and only when the front app is a confirmed browser. No `AXObserver`. | The spec's constraints allow flags "sampled at beat edges and app-activation events" on the existing ticker. A tab-change observer fires on every title update inside the page; a beat-edge read bounds a missed tab change to 30 s at one read per 30 s. |
| R8 | A read result carries the time it was requested. If the open slice is the same app and began at or after that time, the result labels the whole open slice; otherwise the open slice closes at the arrival second and a new slice of the same app with the result's kind opens. A result for another app, or after recording stopped, is dropped. A failed, timed-out, unknown or sensitive read sets the kind to none. A new beat's first slice of the same app carries the previous slice's kind until its read returns. | The read describes the tab from the moment it was asked; a stale result must never label another app. |
| R9 | Messaging timeout 0.5 s; two timeouts trip the app's breaker until beat recording ends (the session stops, or automatic mode's recording stops). | "For the rest of the session" in the spec; automatic-mode recording has no session, so recording's end is the boundary. |
| R10 | `SignalGate.passing` stays empty in this phase. With the gate off for the running macOS, the Site signal switch is disabled with "Not yet available on this version of macOS" and nothing is read, whatever is stored. There is no hidden override. | The spec's gate: a line lands only with its passing probe report. A back door would be a second, unreviewed gate. |
| R11 | Remembered sites are entered by the person in Settings (a site name and a kind). Nothing is learned automatically. Lookup walks from the full host to its parent domains; at each level a remembered entry wins over the built-in table, and a sensitive built-in entry anywhere in the chain gives no signal. Turning Remember sites off deletes the list. The list is left out of backups. | Daybook keeps no address, so "sites the person has corrected" can only be sites the person names. Deleting on off makes it revocable; leaving it out of backups keeps it on this Mac. |
| R12 | Turning the site signal off stops reads at once and drops any read in flight. Kinds already in beats stay and expire with the beats (90 days). Turning it on again always shows the consent sheet, preselecting the last confirmed apps. Consent is stored as a text version (1); a changed text asks again. | Consent is explicit each time; a kind is what the consent text says is kept. |
| R13 | Sensitive by rule: a host whose last label is `gov` or `mil`; a host whose second-to-last label is `gov`, `govt`, `gouv`, `gob`, `gv`, `go` or `mil` (`ato.gov.au`, `impots.gouv.fr`, `x.go.jp`); `gc.ca` and its subdomains; and a host with any label equal to `login`, `signin`, `sign-in`, `signup`, `auth`, `oauth`, `sso`, `account`, `accounts`, `myaccount`, `id`, `idp`, `passport`, `password`, `secure` or `banking`. | Covers government and sign-in pages the fixed table cannot list; widened after the plan review. Over-matching only loses a signal, never leaks one. |
| R14 | `ActivityConstants.algorithmVersion` becomes 2 (rules changed). The read timeout and breaker count live in `SiteSignalConstants`, outside `signature`: they change what is read, not how evidence is weighed. | Spec: any rule change bumps the version. Phase B may bump too; whichever merges second takes the next number. |
| R15 | The fingerprint's `siteKind` is the kind with the most credited seconds, ties by `SiteKind.allCases` order, else "none". | Spec: "plus the site kind or none"; one value per session. |
| R16 | "Mixed" now occurs when credit with and without site kind gives different leaders, exactly as the spec says. An engaged session on a video site reads media with the signal and research without it, so it is "Mixed". | Binding spec text; recorded so the owner sees the consequence before the gate opens. |
| R17 | The site path logs nothing: no address, no site name, no kind, no failure. | The spec forbids logging an address; logging nothing is simplest to prove. |
| R18 | The probe compiles the app's own reader and Core site files with a small `main.swift`, so the owner tests the code that ships. It runs from Terminal, so Terminal (not Daybook) needs the Accessibility grant during the probe. | Owner rule: no session launches a built Daybook; the probe must still test real code. |
| R19 | Settings shows the site signal's state and the three tier lines from spec section 9, with the model line saying only whether on-device AI is on. The shadow-mode line is Phase C. | Spec section 9: "Settings shows which signals are active". |
| R21 | (from the Task 6 review) While waiting for the Accessibility grant the switch shows on, with "Waiting for Accessibility permission" as its state; the spec's "shows as inactive" is carried by that text. One click turns it off and withdraws consent. With consent stored and the gate off, the switch can still be turned off, never on. Turn On in the consent sheet is not the Return default: consent is a deliberate click. | A switch drawn off could not be used to withdraw consent; consent must be revocable from every state. |
| R22 | (from the Task 6 review) Copy says sites Daybook *knows* as banking, health, government, sign-in or adult give no signal and are never kept, never that every such site is caught. Turning Remember sites off with sites in the list asks first. | The table and R13 rules cannot list every bank or clinic; the copy must not claim more. Deleting a list the person built is confirmed, as elsewhere in Settings. |
| R20 | Tasks run one after another in this tree, each running `./build.sh --check` itself, never two builds at once. | Owner rule for this Mac; the skill forbids parallel implementers. |

## Global Constraints

- `./build.sh --check` passes before each commit, sandbox disabled, one build at a time on the Mac (check `pgrep -f build.sh` first). The final gate also runs `TZ=Europe/Berlin` and `TZ=Pacific/Kiritimati`.
- Never `./build.sh --install`, `--test` or `--run`; never launch a built Daybook except with `--snapshot`; never request or grant Accessibility; never touch `~/Library/Application Support/Daybook` or the `com.prabesh.daybook` domain.
- Core is UI-free and compiles alone: the table, reduction, consent state, beat field, recorder and credit rules are Core. `AXUIElement`, `NSWorkspace` and `NSRunningApplication` are App, handed to Core as plain values.
- Privacy: the address is reduced to a site name and a kind inside one function on the worker and dropped there. It is never stored, logged, published, passed to the model or put in an error. Page titles and page content are never read. Only apps in the confirmed list are ever queried. Off by default.
- Consent text, verbatim: "Daybook reads the address of the front browser tab, keeps only what kind of site it is, and discards the address immediately. It never reads page titles or page content."
- No new timer and no polling: reads ride activations and beat edges (R7).
- Checks use `TestClock`, `SelfTest.scratchDirectory()` and `MemoryDefaults.suite(named: "fc-selftest-…")`; times are offsets from `SelfTest.base`; checks hold in any zone. Each new suite goes at the end of `registeredTests`.
- Source files at most 300 lines; `SettingsModel.swift`, `PersistenceStore.swift`, `SessionStore.swift`, `SessionStore+StoryDetails.swift` and `DayStory.swift` take no net growth: new code goes in new files.
- Lengths in App, Design and Surfaces are tokens or `N.zoomed`.
- Files Phase B also changes (`Beat.swift`, `BeatRecorder.swift`, `ActivityDerivation.swift`, `SessionMetadata*`, `SelfTest+Registry.swift`) get the smallest edit that works.
- Commit subjects: one plain present-tense sentence for any user of the app, no prefix, no internal terms. The repository is public: no personal data or real browsing in fixtures or reports. Australian English, no em or en dashes in docs.

## Review Focus

1. A beat line written by a newer build whose slice carries a site kind this build does not know: the beat still loads, that slice reads with no kind (Task 2 check 5).
2. A read result that arrives after the person switched apps, or after recording stopped: it never labels another app's slice (Task 2 check 4, Task 5 check 6).
3. A browser that hangs (a heavy web app): the main thread never waits; two timeouts stop reads of that app until recording ends (Task 4 checks 4 and 5).
4. Consent withdrawn mid-session (the switch turned off, or Accessibility removed in System Settings): no new read starts and a result in flight is dropped (Task 4 check 6).
5. Addresses that are not web pages or are odd: `file:`, `about:blank`, `chrome://`, `data:`, a bare search phrase, an IP address, `localhost`, upper case, a trailing dot, a port, user info in the URL: none or the right kind, and no path is ever examined (Task 1 check 2).

## Who runs what

| Work | Runner |
|---|---|
| Tasks 1, 7 | `sonnet-worker`, effort medium to high |
| Tasks 2, 5 | `sonnet-worker`, effort xhigh (persistence, session state) |
| Tasks 3, 4, 6 | general-purpose on Opus 5.5, effort high (credit rules; the security-sensitive reader; the consent design) |
| Build and check runs outside a task | `haiku-runner`, effort medium, run-and-report only |
| Per-task reviews of 1, 7 | spec-and-quality reviewer, Sonnet, effort high |
| Reviews of 2, 3, 5, and 4's settings | `fix-reviewer` (Opus) |
| Reviews of 4's reader, 6 | Opus reviewer, effort high; Task 6 also gets a design review |
| Task 8 | security review (Opus high, `security-and-hardening`, read-only), then whole-branch review (Opus high) |

## Router plan and safety gate

Skills, from the project router's apple-apps and design-ui hubs: `superpowers:test-driven-development` in every task; `bama:os-integrations` for Task 4's Accessibility reader and the permission flow; `bama:ux-design`, `bama:mac-design` and `bama:swift-swiftui` for Task 6; `bama:test-mac-app` for how each check is pitched (cheapest level first: Core checks, then `--selftest` with fakes); `superpowers:systematic-debugging` for any red check whose cause is unclear; `superpowers:verification-before-completion` before every completion claim. One departure: `os-integrations` suggests polling for the grant; Daybook re-reads trust on Settings appearing and on the app becoming active, with no timer (the spec's no-polling rule).

Safety gate for a native app, with the task that owns each item and Task 8's security review checking all of them:

| Gate item | Owner |
|---|---|
| Privacy text is exact: the README, the Settings disclosure and the consent sheet say what is read (the front tab's address, in confirmed browsers), what is kept (a site kind; site names only under Remember sites, only ones the person adds) and what is never kept or read (addresses, titles, page content, sensitive sites) | Tasks 6 and 7 |
| Only necessary data: one attribute read, reduced to a kind on the worker, nothing else stored, logged or published | Tasks 2 and 4 |
| Consent is explicit, off by default and revocable: nothing reads before Turn On; off stops reads and drops one in flight; Remember sites off deletes the list | Tasks 4, 5 and 6 |
| Permission is asked at use: the Accessibility prompt appears only after Turn On in the consent sheet | Task 6 |
| No unsupported claims: copy states only what the active tier can know; nothing claims the signal works before the probe passes (the gate-off text says so) | Tasks 6 and 7 |

---

### Task 1: Site kinds, the table and the address reduction (Core)

**Files:**
- Create: `Sources/Core/SiteKind.swift`, `Sources/Core/SiteKindTable.swift`, `Sources/Core/SiteAddress.swift`
- Test: `Sources/Verification/SiteKindChecks.swift`; register at the end of `registeredTests`

**Interfaces (produces):**

```swift
enum SiteKind: String, Codable, CaseIterable {
    case video, documentation, codeHost, social, shopping, mail, aiChat, meeting
    var displayName: String          // "Video", "Documentation", "Code host", "Social", "Shopping", "Mail", "AI chat", "Meeting"
    /// R3: leisure kinds read as .ambiguous(active: .media, passive: .media); the rest as .fixed(purpose).
    var rule: PurposeRule
    /// video, social, shopping.
    var isLeisure: Bool
}

enum SiteAddress {
    /// http or https only; the host, lowercased, without a trailing dot, a port, user info or a leading "www.".
    /// nil for anything else. Never reads the path, query or fragment.
    static func siteName(fromAddress address: String) -> String?
    /// A name the person typed for Remember sites: the same normalisation, accepting a bare host
    /// ("example.com") or a full address; nil unless it has at least two labels of letters, digits or hyphens.
    static func normalisedSiteName(_ typed: String) -> String?
}

enum SiteKindTable {
    /// R11 and R13: most specific level first; a sensitive entry anywhere in the chain gives nil.
    static func kind(forSite siteName: String, remembered: [String: SiteKind]) -> SiteKind?
    static func isSensitive(_ siteName: String) -> Bool
}
```

Built-in table (public, well-known hosts only): video `youtube.com youtu.be vimeo.com twitch.tv netflix.com primevideo.com disneyplus.com tv.apple.com max.com hulu.com dailymotion.com`; documentation `developer.apple.com developer.mozilla.org docs.python.org swift.org stackoverflow.com learn.microsoft.com readthedocs.io docs.github.com react.dev nodejs.org devdocs.io docs.rs pkg.go.dev wikipedia.org`; code host `github.com gitlab.com bitbucket.org codeberg.org sr.ht`; social `facebook.com instagram.com x.com twitter.com tiktok.com reddit.com linkedin.com threads.net bsky.app mastodon.social pinterest.com tumblr.com`; shopping `amazon.com amazon.com.au ebay.com ebay.com.au etsy.com aliexpress.com temu.com walmart.com target.com bestbuy.com`; mail `mail.google.com outlook.live.com outlook.office.com mail.yahoo.com mail.proton.me app.fastmail.com`; AI chat `chatgpt.com chat.openai.com claude.ai gemini.google.com perplexity.ai copilot.microsoft.com chat.deepseek.com grok.com poe.com`; meeting `meet.google.com zoom.us teams.microsoft.com teams.live.com whereby.com webex.com`. Sensitive: `paypal.com wise.com revolut.com stripe.com chase.com bankofamerica.com wellsfargo.com hsbc.com barclays.co.uk commbank.com.au anz.com.au westpac.com.au nab.com.au` (banking), `webmd.com mayoclinic.org nhs.uk healthdirect.gov.au healthengine.com.au mychart.org` (health), `my.gov.au` (government), `accounts.google.com login.microsoftonline.com login.live.com appleid.apple.com account.apple.com idmsa.apple.com okta.com my.1password.com vault.bitwarden.com lastpass.com` (sign-in), `pornhub.com xvideos.com xnxx.com xhamster.com onlyfans.com chaturbate.com` (adult), plus the R13 suffix and label rules.

- [ ] **Step 1: Write the failing checks** in `SiteKindChecks`:
  1. "Every kind reads as its purpose": `SiteKind.documentation.rule == .fixed(.research)`, `.codeHost` coding, `.mail` and `.meeting` communication, `.aiChat` writingAI; `.video.rule == .ambiguous(active: .media, passive: .media)` and the same for social and shopping; `isLeisure` true exactly for those three.
  2. "Only a web address gives a site name, and only its host": `https://www.YouTube.com./watch?v=x` gives `youtube.com`; `http://user:pw@docs.python.org:8080/3/` gives `docs.python.org`; nil for `file:///Users/x/a.pdf`, `about:blank`, `chrome://settings`, `data:text/html,hi`, `how to cook rice`, `""`; `https://192.168.1.1/` and `http://localhost:3000` give names that `kind(forSite:)` maps to nil.
  3. "A subdomain finds its site, the most specific entry first": `m.youtube.com` is video; `docs.github.com` is documentation while `gist.github.com` is code host; `example.com` is nil.
  4. "Sensitive sites give no kind, wherever they sit": nil for `accounts.google.com`, `eu.accounts.google.com`, `www.paypal.com`, `my.gov.au`, `ato.gov.au`, `irs.gov`, `impots.gouv.fr`, `x.gov.in`, `login.example.com`, `app.auth.example.com`, `sso.company.io`, `xvideos.com`; `isSensitive` true for each; `government.example.com` and `idea.com` are not sensitive.
  5. "A remembered site wins over the table but never over a sensitive one": remembered `["youtube.com": .documentation, "intranet.example.com": .documentation]` gives documentation for `youtube.com` and `wiki.intranet.example.com`; remembered `["paypal.com": .shopping]` still gives nil for `paypal.com`.
  6. "A typed site name is normalised or refused": `normalisedSiteName("  Example.COM ")` is `example.com`, `"https://www.example.com/a?b"` is `example.com`, nil for `"example"`, `"a b.com"`, `""`, `"file:///x"`.
- [ ] **Step 2:** Run `./build.sh --check`. Expected: these six fail (or the suite does not compile).
- [ ] **Step 3:** Implement the three files to the interfaces above. `siteName` uses `URLComponents(string:)`, checks `scheme` and reads only `host`.
- [ ] **Step 4:** Run `./build.sh --check`. Expected: all pass, exit 0.
- [ ] **Step 5:** Commit: "Daybook knows what kind of site a web address belongs to".

### Task 2: A site kind on each beat slice, and the recorder rule (Core)

**Files:**
- Modify: `Sources/Core/Beat.swift` (`BeatSlice`), `Sources/Core/BeatRecorder.swift`
- Test: `Sources/Verification/SiteBeatChecks.swift`; register at the end

**Interfaces:**
- Consumes: `SiteKind` (Task 1), `CounterReading`, `BeatRecorder` as it stands.
- Produces:

```swift
// BeatSlice gains, last, with a default so existing initialisers compile:
var site: SiteKind? = nil      // coding key "y"; written only when non-nil

extension BeatRecorder {
    /// R8. `app` is the bundle identifier the read was made for.
    mutating func site(_ kind: SiteKind?, app: String, requestedAt: Date, at: Date,
                       counters: CounterReading, idleSeconds: TimeInterval)
}
```

Rules: decoding reads `"y"` as an optional string and maps it through `SiteKind(rawValue:)`, so an unknown value gives nil instead of failing the line. `Beat.schemaVersion` stays 1 (an older build ignores the key). Adjacent slices merge only when app and site are equal. A folded flick takes its neighbour's site. A slice opened by an activation starts with no site; the first slice of a new beat carries the previous slice's site when the app is the same.

- [ ] **Step 1: Write the failing checks** in `SiteBeatChecks`, driving `BeatRecorder` from `Beat.gridStart(for: SelfTest.base)` with a `TestClock` as `BeatRecorderChecks` does:
  1. "A read labels the slice it was asked for": activate browser B at t0, `site(.video, app: B, requestedAt: t0, at: t0 + 1, …)`, 29 ticks; the closed beat has one slice B 30 s with site video.
  2. "A changed tab splits the slice where the answer came": B labelled video from t0, then at t0 + 12 a result `.documentation` requested at t0 + 11; slices B 12 s video and B 18 s documentation.
  3. "The next half-minute keeps the site until it is read again": after check 1's beat, the next beat's first slice of B carries video; a `nil` result requested at that edge relabels it to none.
  4. "A late answer never labels another app": B activated, then app A activated at t0 + 3, then a result for B arrives at t0 + 4; no slice of A carries a site, and B's 3 s slice has none.
  5. "A beat with an unknown site kind still loads": a line with a slice `"y":"hologram"` between two good beats reads back as three beats, that slice with site nil; a slice with no site writes no `"y"` key.
  6. "Two sites in one app stay two slices, and a flick takes its neighbour's site": B video 12 s, B documentation 3 s, B video 15 s gives one slice B 30 s video.
- [ ] **Step 2:** Run `./build.sh --check`. Expected: these fail.
- [ ] **Step 3:** Implement the field and `site(…)`.
- [ ] **Step 4:** Run `./build.sh --check`. Expected: all pass, and every existing `BeatRecorderChecks` and `BeatArchiveChecks` check still passes.
- [ ] **Step 5:** Run `fix-reviewer` on the diff (time arithmetic, persistence format). Address findings.
- [ ] **Step 6:** Commit: "Each half-minute can note what kind of site the browser showed".

### Task 3: Credit, depth, label and fingerprint read the site kind (Core)

**Files:**
- Modify: `Sources/Core/ActivityCredit.swift` (`Piece`, `purpose`, `isAmbiguous` use), `Sources/Core/ActivityCredit+Held.swift` (R5), `Sources/Core/ActivityDerivation.swift` (`depth`, `fingerprint`), `Sources/Core/ActivityConstants.swift` (version 2), `Sources/Core/SignalGate.swift` (`carried(by:)`)
- Modify: `Sources/Verification/BeatArchiveChecks.swift` (check 8's literal and version)
- Test: `Sources/Verification/SiteCreditChecks.swift`; register at the end; reuse `BeatTrace` (add an optional `site` to `BeatTrace.Step`, default nil)

**Interfaces:**
- Consumes: `BeatSlice.site` (Task 2), `SiteKind.rule`, `SiteKind.isLeisure` (Task 1).
- Produces:

```swift
extension SignalKind {
    /// [.siteKind] when any slice of any beat carries a site; else [].
    static func carried(by beats: [Beat]) -> Set<SignalKind>
}
// CreditedSlice gains, last: var site: SiteKind? = nil   (set only when input.signals contains .siteKind)
```

Rules: when `input.signals` contains `.siteKind`, a piece whose app is ambiguous and not overridden (R4) and whose slice has a site is credited with `site.rule` in place of the app's rule, through the same engaged, 3a and 3b paths (a `.fixed` site rule makes the piece quiet-kept, as for an editor). Without `.siteKind` in signals, sites are ignored entirely, which is the counterfactual `label` already runs. Held (R5): a held run whose holder is ambiguous is media, or communication when the holder's slices in the run carry `.meeting` for most of their seconds. Depth (R6): an engaged or quiet-kept slice whose `site?.isLeisure == true` is outside even on a member. Fingerprint (R15). `algorithmVersion = 2`; `signature` unchanged in shape.

- [ ] **Step 1: Write the failing checks** in `SiteCreditChecks` (traces from `SelfTest.base`, browser `com.google.Chrome`, editor `com.microsoft.VSCode`):
  1. "Reading documentation hands-off is research, not media": Chrome keys 2 min on documentation then no input 6 min on documentation, signals on: all 8 min research (quiet part quiet-kept); with signals empty the same beats give media after the grace.
  2. "Typing on a social site is not research": Chrome keys 10 min on social: media, engaged.
  3. "A meeting in the browser is communication": Chrome holder, no input 20 min, site meeting: held, communication; site video: held, media.
  4. "Social time is outside the work, so it is never deep": VS Code keys 20 min, Chrome keys 10 min social, VS Code keys 10 min; depth light. The same with documentation in place of social: deep.
  5. "When the site decides the label, it is Mixed": Chrome keys 10 min on video: label `.mixed` (media with, research without); Chrome keys 10 min on documentation: `.activity(.research)`.
  6. "A person's purpose for the browser beats the site": overrides `["com.google.Chrome": "coding"]`, Chrome keys 10 min on video: coding.
  7. "The fingerprint names the site kind with most time": 6 min documentation and 4 min video gives `siteKind == "documentation"`; no sites gives "none".
  8. "Signals are listed only when a beat carries a site": `SignalKind.carried(by:)` is `[]` for check 6's beats without sites, `[.siteKind]` with one.
- [ ] **Step 2:** Run `./build.sh --check`. Expected: these fail; every Phase A sweep still passes.
- [ ] **Step 3:** Implement. Bump `algorithmVersion` to 2 and update `BeatArchiveChecks` check 8 to `== 2` with the same literal.
- [ ] **Step 4:** Run `./build.sh --check`. Expected: all pass, Phase A sweeps unchanged.
- [ ] **Step 5:** Run `fix-reviewer` on the diff. Address findings.
- [ ] **Step 6:** Commit: "With the site signal on, a browser's time is credited by the kind of site it showed".

### Task 4: Consent, the app list, remembered sites and the reader (Core and App)

**Files:**
- Create: `Sources/Core/SiteSignalSettings.swift` (consent state, constants, known browsers, persistence over a `UserDefaults`), `Sources/App/SiteSignalReader.swift` (worker, gating, breaker), `Sources/App/AXSiteAddressReader.swift` (the real reader, read-only), `Sources/App/WebLinkApps.swift` (the system list)
- Modify: `Sources/Core/PersistenceStore.swift` (`removeAll` key list and `backupSnapshot` exclusion only; no net growth: move an equal number of lines out if needed)
- Test: `Sources/Verification/SiteSignalChecks.swift`; register at the end

**Interfaces (produces):**

```swift
enum SiteSignalConstants {
    static let consentVersion = 1
    static let consentText = "Daybook reads the address of the front browser tab, keeps only what kind of site it is, and discards the address immediately. It never reads page titles or page content."
    static let rememberDisclosure = "Daybook keeps the sites you give a kind, with that kind, on this Mac. Banking, health, government, sign-in and adult sites are never kept. Turning this off deletes the list."
    static let readTimeout: TimeInterval = 0.5
    static let timeoutsBeforeSkipping = 2
    /// Safari, Safari Technology Preview, Chrome, Chrome Canary, Chromium, Firefox, Firefox Developer Edition,
    /// Arc, Dia, Edge, Brave, Opera, Vivaldi, Orion, Zen (bundle identifiers).
    static let knownBrowsers: Set<String>
}

enum SiteSignalState: Equatable { case unavailable, off, awaitingPermission, on }

/// Stored under "fc.siteSignal.consent" (Int), ".apps" ([String]), ".remember" (Bool), ".sites" ([String: String]).
final class SiteSignalSettings {
    init(defaults: UserDefaults)
    var isConsented: Bool { get }                    // stored version == consentVersion
    var apps: [String] { get }
    var remembers: Bool { get }
    var rememberedSites: [String: SiteKind] { get }  // unknown kinds in storage are skipped
    func turnOn(apps: [String])                       // stores version and list
    func turnOff()                                    // clears the version; keeps the list for preselection
    func setRemembers(_ on: Bool)                     // off deletes ".sites"
    /// nil and nothing stored when the name is refused (invalid or sensitive) or remembering is off.
    @discardableResult func remember(_ typed: String, as kind: SiteKind) -> String?
    func forget(_ siteName: String)
    static func state(consented: Bool, gateOn: Bool, trusted: Bool) -> SiteSignalState
    /// Known browsers first, ticked; every other candidate unticked; Daybook itself left out.
    static func candidates(_ apps: [(bundleID: String, name: String)]) -> [(bundleID: String, name: String, ticked: Bool)]
}

enum SiteAddressRead: Equatable { case address(String), failed, timedOut }
protocol SiteAddressReading { func read(pid: pid_t, timeout: TimeInterval) -> SiteAddressRead }

struct SiteReading: Equatable { let kind: SiteKind?; let app: String; let requestedAt: Date }

final class SiteSignalReader {
    init(settings: SiteSignalSettings, reader: SiteAddressReading,
         gateOn: @escaping () -> Bool, trusted: @escaping () -> Bool,
         bundleID: @escaping (pid_t) -> String?,
         run: @escaping (@escaping () -> Void) -> Void,      // the worker: a serial queue in the app, inline in checks
         deliver: @escaping (@escaping () -> Void) -> Void,  // back to the main thread in the app, inline in checks
         onReading: @escaping (SiteReading) -> Void)
    /// Called on the main thread; returns at once. Reads nothing unless gate, consent, trust and the
    /// confirmed list all allow `app`, and its breaker is not tripped. A newer request replaces a pending one.
    func request(app: String, pid: pid_t, at: Date)
    /// Recording ended: breakers reset, pending and in-flight results are dropped.
    func reset()
}
```

The address is reduced inside one private function on the worker (`SiteAddress.siteName` then `SiteKindTable.kind`), and only `SiteReading` leaves it. The worker checks `bundleID(pid) == app` before reading. A result is delivered only if, on the main thread at delivery, gate, consent and trust still allow it, the app is still in the confirmed list, and no `reset()` happened since the request (a generation counter). `AXSiteAddressReader`: `AXUIElementCreateApplication(pid)`, `AXUIElementSetMessagingTimeout`, `kAXFocusedWindowAttribute`, then a breadth-first walk of `kAXChildrenAttribute` for role `AXWebArea`, at most 400 elements and depth 12, never descending into a web area, reading only its `AXURL`; `kAXErrorCannotComplete` is `.timedOut`; it sets no attribute and logs nothing. `WebLinkApps.current()` uses `NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://example.com")!)`.

- [ ] **Step 1: Write the failing checks** in `SiteSignalChecks` (`MemoryDefaults.suite(named: "fc-selftest-site-…")`, a fake reader that records every pid it was asked about, inline `run` and `deliver`):
  1. "Off by default, and consent is explicit": a fresh suite is not consented and does not remember; `state(consented: false, gateOn: true, trusted: true) == .off`; `(true, false, true) == .unavailable`; `(true, true, false) == .awaitingPermission`; `(true, true, true) == .on`.
  2. "Nothing is read unless every gate allows it": with each of gate off, not consented, not trusted, app not in the list, and `bundleID(pid)` naming another app, `request` leaves the fake reader's log empty and delivers nothing.
  3. "A read gives only a kind": the fake returns `.address("https://www.youtube.com/watch?v=x")`; one `SiteReading(kind: .video, …)` is delivered; for `.failed`, `.address("about:blank")`, `.address("https://example.com")` and `.address("https://accounts.google.com/x")` the kind is nil.
  4. "A browser that hangs is skipped after two timeouts": two `.timedOut` reads, then a third request reads nothing; after `reset()` it reads again.
  5. "A slow read never holds up the caller": with `run` deferring work to a list, `request` returns before any read and delivers nothing until the list runs.
  6. "Turning the signal off drops a read in flight": request with deferred `run`, then `turnOff()`, then run the list: nothing delivered; the same with `reset()`, with `trusted()` turning false, and with the app removed from the list, each in place of `turnOff()`.
  6a. "Only the newest request is read": with deferred `run`, three requests before the list runs make one read, for the last.
  6b. "A changed consent text asks again": a suite holding consent version 0 is not consented.
  7. "Remember sites keeps only what the person names, and forgets on off": with remembering off, `remember("example.com", as: .documentation)` stores nothing; on, it stores `example.com`; `remember("paypal.com", …)` and `remember("not a site", …)` return nil; a remembered kind wins in a read; `setRemembers(false)` leaves `rememberedSites` empty; `backupSnapshot` contains no `fc.siteSignal.sites` key.
  8. "The app list ticks known browsers only": candidates for Safari, a text editor and Daybook give Safari ticked, the editor unticked, no Daybook.
- [ ] **Step 2:** Run `./build.sh --check`. Expected: these fail.
- [ ] **Step 3:** Implement the four files and the `PersistenceStore` key additions.
- [ ] **Step 4:** Run `./build.sh --check`. Expected: all pass.
- [ ] **Step 5:** Run `fix-reviewer` on the settings persistence; an Opus reviewer on the reader (concurrency, privacy). Address findings.
- [ ] **Step 6:** Commit: "Daybook can read which kind of site the front browser tab shows, only with consent".

### Task 5: Wiring reads into beats (App)

**Files:**
- Create: `Sources/App/SessionStore+SiteSignal.swift`
- Modify: `Sources/App/ActivityEvidence.swift` (one stored `siteReader: SiteSignalReader?`, nil until the app builds one), `Sources/App/SessionStore+ActivityEvidence.swift` (three one-line calls), `Sources/App/SessionStore+SessionActivity.swift` (the two `signals: []` become `SignalKind.carried(by: beats)`), the place the app builds `SessionStore`'s `ActivityEvidence` (find it with CodeGraph: who calls `ActivityEvidence.init`; construct the real reader with a `.utility` serial queue, `AXIsProcessTrusted`, `SignalGate.isOn(.siteKind, macOSMajor:)`, `NSRunningApplication`)
- Test: `Sources/Verification/SiteSignalWiringChecks.swift`; register at the end

**Interfaces:**
- Consumes: Tasks 2 to 4.
- Produces: `extension SessionStore { func requestSiteRead(app: String?, at: Date); func noteSiteReading(_ reading: SiteReading, at: Date) }`.

Rules: `noteBeatActivation` requests a read for the new app; `recordBeatTick` requests one on every tick that closed a beat while a confirmed browser is in front (whether or not the app changed: an answer the recorder dropped near an edge is then asked again within one beat); `endBeatRecording` calls `siteReader?.reset()`. `noteSiteReading` passes the reading to `recorder.site(…)` only while `recordsBeats` and recording. Requests happen only while recording (R7). The pid comes from the activation's running application; a missing pid reads nothing.

- [ ] **Step 1: Write the failing checks** with a store built for checks (as `ActivityEvidenceStoreChecks` builds one), a fake reader and inline queues:
  1. "A browser activated during a session gets its site kind": consented, Chrome listed, activation of Chrome, 30 ticks; the archived beat's Chrome slice carries the fake's kind.
  2. "Each half-minute asks again while the browser stays in front": 90 ticks in Chrome make exactly 4 reads (one activation, three beat edges).
  3. "Nothing is read when nothing is being recorded": with no session and automatic sessions off, an activation makes no read.
  4. "An editor is never asked": an activation of VS Code, not listed, makes no read.
  5. "A session's snapshot lists the site signal only when its beats carry one": the derived shape's `signals` is `[.siteKind]` after check 1 and `[]` with the signal off.
  6. "Stopping the session drops a late answer": deferred `run`, request, stop the session, run the list; no beat written after the stop carries a site.
- [ ] **Step 2:** Run `./build.sh --check`. Expected: these fail.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `./build.sh --check`. Expected: all pass.
- [ ] **Step 5:** Run `fix-reviewer` (session state, beats). Address findings.
- [ ] **Step 6:** Commit: "Sessions note the kind of site in the front browser tab when the site signal is on".

### Task 6: The Site signal panel and consent sheet (Surfaces)

**Files:**
- Create: `Sources/App/SettingsModel+SiteSignal.swift`, `Sources/Surfaces/Settings/SettingsGroups+SiteSignal.swift`, `Sources/Surfaces/Settings/SiteSignalConsentSheet.swift`
- Modify: `Sources/Surfaces/Settings/SettingsGroups+Data.swift` (one line placing the panel after Privacy), `SettingsPrivacyDisclosure` text (one sentence on the site signal)
- Test: `Sources/Verification/SiteSignalSurfaceChecks.swift`; register at the end; a still in the existing Settings snapshot set if one covers Privacy

**Interfaces:** Consumes `SiteSignalSettings`, `SiteSignalState`, `SiteSignalConstants`, `WebLinkApps`, `SiteKindTable`, `SiteAddress`.

Panel "Site signal", in order: a switch "Read the kind of site in the front browser tab" whose detail is the state ("Off", "On", "Waiting for Accessibility permission", "Not yet available on this version of macOS"); turning it on opens the sheet, turning it off calls `turnOff()` at once. While awaiting permission, a button "Open Accessibility Settings" opens `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`. When on: "Change Apps…" reopens the list. A switch "Remember sites" with `rememberDisclosure` as its detail. With remembering on: the list (site name, kind, a Remove button with an accessibility label naming the site), and an add row (text field "Site, such as example.com", kind picker, Add), which shows "Daybook does not keep this site" when `remember` returns nil. Last, "What Daybook can see now": three lines from spec section 9, each marked on or off for this Mac. The sheet: title "Turn on the site signal", the consent text verbatim, the candidate list as toggles with app names, Cancel (default for Escape) and Turn On (disabled with no app ticked); Turn On calls `turnOn(apps:)` and, if not trusted, `AXIsProcessTrustedWithOptions` with the prompt option. Trust is re-read on appear and on `NSApplication.didBecomeActiveNotification`; no timer.

- [ ] **Step 1: Write the failing checks**: the model's state text for each `SiteSignalState`; Turn On with no ticked app is disabled; the sheet's body contains `SiteSignalConstants.consentText` exactly; with the gate off the switch is disabled and nothing is stored when toggled.
- [ ] **Step 2:** Run `./build.sh --check`. Expected: these fail.
- [ ] **Step 3:** Implement; every length a token or `.zoomed`; every control has an accessibility label.
- [ ] **Step 4:** Run `./build.sh --check`. Expected: all pass. Render the Settings still with `--snapshot` and look at it.
- [ ] **Step 5:** Spec-and-quality review plus a design review (layout, VoiceOver, contrast, copy). Address findings.
- [ ] **Step 6:** Commit: "Settings has an opt-in site signal with a consent sheet and remembered sites".

### Task 7: README, the probe and the owner's steps

**Files:**
- Modify: `README.md` (Privacy section and the beats paragraph near line 421)
- Create: `scripts/site-signal-probe/main.swift`, `docs/debug/2026-11-19-site-signal-probe-steps.md`

README, the "No special access" bullet becomes: "**No special access unless you turn on the site signal.** Daybook asks for no Accessibility, Automation, Screen Recording or Input Monitoring permission; it tells when you are away from system counters, not from what you type. The one exception is the site signal in Settings › Privacy, off by default. If you turn it on, Daybook asks for Accessibility to read the address of the front tab in the browsers you choose, keeps only what kind of site it is (video, documentation, social and so on) and discards the address immediately. It never reads page titles or page content and never queries any other app. Banking, health, government, sign-in and adult sites give no signal. Site names are kept only if you turn on Remember sites, and only the ones you add. Turning the signal off stops it at once. The prompts you may see are …" (the rest unchanged). The first bullet's "never what is in it" gains ", with the one exception described under the site signal below". The beats paragraph adds "and, with the site signal on, the kind of site in the front browser tab (never its address)".

The probe compiles `Sources/Core/SiteKind.swift`, `SiteKindTable.swift`, `SiteAddress.swift`, `SiteSignalSettings.swift` (and whatever Core files those need), `Sources/App/AXSiteAddressReader.swift`, `Sources/App/WebLinkApps.swift` and `main.swift`. It prints the web-link apps (spike 5), then every 2 s for 120 s reads the front app if it is a known browser and prints `browser, result (kind | none | failed | timedOut), latency ms`; `--show-site` also prints the site name, for the owner's eyes only. At the end: per browser, reads, successes, p50 and p95 latency, the longest read, and whether two consecutive timeouts occurred.

The steps document gives the exact build command, granting Terminal Accessibility and removing it afterwards, the pages to open per browser (YouTube video, developer.apple.com, github.com, a heavy web app such as a large spreadsheet, a background tab, a private window), the pass criteria (each test page's kind right in at least 19 of 20 reads per browser; p95 under 250 ms; no read longer than 600 ms; a hung browser stops being read after two timeouts), the report template (`docs/debug/<date>-site-signal-probe.md`, kinds and timings only, no other sites), and what lands in the same commit if it passes: the report, `SignalGate.passing = [.siteKind: [<major>]]`, and `BeatArchiveChecks` check 7 changed to expect the gate on for that major. That commit gets a scoped security re-review before it merges, since it is the one that turns the live path on.

- [ ] **Step 1:** Write the README change, the probe and the steps.
- [ ] **Step 2:** Compile the probe with `swiftc -typecheck` (sandbox allowed) to prove it builds; do not run it.
- [ ] **Step 3:** Run `./build.sh --check`. Expected: all pass (README is not compiled; this proves nothing else moved).
- [ ] **Step 4:** Commit: "The README explains the opt-in site signal and what it keeps".

### Task 8: Security review, whole-branch review, three zones, draft pull request

- [ ] **Step 1:** Security review of the whole signal path (Tasks 1 to 7) by a read-only Opus reviewer using `security-and-hardening`: what is read, where the address lives and dies, gating and races, the AX calls, storage and backups, logs, the probe. Fix every Critical and Important finding as its own round with a check that fails on the old behaviour; scoped re-review after each round, five rounds at most.
- [ ] **Step 2:** Whole-branch review against the spec and this plan. Same fix loop.
- [ ] **Step 3:** `./build.sh --check`, then `TZ=Europe/Berlin ./build.sh --check`, then `TZ=Pacific/Kiritimati ./build.sh --check`, one at a time. Expected: all pass in each.
- [ ] **Step 4:** Push the branch and open a draft pull request. Never merge, never release.
