# Purpose, Threads and Continue — Implementation Plan

**Goal:** Continue a focus session started earlier the same day as a linked segment of one thread, with the apps used alongside it surfaced as side apps, driven by a new app-purpose axis resolved partly by measured input behaviour.

**Architecture:** Three new `Core` types — `AppPurpose`/`PurposeMap` (what an app is for), `InputDensity` (whether the person is producing or consuming), and `ThreadStats` (grouping session records by `threadID` and deriving each thread's primary and side apps from the usage archive). `SessionRecord` gains a `threadID`; continuing starts a new record sharing it. One new `App`-layer sampler feeds `InputDensity` on a 20-second timer. The popover gains a **Continue today** section.

**Tech Stack:** Swift 5, SwiftUI, `swiftc` via `build.sh`. No SPM, no Xcode, no third-party packages.

## Global Constraints

- Build with `./build.sh`; test with `./build.sh --test`. Warnings are errors.
- `Sources/Core/` never imports SwiftUI or AppKit. `CoreGraphics` and `Foundation` only.
- No new TCC permission: no Accessibility, Automation, Screen Recording or Input Monitoring. A feature that needs one is dropped, not the promise.
- No `@State` and no `@Observable` — this machine has Command Line Tools without Xcode, so the SDK ships no `SwiftUIMacros` plugin. View state is `ObservableObject` + `@Published`, consumed via `@StateObject`/`@ObservedObject`/`@EnvironmentObject`.
- Files stay under 500 lines.
- Never delete a file; move unwanted files to `_trash/` preserving the filename.
- Not a git repository — every "Commit" step is recorded and skipped.
- All tests are headless, in `Sources/SelfTest.swift`, against an injected clock and scratch directories.
- New tunable numbers go in `FocusConstants`, never inline in a classifier or view.

## File Structure

| File | Responsibility |
|---|---|
| `Sources/Core/AppPurpose.swift` **(create)** | `AppPurpose`, `PurposeRule`, `PurposeMap`. Static map plus behaviour-resolved ambiguous apps. |
| `Sources/Core/InputDensity.swift` **(create)** | `InputCounters` (injectable CGEventSource reader), `InputSample`, `InputActivity`, `InputDensity` (bounded ring + classifier). |
| `Sources/Core/SessionThread.swift` **(create)** | `ThreadSummary`, `ThreadApps`, `RunningThread`, `ThreadStats`. |
| `Sources/Core/SessionState.swift` **(modify)** | `threadID` on `SessionRecord` with legacy decode; `threadID` on `PersistedState`; new `FocusConstants`. |
| `Sources/Core/SessionEngine.swift` **(modify)** | `activeThreadID`; `start(workType:intent:threadID:)`; carry the thread into the archived record and the persisted snapshot. |
| `Sources/Core/PersistenceStore.swift` **(modify)** | `purposeOverrides` dictionary. |
| `Sources/App/InputSampler.swift` **(create)** | 20-second timer feeding `InputDensity`; suspends on lock and sleep. |
| `Sources/App/SessionStore.swift` **(modify)** | `threadsToday`, `threadApps(_:)`, `continueThread(_:)`, `currentActivity`. |
| `Sources/App/AppCoordinator.swift` **(modify)** | Own the sampler; wire suspend/resume to the existing lock and sleep hooks. |
| `Sources/Surfaces/ContinueTodaySection.swift` **(create)** | The popover section and its row. |
| `Sources/Surfaces/PopoverView.swift` **(modify)** | Insert the section. |
| `Sources/SelfTest.swift` **(modify)** | Tests 43–50. |
| `README.md` **(modify)** | Purposes, threads, side apps, and an honest polling claim. |

---

> **Build order:** Task 1 uses `InputActivity`, which Task 2 defines. Build
> **Task 2 first**, then Task 1, then 3–7 in order. The tasks are numbered by
> concept, not by dependency.

### Task 1: AppPurpose and PurposeMap

**Files:**
- Create: `Sources/Core/AppPurpose.swift`
- Modify: `Sources/Core/PersistenceStore.swift`
- Test: `Sources/SelfTest.swift`

**Interfaces:**
- Consumes: `PersistenceStore` (existing), `InputActivity` (Task 2 — declare it in Task 2 and build Task 2 first if executing out of order; this task's tests pass `InputActivity` values in directly).
- Produces: `AppPurpose`, `PurposeRule`, `PurposeMap.purpose(for:activity:overrides:)`, `AppPurpose.isFocused`, `PersistenceStore.purposeOverrides`.

- [x] **Step 1: Write the failing tests**

Add to `Sources/SelfTest.swift`, and register them in the `tests` array at line 46 as entries 43 and 44:

```swift
("App purpose: static map, ambiguity, overrides", testAppPurpose),
("App purpose: focused set and session kind", testSessionKind),
```

```swift
    // MARK: - 43

    private static func testAppPurpose() -> [String] {
        var problems: [String] = []

        expect(PurposeMap.purpose(for: "com.apple.dt.Xcode", activity: .active) == .coding,
               "Xcode is coding", &problems)
        expect(PurposeMap.purpose(for: "com.apple.dt.Xcode", activity: .passive) == .coding,
               "a fixed purpose ignores activity", &problems)
        expect(PurposeMap.purpose(for: "com.anthropic.claudefordesktop", activity: .passive)
               == .writingAI, "Claude is writing/AI", &problems)
        expect(PurposeMap.purpose(for: "com.figma.Desktop", activity: .active) == .design,
               "Figma is design", &problems)
        expect(PurposeMap.purpose(for: "com.netflix.Netflix", activity: .active) == .media,
               "Netflix is media even while typing", &problems)

        // Unmapped falls to utility, not to a guess.
        expect(PurposeMap.purpose(for: "com.example.unknown", activity: .active) == .utility,
               "an unmapped bundle is a utility", &problems)
        expect(PurposeMap.purpose(for: nil, activity: .active) == .utility,
               "no bundle is a utility", &problems)

        // Ambiguous apps are decided by behaviour.
        expect(PurposeMap.purpose(for: "com.google.Chrome", activity: .active) == .research,
               "Chrome with input is research", &problems)
        expect(PurposeMap.purpose(for: "com.google.Chrome", activity: .passive) == .media,
               "Chrome without input is media", &problems)
        expect(PurposeMap.purpose(for: "com.google.Chrome", activity: .absent) == .media,
               "an absent user is not doing research", &problems)
        expect(PurposeMap.purpose(for: "company.thebrowser.dia", activity: .active) == .writingAI,
               "Dia with input is writing/AI", &problems)

        // A user override wins over both the map and the behaviour.
        let overrides = ["com.google.Chrome": AppPurpose.coding.rawValue]
        expect(PurposeMap.purpose(for: "com.google.Chrome", activity: .passive,
                                  overrides: overrides) == .coding,
               "an override beats the ambiguity rule", &problems)
        expect(PurposeMap.purpose(for: "com.example.unknown", activity: .passive,
                                  overrides: ["com.example.unknown": "media"]) == .media,
               "an override maps an unknown app", &problems)
        expect(PurposeMap.purpose(for: "com.google.Chrome", activity: .active,
                                  overrides: ["com.google.Chrome": "nonsense"]) == .research,
               "a corrupt override falls back to the rule", &problems)

        return problems
    }

    // MARK: - 44

    private static func testSessionKind() -> [String] {
        var problems: [String] = []

        expect(AppPurpose.coding.isFocused, "coding is focused work", &problems)
        expect(AppPurpose.writingAI.isFocused, "writing/AI is focused work", &problems)
        expect(AppPurpose.design.isFocused, "design is focused work", &problems)
        expect(!AppPurpose.research.isFocused,
               "research supports focus but is not focus on its own", &problems)
        expect(!AppPurpose.communication.isFocused, "communication is not focus", &problems)
        expect(!AppPurpose.media.isFocused, "media is not focus", &problems)
        expect(!AppPurpose.utility.isFocused, "a utility is not focus", &problems)

        // Every purpose has a distinct label and a symbol, or the UI cannot draw it.
        var labels = Set<String>()
        var symbols = Set<String>()
        for purpose in AppPurpose.allCases {
            labels.insert(purpose.displayName)
            symbols.insert(purpose.symbolName)
            expect(!purpose.displayName.isEmpty, "\(purpose) has a label", &problems)
        }
        expect(labels.count == AppPurpose.allCases.count,
               "labels are distinct, got \(labels.count)", &problems)
        expect(symbols.count == AppPurpose.allCases.count,
               "symbols are distinct, got \(symbols.count)", &problems)

        return problems
    }
```

- [x] **Step 2: Run the tests and watch them fail**

Run: `./build.sh --test`
Expected: compilation fails with `cannot find 'PurposeMap' in scope`.

- [x] **Step 3: Create `Sources/Core/AppPurpose.swift`**

```swift
import Foundation

/// What an app is *for*. The third and last classification axis, deliberately
/// separate from the two that already exist:
///
/// - `AppCategory` answers "should this app pause my session?"
/// - `WorkType` answers "what did the user say this session was?"
/// - `AppPurpose` answers "what is this tool?"
///
/// Collapsing any pair breaks something: Terminal and Figma are both
/// `.work`, but one is coding and the other design.
enum AppPurpose: String, Codable, CaseIterable {
    case coding, writingAI, design, communication, research, media, utility

    var displayName: String {
        switch self {
        case .coding: return "Coding"
        case .writingAI: return "Writing & AI"
        case .design: return "Design"
        case .communication: return "Communication"
        case .research: return "Research"
        case .media: return "Media"
        case .utility: return "Utility"
        }
    }

    var symbolName: String {
        switch self {
        case .coding: return "chevron.left.forwardslash.chevron.right"
        case .writingAI: return "sparkles"
        case .design: return "paintbrush.pointed.fill"
        case .communication: return "bubble.left.and.bubble.right.fill"
        case .research: return "magnifyingglass"
        case .media: return "play.rectangle.fill"
        case .utility: return "wrench.and.screwdriver.fill"
        }
    }

    /// Purposes that constitute focused work. `research` is excluded on purpose:
    /// it supports deep work but a day of only reading is not a day of making.
    var isFocused: Bool {
        switch self {
        case .coding, .writingAI, .design: return true
        case .communication, .research, .media, .utility: return false
        }
    }
}

/// How an app's purpose is decided.
enum PurposeRule: Equatable {
    /// Always this, whatever the user is doing.
    case fixed(AppPurpose)
    /// Decided by behaviour. Browsers and AI clients carry no fixed purpose, and
    /// without an Accessibility grant the app can never read the URL or window
    /// title to find out — so it reads input instead.
    case ambiguous(active: AppPurpose, passive: AppPurpose)
}

enum PurposeMap {

    /// Code-constant. Only bundle identifiers that are known-good go here;
    /// guessing an identifier would silently misfile an app forever.
    static let rules: [String: PurposeRule] = [
        // Coding
        "com.apple.dt.Xcode": .fixed(.coding),
        "com.microsoft.VSCode": .fixed(.coding),
        "com.microsoft.VSCodeInsiders": .fixed(.coding),
        "com.todesktop.230313mzl4w4u92": .fixed(.coding),   // Cursor
        "com.jetbrains.WebStorm": .fixed(.coding),
        "com.apple.Terminal": .fixed(.coding),
        "com.googlecode.iterm2": .fixed(.coding),
        "com.docker.docker": .fixed(.coding),
        "com.tinyapp.TablePlus": .fixed(.coding),
        "com.postmanlabs.mac": .fixed(.coding),
        "com.github.GitHubClient": .fixed(.coding),

        // Writing and AI
        "com.anthropic.claudefordesktop": .fixed(.writingAI),
        "com.google.GeminiMacOS": .fixed(.writingAI),
        "com.openai.chat": .fixed(.writingAI),
        "notion.id": .fixed(.writingAI),
        "com.apple.Notes": .fixed(.writingAI),

        // Design
        "com.figma.Desktop": .fixed(.design),
        "com.bohemiancoding.sketch3": .fixed(.design),
        "com.adobe.Photoshop": .fixed(.design),

        // Communication
        "us.zoom.xos": .fixed(.communication),
        "com.microsoft.teams2": .fixed(.communication),
        "com.tinyspeck.slackmacgap": .fixed(.communication),
        "com.apple.iChat": .fixed(.communication),
        "com.apple.mail": .fixed(.communication),

        // Media
        "com.netflix.Netflix": .fixed(.media),
        "com.apple.TV": .fixed(.media),
        "com.apple.Music": .fixed(.media),
        "com.spotify.client": .fixed(.media),
        "org.videolan.vlc": .fixed(.media),
        "com.valvesoftware.steam": .fixed(.media),
        "com.hnc.Discord": .fixed(.media),

        // Utility
        "com.apple.finder": .fixed(.utility),
        "com.apple.systemsettings": .fixed(.utility),
        "com.apple.systempreferences": .fixed(.utility),

        // Ambiguous — the whole reason `InputDensity` exists.
        "com.google.Chrome": .ambiguous(active: .research, passive: .media),
        "com.apple.Safari": .ambiguous(active: .research, passive: .media),
        "org.mozilla.firefox": .ambiguous(active: .research, passive: .media),
        "company.thebrowser.Browser": .ambiguous(active: .research, passive: .media),
        "company.thebrowser.dia": .ambiguous(active: .writingAI, passive: .media)
    ]

    /// Precedence: user override → rule → `.utility`. An unmapped app is far
    /// more often a utility than anything else, and a name that describes the
    /// common case reads better in the UI than one describing a lookup failure.
    static func purpose(for bundleID: String?,
                        activity: InputActivity,
                        overrides: [String: String] = [:]) -> AppPurpose {
        guard let bundleID, !bundleID.isEmpty else { return .utility }
        if let raw = overrides[bundleID], let override = AppPurpose(rawValue: raw) {
            return override
        }
        switch rules[bundleID] {
        case .fixed(let purpose):
            return purpose
        case .ambiguous(let active, let passive):
            // An absent user is not doing research.
            return activity == .active ? active : passive
        case nil:
            return .utility
        }
    }
}
```

- [x] **Step 4: Add `purposeOverrides` to `Sources/Core/PersistenceStore.swift`**

Add the key beside `overrides` at line 10:

```swift
        static let purposeOverrides = "fc.purposeOverrides"
```

Add the accessor beside `overrides` (which starts at line 58):

```swift
    /// Bundle ID → `AppPurpose.rawValue`. Separate from `overrides`, which is
    /// the auto-pause category: one answers "what is this app", the other
    /// "should it pause me", and a single dictionary could not express both.
    var purposeOverrides: [String: String] {
        get { defaults.dictionary(forKey: Key.purposeOverrides) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: Key.purposeOverrides) }
    }
```

Add `Key.purposeOverrides` to the array in `removeAll()` at line 149 so the gallery's `prefs.removeAll()` clears it:

```swift
                    Key.menuSessions, Key.menuApps, Key.trackingDisabled,
                    Key.purposeOverrides,
```

- [x] **Step 5: Run the tests**

Run: `./build.sh --test`
Expected: `44/44 passed`.

- [x] **Step 6: Commit** *(skipped — not a git repository)*

---

### Task 2: InputDensity

**Files:**
- Create: `Sources/Core/InputDensity.swift`
- Modify: `Sources/Core/SessionState.swift` (`FocusConstants`)
- Test: `Sources/SelfTest.swift`

**Interfaces:**
- Consumes: `AppUsageTracker.idleCutoff` (existing, `180`).
- Produces: `InputActivity`, `InputSample`, `InputCounters`, `InputDensity.record(_:)`, `InputDensity.activity`.

**Measured facts this task encodes** (verified on this machine, 2026-08-13, no permission prompt):
`CGEventSource.counterForEventType(.hidSystemState, eventType:)` returns live cumulative counts and advances under real input. It also advances for synthetically posted events, while `secondsSinceLastEventType` does not — so the ring is cleared whenever a sample reports absence, and no delta is ever computed across an absent sample.

- [x] **Step 1: Write the failing tests**

Register as entries 45 and 46 in the `tests` array:

```swift
("Input density: active, passive and absent", testInputDensity),
("Input density: ring is bounded, absence clears it", testInputDensityRing),
```

```swift
    // MARK: - 45

    private static func testInputDensity() -> [String] {
        var problems: [String] = []
        let start = base

        // Helper: feed `count` samples 20s apart, adding the given per-sample deltas.
        func feed(keys: UInt32, clicks: UInt32, scrolls: UInt32,
                  samples: Int, idle: TimeInterval = 0) -> InputDensity {
            let density = InputDensity()
            var k: UInt32 = 1_000, c: UInt32 = 50, s: UInt32 = 500
            for index in 0...samples {
                density.record(InputSample(at: start.addingTimeInterval(Double(index) * 20),
                                           keys: k, clicks: c, scrolls: s, idleSeconds: idle))
                k += keys; c += clicks; s += scrolls
            }
            return density
        }

        // One sample is not enough to measure a rate.
        let single = InputDensity()
        single.record(InputSample(at: start, keys: 0, clicks: 0, scrolls: 0, idleSeconds: 0))
        expect(single.activity == .passive,
               "a single sample cannot prove activity, got \(single.activity)", &problems)

        // 8 keys per 20s sample = 24/min, over the 12/min floor.
        expect(feed(keys: 8, clicks: 0, scrolls: 0, samples: 5).activity == .active,
               "sustained typing is active", &problems)

        // 2 keys per 20s = 6/min, under the floor, and no clicks.
        expect(feed(keys: 2, clicks: 0, scrolls: 0, samples: 5).activity == .passive,
               "occasional keys are not active", &problems)

        // Clicking with some keys is active: 2 clicks per 20s = 6/min, over the 4/min
        // click floor, with keys present.
        expect(feed(keys: 1, clicks: 2, scrolls: 0, samples: 5).activity == .active,
               "clicking with keys is active", &problems)

        // Clicking with no keys at all is not active — that is a video player.
        expect(feed(keys: 0, clicks: 2, scrolls: 0, samples: 5).activity == .passive,
               "clicks alone are not active", &problems)

        // Scrolling and mouse movement never qualify: a film plays while a hand
        // rests on the trackpad.
        expect(feed(keys: 0, clicks: 0, scrolls: 40, samples: 5).activity == .passive,
               "scrolling alone is passive", &problems)

        // Past the idle cutoff nobody is there, whatever the counters say.
        expect(feed(keys: 40, clicks: 40, scrolls: 40, samples: 5,
                    idle: AppUsageTracker.idleCutoff + 1).activity == .absent,
               "past the idle cutoff the user is absent", &problems)

        return problems
    }

    // MARK: - 46

    private static func testInputDensityRing() -> [String] {
        var problems: [String] = []
        let density = InputDensity()
        let start = base

        // Far more samples than the ring holds; memory must not grow.
        var keys: UInt32 = 0
        for index in 0..<(FocusConstants.densityRingSize * 10) {
            keys += 8
            density.record(InputSample(at: start.addingTimeInterval(Double(index) * 20),
                                       keys: keys, clicks: 0, scrolls: 0, idleSeconds: 0))
        }
        expect(density.sampleCount == FocusConstants.densityRingSize,
               "the ring is capped at \(FocusConstants.densityRingSize), got "
               + "\(density.sampleCount)", &problems)
        expect(density.activity == .active, "sustained typing is still active", &problems)

        // An absent sample clears the ring: the counters may have advanced from
        // synthetic events while nobody was there, and a delta measured across
        // that gap would be a lie.
        density.record(InputSample(at: start.addingTimeInterval(10_000),
                                   keys: keys + 5_000, clicks: 0, scrolls: 0,
                                   idleSeconds: AppUsageTracker.idleCutoff + 1))
        expect(density.sampleCount == 0, "absence clears the ring, got "
               + "\(density.sampleCount)", &problems)
        expect(density.activity == .absent, "and reports absence", &problems)

        // Coming back, the first sample after the gap cannot claim activity.
        density.record(InputSample(at: start.addingTimeInterval(10_020),
                                   keys: keys + 5_000, clicks: 0, scrolls: 0, idleSeconds: 0))
        expect(density.activity == .passive,
               "the first sample after a gap is not proof of activity", &problems)

        return problems
    }
```

- [x] **Step 2: Run the tests and watch them fail**

Run: `./build.sh --test`
Expected: compilation fails with `cannot find 'InputDensity' in scope`.

- [x] **Step 3: Add the constants to `Sources/Core/SessionState.swift`**

Insert into `FocusConstants`, before `static let bundleIdentifier`:

```swift
    /// Input sampling. The cadence is a compromise: fine enough that a short
    /// focused burst is still visible, coarse enough that it costs nothing.
    static let inputSampleInterval: TimeInterval = 20
    /// Five minutes of history at that cadence. Fixed, so memory is constant
    /// however long the app runs.
    static let densityRingSize = 15
    /// Per-minute floors separating producing from consuming.
    static let activeKeysPerMinute: Double = 12
    static let activeClicksPerMinute: Double = 4
    /// An app must be attended at least this long to count as a session's side
    /// app. Keeps a two-second Finder detour out of the list.
    static let sideAppMinimum: TimeInterval = 60
```

- [x] **Step 4: Create `Sources/Core/InputDensity.swift`**

```swift
import CoreGraphics
import Foundation

/// Whether somebody is producing something, consuming something, or gone.
enum InputActivity: String, Equatable {
    case absent, passive, active
}

/// One reading of the system input counters.
struct InputSample: Equatable {
    let at: Date
    let keys: UInt32
    let clicks: UInt32
    let scrolls: UInt32
    let idleSeconds: TimeInterval
}

/// Reads cumulative per-type event *counts* — never event content — so it needs
/// no Input Monitoring grant, the same reasoning that makes `IdleMonitor`
/// permissible. Verified 2026-08-13: no TCC prompt, counters advance under real
/// input.
struct InputCounters {
    var keys: () -> UInt32 = {
        CGEventSource.counterForEventType(.hidSystemState, eventType: .keyDown)
    }
    var clicks: () -> UInt32 = {
        CGEventSource.counterForEventType(.hidSystemState, eventType: .leftMouseDown)
    }
    var scrolls: () -> UInt32 = {
        CGEventSource.counterForEventType(.hidSystemState, eventType: .scrollWheel)
    }

    static let zero = InputCounters(keys: { 0 }, clicks: { 0 }, scrolls: { 0 })
}

/// Classifies recent input as active, passive or absent over a bounded window.
///
/// The counters also advance for synthetically posted events, while the idle
/// timer does not. So an absent sample clears the window outright rather than
/// being stored: a delta measured across a gap in which nobody was present
/// would be a lie, and this is the one place that lie could enter the data.
final class InputDensity {

    private var ring: [InputSample] = []

    /// Exposed for the tests; nothing in the app depends on it.
    var sampleCount: Int { ring.count }

    func record(_ sample: InputSample) {
        guard sample.idleSeconds < AppUsageTracker.idleCutoff else {
            ring.removeAll(keepingCapacity: true)
            return
        }
        ring.append(sample)
        if ring.count > FocusConstants.densityRingSize {
            ring.removeFirst(ring.count - FocusConstants.densityRingSize)
        }
    }

    var activity: InputActivity {
        guard let first = ring.first, let last = ring.last else { return .absent }
        // One sample proves a person is present but measures no rate.
        let minutes = last.at.timeIntervalSince(first.at) / 60
        guard ring.count >= 2, minutes > 0 else { return .passive }

        let keysPerMinute = Double(last.keys &- first.keys) / minutes
        let clicksPerMinute = Double(last.clicks &- first.clicks) / minutes

        if keysPerMinute >= FocusConstants.activeKeysPerMinute { return .active }
        // Clicking counts only alongside some typing. Clicks alone are a video
        // player; scrolls and mouse movement never qualify at all.
        if clicksPerMinute >= FocusConstants.activeClicksPerMinute && keysPerMinute > 0 {
            return .active
        }
        return .passive
    }
}
```

- [x] **Step 5: Run the tests**

Run: `./build.sh --test`
Expected: `46/46 passed`.

- [x] **Step 6: Commit** *(skipped — not a git repository)*

---

### Task 3: threadID on the record, the engine and the snapshot

**Files:**
- Modify: `Sources/Core/SessionState.swift` (`SessionRecord`, `PersistedState`)
- Modify: `Sources/Core/SessionEngine.swift`
- Test: `Sources/SelfTest.swift`

**Interfaces:**
- Produces: `SessionRecord.threadID: UUID`, `SessionEngine.activeThreadID: UUID`, `SessionEngine.start(workType:intent:threadID:)`.

- [x] **Step 1: Write the failing tests**

Register as entries 47 and 48:

```swift
("Threads: records carry a thread, legacy JSON decodes", testThreadIdentity),
("Threads: continuing reuses the thread, starting fresh does not", testThreadContinuity),
```

```swift
    // MARK: - 47

    private static func testThreadIdentity() -> [String] {
        var problems: [String] = []

        // A record made the ordinary way gets its own thread.
        let a = SessionRecord(name: "Refactor", workType: .deepWork,
                              start: base, end: base.addingTimeInterval(600),
                              workSeconds: 600)
        let b = SessionRecord(name: "Refactor", workType: .deepWork,
                              start: base, end: base.addingTimeInterval(600),
                              workSeconds: 600)
        expect(a.threadID != b.threadID,
               "two independent records are two threads", &problems)

        // A record can be told which thread it belongs to.
        let thread = UUID()
        let joined = SessionRecord(name: "Refactor", workType: .deepWork,
                                   start: base, end: base.addingTimeInterval(600),
                                   workSeconds: 600, threadID: thread)
        expect(joined.threadID == thread, "an explicit thread is kept", &problems)

        // Round-trips.
        guard let encoded = try? JSONEncoder().encode(joined),
              let decoded = try? JSONDecoder().decode(SessionRecord.self, from: encoded) else {
            problems.append("a record with a thread must round-trip")
            return problems
        }
        expect(decoded.threadID == thread, "the thread survives a round-trip", &problems)

        // Legacy JSON written before threads existed must still decode, each
        // record becoming its own single-segment thread — which is the truth
        // about it.
        let legacy = """
        {"id":"\(UUID().uuidString)","name":"Old","workType":"deepWork",
         "start":0,"end":600,"workSeconds":600}
        """
        guard let old = try? JSONDecoder().decode(SessionRecord.self,
                                                  from: Data(legacy.utf8)) else {
            problems.append("legacy JSON without threadID must decode")
            return problems
        }
        expect(old.name == "Old", "legacy fields still decode", &problems)

        let legacyB = """
        {"id":"\(UUID().uuidString)","name":"Old","workType":"deepWork",
         "start":0,"end":600,"workSeconds":600}
        """
        if let otherOld = try? JSONDecoder().decode(SessionRecord.self,
                                                    from: Data(legacyB.utf8)) {
            expect(old.threadID != otherOld.threadID,
                   "each legacy record is its own thread", &problems)
        } else {
            problems.append("the second legacy record must decode too")
        }

        return problems
    }

    // MARK: - 48

    private static func testThreadContinuity() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let engine = makeEngine(clock)

        engine.start(workType: .deepWork, intent: "Refactor")
        let first = engine.activeThreadID
        clock.value = base.addingTimeInterval(600)
        engine.stop()

        guard let firstRecord = engine.archive.records.last else {
            problems.append("the first session must be archived")
            return problems
        }
        expect(firstRecord.threadID == first,
               "the archived record carries the engine's thread", &problems)

        // Continuing reuses the thread.
        clock.value = base.addingTimeInterval(3_600)
        engine.start(workType: .deepWork, intent: "Refactor", threadID: first)
        expect(engine.activeThreadID == first,
               "continuing adopts the thread", &problems)
        clock.value = base.addingTimeInterval(4_200)
        engine.stop()
        expect(engine.archive.records.last?.threadID == first,
               "the second segment joins the thread", &problems)
        expect(engine.archive.records.count == 2,
               "two segments, two records — the gap is never worked time", &problems)

        // Starting fresh does not.
        clock.value = base.addingTimeInterval(7_200)
        engine.start(workType: .admin, intent: "Email")
        expect(engine.activeThreadID != first,
               "an unrelated session is a new thread", &problems)
        clock.value = base.addingTimeInterval(7_800)
        engine.stop()

        // Restarting mid-session must not lose the link: the thread is part of
        // the persisted snapshot, not just in memory.
        clock.value = base.addingTimeInterval(10_000)
        engine.start(workType: .deepWork, intent: "Refactor", threadID: first)
        let restored = SessionEngine(store: engine.store,
                                     archive: engine.archive,
                                     ownBundleID: FocusConstants.bundleIdentifier,
                                     schedulesDwell: false,
                                     now: { clock.value })
        restored.loadState()
        expect(restored.activeThreadID == first,
               "the thread survives a relaunch mid-session", &problems)

        return problems
    }
```

- [x] **Step 2: Run the tests and watch them fail**

Run: `./build.sh --test`
Expected: compilation fails with `extra argument 'threadID' in call`.

- [x] **Step 3: Add `threadID` to `SessionRecord` in `Sources/Core/SessionState.swift`**

Replace the struct at lines 120–143 with:

```swift
struct SessionRecord: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var workType: WorkType
    var start: Date
    var end: Date
    var workSeconds: Double
    var detectedApp: String?
    /// Segments of one piece of work share a thread. Continuing a session
    /// starts a new record with the same thread rather than reopening the old
    /// one, so a four-hour lunch is never rendered as worked time.
    var threadID: UUID

    init(id: UUID = UUID(),
         name: String,
         workType: WorkType,
         start: Date,
         end: Date,
         workSeconds: Double,
         detectedApp: String? = nil,
         threadID: UUID = UUID()) {
        self.id = id
        self.name = name
        self.workType = workType
        self.start = start
        self.end = end
        self.workSeconds = workSeconds
        self.detectedApp = detectedApp
        self.threadID = threadID
    }

    /// Records written before threads existed decode with a fresh thread each,
    /// so every old session becomes its own single-segment thread. Same pattern
    /// as `AppUsageSession.endReason`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        workType = try container.decode(WorkType.self, forKey: .workType)
        start = try container.decode(Date.self, forKey: .start)
        end = try container.decode(Date.self, forKey: .end)
        workSeconds = try container.decode(Double.self, forKey: .workSeconds)
        detectedApp = try container.decodeIfPresent(String.self, forKey: .detectedApp)
        threadID = try container.decodeIfPresent(UUID.self, forKey: .threadID) ?? UUID()
    }
}
```

- [x] **Step 4: Add `threadID` to `PersistedState`**

In `Sources/Core/SessionState.swift`, add the property to `PersistedState` beside `name`:

```swift
    /// Nil in snapshots written before threads existed.
    var threadID: UUID?
```

If `PersistedState` has a memberwise initialiser written out, add `threadID: UUID? = nil` as a defaulted parameter and assign it. If it relies on the synthesised one, the optional needs no further work — `Codable` treats a missing optional as `nil`.

- [x] **Step 5: Carry the thread through `Sources/Core/SessionEngine.swift`**

Add beside `activeWorkType` (line 53):

```swift
    /// The thread the running session belongs to. A fresh session gets a fresh
    /// thread; continuing adopts an existing one.
    private(set) var activeThreadID = UUID()
```

Change `start` (line 342):

```swift
    func start(workType: WorkType, intent: String, threadID: UUID = UUID()) {
        if state != .idle { stop() }
        activeWorkType = workType
        activeDetectedApp = currentAppBundleID
        activeThreadID = threadID
        store.sessionName = intent.trimmingCharacters(in: .whitespacesAndNewlines)
        transition(on: .launch)
    }
```

Change `archiveCurrentSession` (line 328) to carry it:

```swift
        archive.append(SessionRecord(name: sessionName,
                                     workType: activeWorkType,
                                     start: sessionStartDate,
                                     end: now(),
                                     workSeconds: elapsed,
                                     detectedApp: activeDetectedApp,
                                     threadID: activeThreadID))
```

In the method that builds `PersistedState` for `persist()`, set `threadID: activeThreadID`. In `loadState()`, restore it:

```swift
        activeThreadID = snapshot.threadID ?? UUID()
```

- [x] **Step 6: Run the tests**

Run: `./build.sh --test`
Expected: `48/48 passed`.

- [x] **Step 7: Commit** *(skipped — not a git repository)*

---

### Task 4: ThreadStats — grouping and side apps

**Files:**
- Create: `Sources/Core/SessionThread.swift`
- Test: `Sources/SelfTest.swift`

**Interfaces:**
- Consumes: `SessionArchive.records(on:)`, `AppUsageArchive.sessions`, `AppRank`, `PurposeMap.purpose(for:activity:overrides:)`, `FocusConstants.sideAppMinimum`.
- Produces: `ThreadSummary`, `ThreadApps`, `RunningThread`, `ThreadStats.threads(on:running:)`, `ThreadStats.apps(for:on:)`.

- [x] **Step 1: Write the failing tests**

Register as entries 49 and 50:

```swift
("Threads: grouped, summed, ordered, running included", testThreadSummaries),
("Threads: primary app by purpose, side apps above the floor", testThreadApps),
```

```swift
    // MARK: - 49

    private static func testThreadSummaries() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let sessionDir = scratchDirectory(), usageDir = scratchDirectory()
        let archive = SessionArchive(directory: sessionDir, now: { clock.value })
        let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: base)
        let thread = UUID()

        // Two segments of one thread, plus an unrelated session between them.
        archive.append(SessionRecord(name: "Refactor", workType: .deepWork,
                                     start: today.addingTimeInterval(9 * 3_600),
                                     end: today.addingTimeInterval(9 * 3_600 + 3_600),
                                     workSeconds: 3_600, threadID: thread))
        archive.append(SessionRecord(name: "Email", workType: .admin,
                                     start: today.addingTimeInterval(11 * 3_600),
                                     end: today.addingTimeInterval(11 * 3_600 + 600),
                                     workSeconds: 600))
        archive.append(SessionRecord(name: "Refactor", workType: .deepWork,
                                     start: today.addingTimeInterval(13 * 3_600),
                                     end: today.addingTimeInterval(13 * 3_600 + 1_800),
                                     workSeconds: 1_800, threadID: thread))

        let stats = ThreadStats(sessions: archive, usage: usage, now: { clock.value })
        let threads = stats.threads(on: base, running: nil)

        expect(threads.count == 2, "two threads today, got \(threads.count)", &problems)
        guard let refactor = threads.first(where: { $0.threadID == thread }) else {
            problems.append("the refactor thread must be present")
            return problems
        }
        expect(refactor.segments == 2, "two segments, got \(refactor.segments)", &problems)
        expectClose(refactor.totalWorked, 5_400,
                    "worked time sums across segments", &problems)
        expect(refactor.name == "Refactor", "the thread takes the segment name", &problems)
        expect(!refactor.isRunning, "nothing is running", &problems)

        // Ordered by last end, newest first: refactor ended at 13:30, email 11:10.
        expect(threads.first?.threadID == thread,
               "the most recently touched thread comes first", &problems)

        // The running session is included and marked, the same rule
        // `sessionsToday` already follows — one surface must never disagree
        // with another.
        let live = RunningThread(threadID: thread, name: "Refactor",
                                 workType: .deepWork,
                                 start: today.addingTimeInterval(15 * 3_600),
                                 worked: 900)
        let withRunning = stats.threads(on: base, running: live)
        guard let merged = withRunning.first(where: { $0.threadID == thread }) else {
            problems.append("the running thread must be present")
            return problems
        }
        expect(merged.segments == 3, "the running segment counts, got \(merged.segments)",
               &problems)
        expectClose(merged.totalWorked, 6_300, "and its time counts", &problems)
        expect(merged.isRunning, "and it is marked running", &problems)

        // A running session on a brand-new thread appears as its own thread.
        let fresh = RunningThread(threadID: UUID(), name: "Design", workType: .deepWork,
                                  start: today.addingTimeInterval(16 * 3_600), worked: 300)
        expect(stats.threads(on: base, running: fresh).count == 3,
               "a new running thread is a third thread", &problems)

        try? FileManager.default.removeItem(at: sessionDir)
        try? FileManager.default.removeItem(at: usageDir)
        return problems
    }

    // MARK: - 50

    private static func testThreadApps() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let sessionDir = scratchDirectory(), usageDir = scratchDirectory()
        let archive = SessionArchive(directory: sessionDir, now: { clock.value })
        let usage = AppUsageArchive(directory: usageDir, now: { clock.value })
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: base)
        let thread = UUID()
        let segmentStart = today.addingTimeInterval(9 * 3_600)

        archive.append(SessionRecord(name: "Refactor", workType: .deepWork,
                                     start: segmentStart,
                                     end: segmentStart.addingTimeInterval(3_600),
                                     workSeconds: 3_600, threadID: thread))

        // Inside the segment: Chrome longest, Xcode second, Terminal third,
        // Finder a flicker.
        usage.record(AppUsageSession(bundleID: "com.google.Chrome", appName: "Chrome",
                                     start: segmentStart,
                                     end: segmentStart.addingTimeInterval(1_800)))
        usage.record(AppUsageSession(bundleID: "com.apple.dt.Xcode", appName: "Xcode",
                                     start: segmentStart.addingTimeInterval(1_800),
                                     end: segmentStart.addingTimeInterval(3_000)))
        usage.record(AppUsageSession(bundleID: "com.apple.Terminal", appName: "Terminal",
                                     start: segmentStart.addingTimeInterval(3_000),
                                     end: segmentStart.addingTimeInterval(3_400)))
        usage.record(AppUsageSession(bundleID: "com.apple.finder", appName: "Finder",
                                     start: segmentStart.addingTimeInterval(3_400),
                                     end: segmentStart.addingTimeInterval(3_410)))
        // Outside the segment entirely — must not appear at all.
        usage.record(AppUsageSession(bundleID: "com.netflix.Netflix", appName: "Netflix",
                                     start: today.addingTimeInterval(20 * 3_600),
                                     end: today.addingTimeInterval(20 * 3_600 + 3_600)))

        let stats = ThreadStats(sessions: archive, usage: usage, now: { clock.value })
        guard let summary = stats.threads(on: base, running: nil).first else {
            problems.append("the thread must be present")
            return problems
        }
        let apps = stats.apps(for: summary, on: base)

        // Chrome has the most time, but Xcode is the focused-purpose app and so
        // is what the session was actually *for*.
        expect(apps.primary?.bundleID == "com.apple.dt.Xcode",
               "the primary app is the focused-purpose one, got "
               + "\(apps.primary?.bundleID ?? "nil")", &problems)
        expectClose(apps.primary?.total ?? -1, 1_200, "with its own attended time", &problems)

        let sideIDs = apps.side.map(\.bundleID)
        expect(sideIDs.contains("com.google.Chrome"), "Chrome is a side app", &problems)
        expect(sideIDs.contains("com.apple.Terminal"), "Terminal is a side app", &problems)
        expect(!sideIDs.contains("com.apple.finder"),
               "a ten-second flicker is below the floor", &problems)
        expect(!sideIDs.contains("com.netflix.Netflix"),
               "an app used outside the segment is not a side app", &problems)
        expect(!sideIDs.contains("com.apple.dt.Xcode"),
               "the primary app is not also a side app", &problems)
        expect(sideIDs.first == "com.google.Chrome",
               "side apps rank by attended time", &problems)

        // With no focused-purpose app at all, the most-attended one leads.
        let plainThread = UUID()
        let plainStart = today.addingTimeInterval(14 * 3_600)
        archive.append(SessionRecord(name: "Reading", workType: .learning,
                                     start: plainStart,
                                     end: plainStart.addingTimeInterval(1_800),
                                     workSeconds: 1_800, threadID: plainThread))
        usage.record(AppUsageSession(bundleID: "com.apple.Safari", appName: "Safari",
                                     start: plainStart,
                                     end: plainStart.addingTimeInterval(1_500)))
        let plainStats = ThreadStats(sessions: archive, usage: usage, now: { clock.value })
        if let plain = plainStats.threads(on: base, running: nil)
            .first(where: { $0.threadID == plainThread }) {
            expect(plainStats.apps(for: plain, on: base).primary?.bundleID
                   == "com.apple.Safari",
                   "with no focused app the most-attended one leads", &problems)
        } else {
            problems.append("the reading thread must be present")
        }

        try? FileManager.default.removeItem(at: sessionDir)
        try? FileManager.default.removeItem(at: usageDir)
        return problems
    }
```

- [x] **Step 2: Run the tests and watch them fail**

Run: `./build.sh --test`
Expected: compilation fails with `cannot find 'ThreadStats' in scope`.

- [x] **Step 3: Create `Sources/Core/SessionThread.swift`**

```swift
import Foundation

/// One piece of work, across every segment of it worked today.
struct ThreadSummary: Identifiable, Equatable {
    let threadID: UUID
    let name: String
    let workType: WorkType
    let totalWorked: TimeInterval
    let segments: Int
    let firstStart: Date
    let lastEnd: Date
    let isRunning: Bool
    var id: UUID { threadID }
}

/// The live session, passed in rather than read from the engine so `Core` stays
/// free of the engine and the tests need no running state. Mirrors how
/// `focusQuality(for:runningSeconds:)` already takes the in-flight time.
struct RunningThread: Equatable {
    let threadID: UUID
    let name: String
    let workType: WorkType
    let start: Date
    let worked: TimeInterval
}

/// What a thread was worked *in*.
struct ThreadApps: Equatable {
    let primary: AppRank?
    let side: [AppRank]

    static let none = ThreadApps(primary: nil, side: [])
}

/// Groups the day's session records into threads and derives each thread's apps
/// from the usage archive.
///
/// Side apps are derived, never stored on the record: the usage archive already
/// holds that truth, and a stored copy would go stale the moment the grouping
/// rules changed.
struct ThreadStats {

    private let sessions: SessionArchive
    private let usage: AppUsageArchive
    private let overrides: [String: String]
    private let calendar: Calendar
    private let now: () -> Date

    init(sessions: SessionArchive,
         usage: AppUsageArchive,
         purposeOverrides: [String: String] = [:],
         calendar: Calendar = .current,
         now: @escaping () -> Date = Date.init) {
        self.sessions = sessions
        self.usage = usage
        self.overrides = purposeOverrides
        self.calendar = calendar
        self.now = now
    }

    /// Newest last-end first. The running session, if any, is folded into its
    /// thread — or becomes a thread of its own if it is new work.
    func threads(on day: Date, running: RunningThread?) -> [ThreadSummary] {
        var order: [UUID] = []
        var byThread: [UUID: (name: String, workType: WorkType, worked: TimeInterval,
                              segments: Int, first: Date, last: Date, live: Bool)] = [:]

        for record in sessions.records(on: day) {
            if var existing = byThread[record.threadID] {
                existing.worked += record.workSeconds
                existing.segments += 1
                existing.first = min(existing.first, record.start)
                existing.last = max(existing.last, record.end)
                // The most recent segment's name wins: renaming a thread should
                // stick rather than being overruled by its own history.
                if record.end >= existing.last { existing.name = record.name }
                byThread[record.threadID] = existing
            } else {
                order.append(record.threadID)
                byThread[record.threadID] = (record.name, record.workType,
                                             record.workSeconds, 1,
                                             record.start, record.end, false)
            }
        }

        if let running {
            let end = now()
            if var existing = byThread[running.threadID] {
                existing.worked += running.worked
                existing.segments += 1
                existing.first = min(existing.first, running.start)
                existing.last = max(existing.last, end)
                existing.live = true
                byThread[running.threadID] = existing
            } else {
                order.append(running.threadID)
                byThread[running.threadID] = (running.name, running.workType,
                                              running.worked, 1,
                                              running.start, end, true)
            }
        }

        return order.compactMap { id -> ThreadSummary? in
            guard let entry = byThread[id] else { return nil }
            return ThreadSummary(threadID: id,
                                 name: entry.name,
                                 workType: entry.workType,
                                 totalWorked: entry.worked,
                                 segments: entry.segments,
                                 firstStart: entry.first,
                                 lastEnd: entry.last,
                                 isRunning: entry.live)
        }
        .sorted { $0.lastEnd > $1.lastEnd }
    }

    /// Primary app and side apps for a thread, measured over the union of its
    /// segments' time ranges.
    func apps(for thread: ThreadSummary, on day: Date) -> ThreadApps {
        let ranges = segmentRanges(for: thread, on: day)
        guard !ranges.isEmpty else { return .none }

        var totals: [String: (name: String, total: TimeInterval, longest: TimeInterval)] = [:]
        for session in usage.sessions {
            var attended: TimeInterval = 0
            var longest: TimeInterval = 0
            for range in ranges {
                let start = max(session.start, range.start)
                let end = min(session.end, range.end)
                guard end > start else { continue }
                let overlap = end.timeIntervalSince(start)
                attended += overlap
                longest = max(longest, overlap)
            }
            guard attended > 0 else { continue }
            var entry = totals[session.bundleID] ?? (session.appName, 0, 0)
            entry.name = session.appName
            entry.total += attended
            entry.longest = max(entry.longest, longest)
            totals[session.bundleID] = entry
        }
        guard !totals.isEmpty else { return .none }

        let overall = totals.values.reduce(0) { $0 + $1.total }
        var ranks: [AppRank] = []
        for (bundleID, entry) in totals {
            ranks.append(AppRank(bundleID: bundleID,
                                 appName: entry.name,
                                 total: entry.total,
                                 share: overall > 0 ? entry.total / overall : 0,
                                 longest: entry.longest))
        }
        ranks.sort { $0.total > $1.total }

        // The tool the work was done *in* is the focused-purpose app, not
        // necessarily the one with the most minutes: a browser open beside an
        // editor all afternoon is support, not subject. Purpose is resolved at
        // `.active`, since these ranges are time the user declared as work.
        let primary = ranks.first {
            PurposeMap.purpose(for: $0.bundleID, activity: .active,
                               overrides: overrides).isFocused
        } ?? ranks.first

        let side = ranks.filter {
            $0.bundleID != primary?.bundleID && $0.total >= FocusConstants.sideAppMinimum
        }
        return ThreadApps(primary: primary, side: side)
    }

    private func segmentRanges(for thread: ThreadSummary,
                               on day: Date) -> [(start: Date, end: Date)] {
        var ranges = sessions.records(on: day)
            .filter { $0.threadID == thread.threadID }
            .map { (start: $0.start, end: $0.end) }
        if thread.isRunning {
            // The live segment: from the thread's last recorded end, or its
            // start if there is none, up to now.
            ranges.append((start: ranges.last?.end ?? thread.firstStart, end: now()))
        }
        return ranges
    }
}
```

- [x] **Step 4: Run the tests**

Run: `./build.sh --test`
Expected: `50/50 passed`.

- [x] **Step 5: Commit** *(skipped — not a git repository)*

---

### Task 5: Event-boundary sampling

**Files:**
- Modify: `Sources/App/AppCoordinator.swift`

**Interfaces:**
- Consumes: `InputCounters`, `InputSample`, `InputDensity`, `IdleMonitor`.
- Produces: `AppCoordinator.density: InputDensity`.

**No timer.** The app has exactly one `Timer` today — the one-second ticker in
`SessionStore`, started and stopped with the session — so nothing polls while
idle, and a new repeating timer would be the first thing to keep the process off
App Nap indefinitely. That is rejected.

Instead the counters are read inside handlers that already fire: app activation,
lock, unlock, sleep and wake. Reading three integers in a handler that was going
to run anyway adds no wakeups and no idle cost.

This also measures density **per app stretch** rather than over a global rolling
window, so a browser's purpose is decided by the input that happened while it was
frontmost rather than by typing that happened in an editor minutes earlier —
which is exactly the granularity `PurposeMap` needs, and it lines up with the
boundaries `AppUsageTracker` already segments on.

**Known limitation, recorded not hidden:** sitting in one app for hours without
switching produces no new sample, so that stretch is settled by the delta read at
the next switch. Harmless here, because purpose is only consumed when attributing
a completed stretch. Slice C's auto-start wants live state and will need to
revisit this.

No new test: the classifier is covered by tests 45 and 46, and there is no logic
left in the wiring to assert about.

- [x] **Step 1: Add the density to `Sources/App/AppCoordinator.swift`**

```swift
    /// Fed at event boundaries, never on a timer. See Task 5 of the plan.
    let density = InputDensity()
    private let inputCounters = InputCounters()
    private let densityIdle = IdleMonitor()

    /// Reads the input counters. Called only from handlers that already fire.
    private func sampleInput(absent: Bool = false) {
        density.record(InputSample(at: Date(),
                                   keys: inputCounters.keys(),
                                   clicks: inputCounters.clicks(),
                                   scrolls: inputCounters.scrolls(),
                                   idleSeconds: absent ? .greatestFiniteMagnitude
                                                       : densityIdle.idleSeconds()))
    }
```

- [x] **Step 2: Call it from the existing handlers**

In `monitor.onAppActivated` (line 118), after the existing body, add:

```swift
            self?.sampleInput()
```

In the existing `onScreenLocked` and `onSystemWillSleep` handlers add
`self?.sampleInput(absent: true)` — whatever the counters do behind a locked
screen, it was not this person working, and recording absence clears the window.

In the existing `onScreenUnlocked` and `onSystemDidWake` handlers add
`self?.sampleInput()`.

- [x] **Step 3: Build and run**

Run: `./build.sh --run`
Expected: builds clean; the app appears in the menu bar and stays responsive.

- [x] **Step 4: Confirm the idle cost is unchanged**

Run:

```bash
ps -o %cpu= -p "$(pgrep -f 'FocusContinuity.app/Contents/MacOS/FocusContinuity' | head -1)"
```

Expected: 0.0 with no session running and no app switching. The README's
"Nothing polls" claim stays true and is **not** edited.

- [x] **Step 5: Commit** *(skipped — not a git repository)*

---

### Task 6: Continue today

**Files:**
- Modify: `Sources/App/SessionStore.swift`
- Create: `Sources/Surfaces/ContinueTodaySection.swift`
- Modify: `Sources/Surfaces/PopoverView.swift`
- Test: `Sources/SelfTest.swift`

**Interfaces:**
- Consumes: `ThreadStats`, `ThreadSummary`, `ThreadApps`, `SessionEngine.start(workType:intent:threadID:)`, `AppIcon`, `SectionHeader`, `Tokens`.
- Produces: `SessionStore.threadsToday`, `SessionStore.threadApps(_:)`, `SessionStore.continueThread(_:)`, `ContinueTodaySection`.

- [x] **Step 1: Write the failing test**

Register as entry 51:

```swift
("Continue: a thread resumes with its name, type and link", testContinueThread),
```

```swift
    // MARK: - 51

    private static func testContinueThread() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let engine = makeEngine(clock)

        engine.start(workType: .learning, intent: "Read the paper")
        let thread = engine.activeThreadID
        clock.value = base.addingTimeInterval(1_200)
        engine.stop()

        // A different session runs in between and must be archived, not lost,
        // when the earlier thread is continued.
        clock.value = base.addingTimeInterval(2_000)
        engine.start(workType: .admin, intent: "Email")
        clock.value = base.addingTimeInterval(2_300)

        guard let summary = ThreadStats(sessions: engine.archive,
                                        usage: AppUsageArchive(directory: scratchDirectory(),
                                                               now: { clock.value }),
                                        now: { clock.value })
            .threads(on: base, running: nil)
            .first(where: { $0.threadID == thread }) else {
            problems.append("the earlier thread must be findable")
            return problems
        }

        engine.start(workType: summary.workType, intent: summary.name,
                     threadID: summary.threadID)
        expect(engine.activeThreadID == thread, "the thread is adopted", &problems)
        expect(engine.activeWorkType == .learning, "the work type comes back", &problems)
        expect(engine.store.sessionName == "Read the paper",
               "the name comes back, got \(engine.store.sessionName)", &problems)
        expect(engine.archive.records.contains { $0.name == "Email" },
               "the interrupted session was archived, not discarded", &problems)

        clock.value = base.addingTimeInterval(3_000)
        engine.stop()
        let segments = engine.archive.records.filter { $0.threadID == thread }
        expect(segments.count == 2, "the thread now has two segments, got "
               + "\(segments.count)", &problems)

        return problems
    }
```

- [x] **Step 2: Run the test and watch it fail**

Run: `./build.sh --test`
Expected: compilation fails, or the test fails on the thread not being adopted.

- [x] **Step 3: Add the store bridge in `Sources/App/SessionStore.swift`**

Add the published property beside `quickStarts`:

```swift
    @Published private(set) var threadsToday: [ThreadSummary] = []
```

Add the refresh, inside `refreshDashboard()` beside the period rollup:

```swift
        let threadStats = ThreadStats(sessions: engine.archive, usage: usage,
                                      purposeOverrides: prefs.purposeOverrides)
        threadsToday = threadStats.threads(on: Date(), running: runningThread())
```

Add the helpers:

```swift
    /// The live session as a thread, or nil when idle. Kept in step with
    /// `sessionsToday`: a running session counts everywhere or nowhere.
    private func runningThread() -> RunningThread? {
        guard state != .idle else { return nil }
        return RunningThread(threadID: engine.activeThreadID,
                             name: engine.sessionName,
                             workType: engine.activeWorkType,
                             start: engine.sessionStartDate,
                             worked: engine.elapsed)
    }

    func threadApps(_ thread: ThreadSummary) -> ThreadApps {
        guard let usage else { return .none }
        return ThreadStats(sessions: engine.archive, usage: usage,
                           purposeOverrides: prefs.purposeOverrides)
            .apps(for: thread, on: Date())
    }

    /// Resumes earlier work as a new segment of the same thread, and restores
    /// the context it was done in: if the thread's primary app is still
    /// running, it comes forward. If it was quit during the break, nothing is
    /// launched — reopening an app the user deliberately closed would be worse
    /// than doing nothing.
    func continueThread(_ thread: ThreadSummary) {
        guard !thread.isRunning else { return }
        let primary = threadApps(thread).primary?.bundleID
        engine.start(workType: thread.workType, intent: thread.name,
                     threadID: thread.threadID)
        if let primary,
           let app = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == primary }) {
            // Deprecated from macOS 14, correct on the 13.0 deployment target.
            app.activate(options: .activateIgnoringOtherApps)
        }
        refresh()
    }
```

If `engine.sessionName` or `engine.sessionStartDate` are private, expose them as `private(set)` — they are already read elsewhere for the popover's subtitle, so follow whatever accessor that path uses.

- [x] **Step 4: Create `Sources/Surfaces/ContinueTodaySection.swift`**

```swift
import SwiftUI

/// Earlier work, resumable in one click. Each row is a thread: what it was, how
/// long it has taken across every segment, and what it was worked in.
struct ContinueTodaySection: View {
    @ObservedObject var store: SessionStore
    var limit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            SectionHeader(title: "Continue today",
                          trailing: store.threadsToday.isEmpty
                              ? nil : "\(store.threadsToday.count)")
            if store.threadsToday.isEmpty {
                Text("No sessions yet today.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.threadsToday.prefix(limit)) { thread in
                    ThreadRow(thread: thread,
                              apps: store.threadApps(thread),
                              onContinue: { store.continueThread(thread) })
                }
            }
        }
    }
}

private struct ThreadRow: View {
    let thread: ThreadSummary
    let apps: ThreadApps
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Tokens.Space.s) {
                Text(thread.name.isEmpty ? thread.workType.displayName : thread.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: Tokens.Space.s)
                Text(Tokens.preciseDuration(thread.totalWorked))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: Tokens.Space.xs) {
                if let primary = apps.primary {
                    AppIcon(bundleID: primary.bundleID, size: 14)
                    Text(primary.appName)
                        .font(.caption)
                        .lineLimit(1)
                }
                if !apps.side.isEmpty {
                    Text("+ " + apps.side.prefix(3).map(\.appName).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: Tokens.Space.s)
                Text(segmentLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if thread.isRunning {
                    Text("running")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tint)
                } else {
                    Button("Continue", action: onContinue)
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .accessibilityLabel("Continue \(thread.name)")
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var segmentLabel: String {
        thread.segments == 1 ? "1 segment" : "\(thread.segments) segments"
    }
}
```

- [x] **Step 5: Insert the section into `Sources/Surfaces/PopoverView.swift`**

In `body`, between the timeline and `topApps` (lines 19–21):

```swift
            DayTimelineView(store: store, compact: true)
            Divider()
            ContinueTodaySection(store: store, limit: store.menuSessions)
            Divider()
            topApps
```

If the store's accessor for the recent-sessions preference is named differently, use that name — it is the same preference the per-app history already uses (`PersistenceStore.menuSessions`). Do not add a new setting.

- [x] **Step 6: Run the tests**

Run: `./build.sh --test`
Expected: `51/51 passed`.

- [x] **Step 7: Commit** *(skipped — not a git repository)*

---

### Task 7: Verification

**Files:**
- Modify: `Sources/Surfaces/GalleryView.swift`
- Modify: `README.md`

- [x] **Step 1: Tests**

Run: `./build.sh --test`
Expected: `51/51 passed`, zero warnings.

- [x] **Step 2: Seed threads in the gallery**

In `Sources/Surfaces/GalleryView.swift`, inside `seedWeek`, give today's first two records a shared thread so the Continue section has a multi-segment row to draw. Add above the `for daysAgo` loop:

```swift
            let todayThread = UUID()
```

and pass `threadID: daysAgo == 0 ? todayThread : UUID()` to the `SessionRecord` initialiser. Then append a second segment of that thread:

```swift
            archive.append(SessionRecord(name: "Refactor", workType: .deepWork,
                                         start: anchor.addingTimeInterval(-5_400),
                                         end: anchor.addingTimeInterval(-3_600),
                                         workSeconds: 1_800,
                                         detectedApp: "com.apple.dt.Xcode",
                                         threadID: todayThread))
```

- [x] **Step 3: Snapshots**

Run:

```bash
./FocusContinuity.app/Contents/MacOS/FocusContinuity --snapshot ./snapshots
```

Inspect the popover in both appearances and confirm: a multi-segment thread reads `2 segments` with a primary icon and side app names; the `firstRun` fixture shows *"No sessions yet today."* rather than dead space; the `running` fixture shows `running` in place of the Continue button; and nothing overflows 320pt.

- [x] **Step 4: Live check**

Run: `./build.sh --run`, work in two apps for a few minutes, start a session, stop it, then open the popover and press Continue. Confirm the timer restarts, the thread's total grows rather than resetting, and the segment count increments.

- [x] **Step 5: Memory**

Run:

```bash
footprint -p "$(pgrep -f 'FocusContinuity.app/Contents/MacOS/FocusContinuity' | head -1)" | grep phys_footprint
```

Expected: at or under 20 MB. `threadApps` is called per row per render, so if this regresses, memoise it in the store beside the day-slice cache rather than making the view do less.

- [x] **Step 6: README**

Document, in the Surfaces section: the purpose axis and why it is separate from the two existing classifications; that browsers and AI clients are resolved by input behaviour and why window titles are not an option; threads and the Continue section; and that side apps are derived, not stored. Update the test count and the file map.

- [x] **Step 7: Commit** *(skipped — not a git repository)*

---

## Self-Review

**Spec coverage.** `AppPurpose` and the map — Task 1. `InputDensity`, including the synthetic-event caveat — Task 2. The 20-second sampler and the corrected polling claim — Task 5. `threadID`, legacy decode, and surviving a relaunch — Task 3. `ThreadSummary`, `threads(on:)`, side-app derivation and the 60-second floor — Task 4. Continue and the menu bar section — Task 6. Snapshots, memory and README — Task 7.

**One spec item deliberately deferred:** the spec's *Dashboard* paragraph (nesting log segments under thread headers) is not in this plan. It is a second surface for the same data and the popover is what was asked for; folding it in would widen the plan without adding capability. It is recorded here so it is not lost.

**Placeholders.** None. Every code step carries the code.

**Type consistency.** `InputActivity` is defined in Task 2 and used in Task 1's `PurposeMap.purpose(for:activity:overrides:)` — Task 2 must be built first, or Task 1 will not compile; this is stated in Task 1's Interfaces block. `AppRank` is the existing type from `DashboardStats.swift`, with fields `bundleID`, `appName`, `total`, `share`, `longest`. `ThreadApps.none`, `RunningThread`, and `ThreadSummary.isRunning` are used consistently in Tasks 4, 6 and 7.


---

## Execution result

All 7 tasks complete. **51/51 tests pass**, zero warnings.

Two corrections from the user were folded in mid-execution:

1. **Continue brings the primary app forward** if it is still running
   (`activate(options: .activateIgnoringOtherApps)`), and launches nothing if it
   was quit during the break.
2. **The 20-second sampler was rejected** and never built. Density is sampled
   only inside handlers that already fire — app activation, lock, unlock, wake —
   so the app still has exactly one `Timer`, the one-second ticker that runs only
   while a session runs. The README's "Nothing polls" claim stands unedited.

The rejection produced a better design than the plan had: density is now measured
per app stretch rather than over a global rolling window, so a browser's purpose
is decided by input that happened while it was frontmost.

**Verified in the live app:** the persisted state now carries
`"threadID":"119E803F-…"`, so threads survive a relaunch mid-session on real data.

**Measurements:** 17 MB resident with the full slice, flat over 90 seconds. An
intermediate reading of 33–39 MB was investigated and traced to environmental
drift, not to this work — disabling both the store call and the view left it
unchanged at 33 MB.

**One defect found and fixed during verification:** the popover showed "Tracking
starts when you switch apps." twice once the new section sat between the timeline
and Top apps. The timeline's empty state now reads "No app time recorded for this
day yet."

**Deferred to a later slice:** nesting dashboard log rows under thread headers
(recorded in the plan's self-review), and slices C (auto sessions) and D
(learning).
