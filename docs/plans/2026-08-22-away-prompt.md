# Away Prompt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ask the away question where the user is — a quick menu-bar-anchored card for short absences, a blurred full-screen prompt for long ones — with one answer grid (range in the header, four equal buttons) shared by every surface; and split `SessionStore` in two.

**Architecture:** The engine exposes the pending absence's range; the store publishes it. A pure `AwayPromptTier` rule picks quick vs full from the absence length and a new setting. `AwayAnswerGrid` is the single answer UI; `ResolveCard` wraps it for the popover and dashboard. Two AppKit surfaces — a non-activating anchored panel and a key-capable blur window — host the grid; an `@MainActor` `AwayPrompter` owns both and follows `store.$pendingAway`.

**Tech Stack:** Swift 5, SwiftUI, AppKit, Combine. `swiftc` via `./build.sh`. macOS 13.

**Spec:** `docs/specs/2026-08-22-away-prompt-design.md`

## Global Constraints

- Not a git repository; commit steps recorded, skipped.
- No `@State` / `@Observable` (no macros). `ObservableObject` + `@Published`; `@StateObject` / `@ObservedObject`.
- `Sources/Core/` imports Foundation and CoreGraphics only.
- Exactly one repeating `Timer` (`SessionStore.startTicker()`). The quick prompt's fade uses a `DispatchWorkItem`, not a timer.
- No new TCC permissions; no packages; no warnings (`./build.sh` prints none).
- Never delete; move to `_trash/`. Nothing in the project root.
- Build/test: `./build.sh 2>&1 | grep -E "error|warning|Build succeeded"` then `./FocusContinuity.app/Contents/MacOS/FocusContinuity --selftest 2>&1 | grep -E "FAIL|passed"`. Snapshot dir: `/private/tmp/claude-501/-Users-prabeshbhetwal-Desktop-Files-Development-Project-FocusContinuity/d9e74462-42ba-4aac-8014-68ac6cc6464b/scratchpad/snaps`.

---

### Task 1: Range, tier rule, setting

**Files:**
- Create: `Sources/Core/AwayPrompt.swift`
- Modify: `Sources/Core/SessionState.swift` (`FocusConstants`), `Sources/Core/SessionEngine.swift`, `Sources/Core/PersistenceStore.swift`, `Sources/App/SessionStore.swift`, `Sources/App/SettingsModel.swift`, `Sources/Surfaces/Settings/SettingsView.swift`
- Test: `Sources/SelfTest.swift` (85, 86; 82 count)

**Interfaces:**
- Produces: `enum AwayPromptTier { case quick, full; static func tier(forAbsence:fullPromptAfter:) }`; `FocusConstants.defaultFullPromptAfter`, `.fullPromptAfterOptions`; `PersistenceStore.fullPromptAfter: TimeInterval?`; `SessionEngine.pendingAwayRange: (start: Date, end: Date)?`; `SessionStore.pendingAwayRange` (published); `SettingsModel.fullPromptAfter: TimeInterval` (0 = Never).

- [ ] **Step 1: Failing tests.** Before `// MARK: - 60` in `SelfTest.swift`:

```swift
    // MARK: - 85

    /// Which prompt an absence gets is a pure rule, and "Never" must mean the
    /// quick one rather than none — the question is still asked.
    private static func testAwayPromptTier() -> [String] {
        var problems: [String] = []
        expect(AwayPromptTier.tier(forAbsence: 20 * 60, fullPromptAfter: 30 * 60) == .quick,
               "under the threshold is quick", &problems)
        expect(AwayPromptTier.tier(forAbsence: 30 * 60, fullPromptAfter: 30 * 60) == .full,
               "at the threshold is full", &problems)
        expect(AwayPromptTier.tier(forAbsence: 3 * 3_600, fullPromptAfter: 30 * 60) == .full,
               "well over is full", &problems)
        expect(AwayPromptTier.tier(forAbsence: 3 * 3_600, fullPromptAfter: nil) == .quick,
               "Never means always quick", &problems)

        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let store = PersistenceStore(defaults: defaults)
        store.removeAll()
        expectClose(store.fullPromptAfter ?? -1, FocusConstants.defaultFullPromptAfter,
                    "missing key reads as the default", &problems)
        store.fullPromptAfter = nil
        expect(store.fullPromptAfter == nil, "Never round-trips as nil", &problems)
        store.fullPromptAfter = 3_600
        expectClose(store.fullPromptAfter ?? -1, 3_600, "a value round-trips", &problems)
        return problems
    }

    // MARK: - 86

    /// The card says when, not only how long. The range is derived from the
    /// return moment the engine already stamps, so it cannot disagree with the
    /// length beside it.
    private static func testPendingAwayRange() -> [String] {
        var problems: [String] = []
        let clock = Clock(base)
        let engine = makeEngine(clock)
        engine.start(workType: .deepWork, intent: "Range")
        expect(engine.pendingAwayRange == nil, "nothing pending while running", &problems)
        clock.advance(600)
        engine.transition(on: .awayBegan(trigger: .screenLock))
        clock.advance(22 * 60)
        engine.transition(on: .awayEnded)
        guard let range = engine.pendingAwayRange else {
            return problems + ["a 22-minute lock should leave a pending range"]
        }
        expectClose(range.end.timeIntervalSince(range.start), 22 * 60,
                    "the range spans the absence", &problems)
        expectClose(range.end.timeIntervalSince(clock.value), 0,
                    "and ends when the user came back", &problems)
        engine.transition(on: .decision(.continueSession))
        expect(engine.pendingAwayRange == nil, "answered means no range", &problems)
        return problems
    }
```

Register after `testPopoverStillFits13Inch`:

```swift
            ("Away prompt tier is a pure rule; Never means quick", testAwayPromptTier),
            ("Pending away range spans the absence and ends at return", testPendingAwayRange)
```

In test 82 (`testSettingsModel`), after `model.menuSessionCount = 7` block add:

```swift
        model.fullPromptAfter = 3_600
        expectClose(store.fullPromptAfter ?? -1, 3_600, "full-prompt threshold writes through", &problems)
        model.fullPromptAfter = 0
        expect(store.fullPromptAfter == nil, "zero means Never", &problems)
```
and change `expect(changes == 8, ...)` to `expect(changes == 10, ...)` (both occurrences of `changes == 8`).

- [ ] **Step 2: Run — expect `cannot find 'AwayPromptTier'`.**

- [ ] **Step 3: Core.** Create `Sources/Core/AwayPrompt.swift`:

```swift
import Foundation

/// How the away question is put to the user when they come back: lightly, from
/// the menu bar, or on a blurred screen. Pure so it can be tested without a
/// window.
enum AwayPromptTier: Equatable {
    case quick
    case full

    /// `fullPromptAfter == nil` means Never: every absence gets the quick
    /// prompt. The question is still asked — only the weight of the asking
    /// changes.
    static func tier(forAbsence away: TimeInterval,
                     fullPromptAfter: TimeInterval?) -> AwayPromptTier {
        guard let threshold = fullPromptAfter else { return .quick }
        return away >= threshold ? .full : .quick
    }
}
```

In `SessionState.swift`, after `static let longAwayCapOptions...]` add:

```swift
    /// Absences at least this long are asked about on a blurred screen rather
    /// than from the menu bar. Half an hour: a coffee is a quick click, lunch is
    /// long enough to have lost the thread. `nil` in the store means Never.
    static let defaultFullPromptAfter: TimeInterval = 30 * 60
    static let fullPromptAfterOptions: [TimeInterval] = [
        20 * 60, 30 * 60, 45 * 60, 60 * 60, 90 * 60, 120 * 60
    ]
```

In `PersistenceStore.swift`, add key `static let fullPromptAfter = "fc.fullPromptAfter"` in `Key`, and after `var longAwayCap` add:

```swift
    /// Past this an absence is asked about on a blurred screen; under it, from
    /// the menu bar. Nil is Never — stored as 0 so it survives as a choice,
    /// while a missing key reads as the default.
    var fullPromptAfter: TimeInterval? {
        get {
            guard let stored = defaults.object(forKey: Key.fullPromptAfter) as? Double else {
                return FocusConstants.defaultFullPromptAfter
            }
            return stored > 0 ? stored : nil
        }
        set { defaults.set(newValue ?? 0, forKey: Key.fullPromptAfter) }
    }
```

In `SessionEngine.swift`, after `var runningSpan` add:

```swift
    /// When the pending absence was, for the card and the prompts. Derived from
    /// the return moment already stamped in `decisionStartDate` and the length
    /// in the state, so it cannot disagree with the figure beside it.
    var pendingAwayRange: (start: Date, end: Date)? {
        guard case .awaitingUserDecision(let away, _) = state,
              let returnedAt = decisionStartDate else { return nil }
        return (start: returnedAt.addingTimeInterval(-away), end: returnedAt)
    }
```

In `SessionStore.swift`: beside `@Published private(set) var pendingAway` add
`@Published private(set) var pendingAwayRange: (start: Date, end: Date)?`; in `init`'s
`onNeedsDecision` closure add `self?.pendingAwayRange = self?.engine.pendingAwayRange` before
`self?.onAwayNeedsResolution?(away)`; in `apply(_:)` set `pendingAwayRange = engine.pendingAwayRange`
in the awaiting branch and `nil` in the else.

In `SettingsModel.swift`, after `longAwayCap` add:

```swift
    /// 0 means Never, so the picker has a concrete tag to bind to.
    var fullPromptAfter: TimeInterval {
        get { store.fullPromptAfter ?? 0 }
        set { write { store.fullPromptAfter = newValue > 0 ? newValue : nil } }
    }
```

In `SettingsView.swift`, in the *Stepping away* section after the `End session after` picker add:

```swift
                Picker("Full-screen prompt after", selection: $model.fullPromptAfter) {
                    ForEach(FocusConstants.fullPromptAfterOptions, id: \.self) {
                        Text(Tokens.duration($0)).tag($0)
                    }
                    Text("Never").tag(0.0)
                }
```
and extend the footer text with: `" Shorter absences are asked about from the menu bar; from \(model.fullPromptAfter > 0 ? Tokens.duration(model.fullPromptAfter) : "never") the question fills the screen."` — build it as a separate `Text` line beneath the existing footer text inside a `VStack(alignment: .leading, spacing: Tokens.Space.xs)`.

- [ ] **Step 4: Build, test — `86/86`.**
- [ ] **Step 5: Commit** *(recorded, skipped)* `feat: away range, prompt tier rule, full-prompt setting`

---

### Task 2: `AwayAnswerGrid`; `ResolveCard` wraps it

**Files:**
- Create: `Sources/Design/Components/AwayAnswers.swift`
- Modify: `Sources/Design/Components/Components.swift` (`ResolveCard`), `Sources/Surfaces/Popover/HeroCard.swift`, `Sources/Surfaces/Dashboard/DashboardView.swift`, `Sources/Surfaces/GalleryView.swift` (strip)

- [ ] **Step 1: Create `AwayAnswers.swift`:**

```swift
import SwiftUI

/// The four answers to "what was that?", as one grid used by every surface that
/// asks: the popover card, the dashboard card, the quick prompt, the full
/// prompt. Header says how long and when; the recommended answer is filled.
struct AwayAnswerGrid: View {
    let away: TimeInterval
    var range: (start: Date, end: Date)?
    var showsCaptions: Bool = false
    var compact: Bool = false
    let onAnswer: (UserDecision) -> Void

    private struct Answer: Identifiable {
        let decision: UserDecision
        let title: String
        let caption: String
        let prominent: Bool
        var id: String { decision.rawValue }
    }

    private var answers: [Answer] {
        [
            Answer(decision: .tookBreak, title: "It was a break",
                   caption: "Not counted, written down as rest", prominent: true),
            Answer(decision: .mergeTime, title: "I was working",
                   caption: "Count it as work on this session", prominent: false),
            Answer(decision: .continueSession, title: "I was away",
                   caption: "Not counted, nothing recorded", prominent: false),
            Answer(decision: .resetTimer, title: "Start fresh",
                   caption: "End that session where you left, begin a new one",
                   prominent: false)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? Tokens.Space.s : Tokens.Space.m) {
            header
            Text("Not counted. Your session is still running.")
                .font(compact ? .caption : .callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: Tokens.Space.s) {
                HStack(spacing: Tokens.Space.s) {
                    button(answers[0]).keyboardShortcut(.defaultAction)
                    button(answers[1])
                }
                HStack(spacing: Tokens.Space.s) {
                    button(answers[2])
                    button(answers[3])
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
            Label("Away \(Tokens.duration(away))", systemImage: "moon.zzz.fill")
                .font(compact ? .headline : .title3.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
            if let range {
                Text(Tokens.timeRange(range.start, range.end))
                    .font(compact ? .caption : .callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func button(_ answer: Answer) -> some View {
        Button { onAnswer(answer.decision) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(answer.title)
                    .font(compact ? .callout.weight(.semibold) : .body.weight(.semibold))
                if showsCaptions {
                    Text(answer.caption)
                        .font(.caption)
                        .opacity(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, compact ? Tokens.Space.m : Tokens.Space.l)
            .padding(.vertical, compact ? 7 : (showsCaptions ? Tokens.Space.m : 9))
            .background(answer.prominent ? AnyShapeStyle(Color.accentColor)
                                         : AnyShapeStyle(Tokens.Surface.well),
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.control,
                                             style: .continuous))
            .foregroundStyle(answer.prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.control))
        }
        .buttonStyle(.plain)
        .help(showsCaptions ? "" : answer.caption)
        .accessibilityLabel("\(answer.title). \(answer.caption)")
    }
}
```

- [ ] **Step 2: `ResolveCard` becomes a wrapper.** Replace the whole `struct ResolveCard` in `Components.swift` with:

```swift
/// Non-blocking resolution of a long absence, as a card: the grid inside a
/// frame, or bare when it already sits in another card.
struct ResolveCard: View {
    let away: TimeInterval
    var range: (start: Date, end: Date)?
    var framed: Bool = true
    let onAnswer: (UserDecision) -> Void

    var body: some View {
        let grid = AwayAnswerGrid(away: away, range: range, compact: true, onAnswer: onAnswer)
            .frame(maxWidth: .infinity, alignment: .leading)
        if framed {
            grid.card(padding: Tokens.Space.m)
        } else {
            grid
        }
    }
}
```

Update the two call sites to `ResolveCard(away: away, range: store.pendingAwayRange, framed: false) { store.resolve($0) }` (HeroCard) and the same in `DashboardView.activeSession`.

In `GalleryView.ComponentStrip`, append after `StartButton(fills: false) {}`:

```swift
            AwayAnswerGrid(away: 22 * 60,
                           range: (Date().addingTimeInterval(-22 * 60), Date()),
                           showsCaptions: true) { _ in }
                .frame(width: 420)
```

- [ ] **Step 3: Build, test — `86/86`; snapshot; open `needsResolution-dark.png` and `components-light.png`.** Expected: the hero's away card shows `Away 22m · 9:10 – 9:32 am` and four equal buttons, the first filled; the strip shows the captioned version.
- [ ] **Step 4: Commit** *(recorded, skipped)* `design: away answer grid with range; resolve card wraps it`

---

### Task 3: Quick panel and full prompt

**Files:**
- Modify: `Sources/Surfaces/RewardHUD.swift` (make `NonActivatingHUDPanel`, `FirstMouseHostingView` internal)
- Create: `Sources/Surfaces/AwayPrompt/AwayQuickPanel.swift`, `Sources/Surfaces/AwayPrompt/AwayFullPrompt.swift`

- [ ] **Step 1:** In `RewardHUD.swift` change `private final class NonActivatingHUDPanel` → `final class NonActivatingHUDPanel` and `private final class FirstMouseHostingView` → `final class FirstMouseHostingView`.

- [ ] **Step 2: Create `AwayQuickPanel.swift`:**

```swift
import SwiftUI
import AppKit

private final class QuickPromptModel: ObservableObject {
    @Published var away: TimeInterval = 0
    @Published var range: (start: Date, end: Date)?
}

private struct QuickPromptView: View {
    @ObservedObject var model: QuickPromptModel
    let onAnswer: (UserDecision) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Triangle()
                .fill(.regularMaterial)
                .frame(width: 18, height: 9)
            AwayAnswerGrid(away: model.away, range: model.range, compact: true,
                           onAnswer: onAnswer)
                .padding(Tokens.Space.m)
                .frame(width: 300, alignment: .leading)
                .background(.regularMaterial,
                            in: RoundedRectangle(cornerRadius: Tokens.Radius.card,
                                                 style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                    .strokeBorder(Tokens.Surface.hairline))
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The light way to ask: a small card with an arrow, under the menu-bar item,
/// that never takes focus — one click answers without leaving the app in
/// front. Fades after twenty seconds; the popover card stays.
@MainActor
final class AwayQuickPanel {
    private let panel: NonActivatingHUDPanel
    private let model = QuickPromptModel()
    private var fade: DispatchWorkItem?
    private var generation = 0

    init(onAnswer: @escaping (UserDecision) -> Void) {
        let panel = NonActivatingHUDPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.nonactivatingPanel, .hudWindow, .borderless],
            backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.alphaValue = 0
        self.panel = panel
        panel.contentView = FirstMouseHostingView(
            rootView: QuickPromptView(model: model, onAnswer: onAnswer))
    }

    func show(away: TimeInterval, range: (start: Date, end: Date)?) {
        generation += 1
        let current = generation
        fade?.cancel()
        model.away = away
        model.range = range
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? NSSize(width: 300, height: 200)
        panel.setContentSize(size)
        panel.setFrameOrigin(AwayQuickPanel.anchor(for: size))
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.generation == current else { return }
            self.dismiss()
        }
        fade = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: item)
    }

    func dismiss() {
        generation += 1
        fade?.cancel()
        fade = nil
        guard panel.alphaValue > 0 else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
        })
    }

    /// Centred under the status item when its window can be found; otherwise
    /// tucked into the top-right of the main screen. `MenuBarExtra` exposes no
    /// frame, so the status-bar window is the best evidence there is.
    private static func anchor(for size: NSSize) -> NSPoint {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let menuBarTop = screen?.frame.maxY ?? visible.maxY
        if let item = NSApp.windows.first(where: {
            $0.className == "NSStatusBarWindow" && $0.frame.maxY >= menuBarTop - 1
        }) {
            let x = item.frame.midX - size.width / 2
            let clampedX = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
            return NSPoint(x: clampedX, y: item.frame.minY - size.height - 2)
        }
        return NSPoint(x: visible.maxX - size.width - 16, y: visible.maxY - size.height - 8)
    }
}
```

- [ ] **Step 3: Create `AwayFullPrompt.swift`:**

```swift
import SwiftUI
import AppKit

private final class FullPromptModel: ObservableObject {
    @Published var away: TimeInterval = 0
    @Published var range: (start: Date, end: Date)?
}

private struct FullPromptView: View {
    @ObservedObject var model: FullPromptModel
    let onAnswer: (UserDecision) -> Void
    let onLater: () -> Void

    var body: some View {
        ZStack {
            // Click-catcher: anywhere outside the card is "later".
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onLater)
            VStack(alignment: .leading, spacing: Tokens.Space.l) {
                AwayAnswerGrid(away: model.away, range: model.range, showsCaptions: true,
                               onAnswer: onAnswer)
                HStack {
                    Spacer()
                    Button("Later", action: onLater)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(Tokens.Space.xl)
            .frame(width: 520)
            .background(Tokens.Surface.card,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.card + 4,
                                             style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card + 4, style: .continuous)
                .strokeBorder(Tokens.Surface.hairline))
            .shadow(color: .black.opacity(0.25), radius: 30, y: 12)
        }
    }
}

/// A borderless window that can take the keyboard, so Return and Esc work.
private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The heavy way to ask: the display under the pointer goes soft behind a
/// centred card. For absences long enough that the thread is lost anyway, so
/// a centred question costs nothing and a missed one would.
@MainActor
final class AwayFullPrompt {
    private var window: KeyableWindow?
    private let model = FullPromptModel()
    private let onAnswer: (UserDecision) -> Void
    private let onLater: () -> Void

    init(onAnswer: @escaping (UserDecision) -> Void, onLater: @escaping () -> Void) {
        self.onAnswer = onAnswer
        self.onLater = onLater
    }

    func show(away: TimeInterval, range: (start: Date, end: Date)?) {
        model.away = away
        model.range = range
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let window = self.window ?? makeWindow()
        window.setFrame(screen.frame, display: false)
        NSApp.activate(ignoringOtherApps: true)
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            window.animator().alphaValue = 1
        }
    }

    func dismiss() {
        guard let window, window.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
        })
    }

    private func makeWindow() -> KeyableWindow {
        let window = KeyableWindow(contentRect: NSScreen.main?.frame ?? .zero,
                                   styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = false

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]
        let hosting = NSHostingView(rootView: FullPromptView(model: model,
                                                             onAnswer: onAnswer,
                                                             onLater: onLater))
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = blur.bounds
        blur.addSubview(hosting)
        window.contentView = blur
        hosting.frame = blur.bounds
        self.window = window
        return window
    }
}
```

- [ ] **Step 4: Build — expect `Build succeeded`, `86/86`.** (Nothing shows yet.)
- [ ] **Step 5: Commit** *(recorded, skipped)* `surfaces: quick away panel and full-screen away prompt`

---

### Task 4: `AwayPrompter`, wiring, harness renders

**Files:**
- Create: `Sources/App/AwayPrompter.swift`
- Modify: `Sources/App/AppCoordinator.swift`, `Sources/Surfaces/Snapshotter.swift`

- [ ] **Step 1: Create `AwayPrompter.swift`:**

```swift
import SwiftUI
import Combine

/// Decides how the away question is put — quick from the menu bar or full on a
/// blurred screen — and keeps both in step with the one pending question the
/// store publishes. Answering anywhere resolves everywhere; dismissing leaves
/// the popover card standing.
@MainActor
final class AwayPrompter {
    private let store: SessionStore
    private let fullPromptAfter: () -> TimeInterval?
    private lazy var quick = AwayQuickPanel { [weak self] in self?.answer($0) }
    private lazy var full = AwayFullPrompt(onAnswer: { [weak self] in self?.answer($0) },
                                           onLater: { [weak self] in self?.dismiss() })
    private var subscription: AnyCancellable?
    private var wasPending = false

    init(store: SessionStore, fullPromptAfter: @escaping () -> TimeInterval?) {
        self.store = store
        self.fullPromptAfter = fullPromptAfter
    }

    /// A question already pending at launch is asked quietly, whatever its
    /// length: a blurred screen as the first thing after login is not a welcome.
    func start() {
        if let away = store.pendingAway {
            wasPending = true
            quick.show(away: away, range: store.pendingAwayRange)
        }
        subscription = store.$pendingAway
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pending in
                guard let self else { return }
                if let away = pending {
                    if !self.wasPending { self.present(away: away) }
                    self.wasPending = true
                } else {
                    self.wasPending = false
                    self.dismiss()
                }
            }
    }

    private func present(away: TimeInterval) {
        let range = store.pendingAwayRange
        switch AwayPromptTier.tier(forAbsence: away, fullPromptAfter: fullPromptAfter()) {
        case .quick: quick.show(away: away, range: range)
        case .full: full.show(away: away, range: range)
        }
    }

    private func answer(_ decision: UserDecision) {
        dismiss()
        store.resolve(decision)
    }

    func dismiss() {
        quick.dismiss()
        full.dismiss()
    }
}
```

- [ ] **Step 2: Wire it.** In `AppCoordinator.swift`, after `@MainActor private lazy var hud = RewardHUD()` add:

```swift
    /// Puts the away question where the user is. Lazy for the same reason as
    /// the HUD: main-actor isolated, first touched on the main thread.
    @MainActor private lazy var awayPrompter = AwayPrompter(
        store: store, fullPromptAfter: { [weak self] in self?.engine.store.fullPromptAfter })
```

In `applicationDidFinishLaunching`, immediately after `store.refresh()` add:

```swift
        Task { @MainActor in self.awayPrompter.start() }
```

- [ ] **Step 3: Harness.** In `Snapshotter.run`, in the components loop add two renders after the strip:

```swift
            let quick = AwayAnswerGrid(away: 22 * 60,
                                       range: (Date().addingTimeInterval(-22 * 60), Date()),
                                       compact: true) { _ in }
                .padding(Tokens.Space.m).frame(width: 300)
                .background(Tokens.Surface.card)
                .environment(\.colorScheme, scheme)
            _ = render(quick, to: directory.appendingPathComponent(
                "awayPrompt-quick-\(scheme == .light ? "light" : "dark").png"))
            let full = AwayAnswerGrid(away: 72 * 60,
                                      range: (Date().addingTimeInterval(-72 * 60), Date()),
                                      showsCaptions: true) { _ in }
                .padding(Tokens.Space.xl).frame(width: 520)
                .background(Tokens.Surface.card)
                .environment(\.colorScheme, scheme)
            _ = render(full, to: directory.appendingPathComponent(
                "awayPrompt-full-\(scheme == .light ? "light" : "dark").png"))
```

- [ ] **Step 4: Build, test, snapshot, look** at `awayPrompt-full-dark.png`, `awayPrompt-quick-light.png`, `needsResolution-dark.png`. Relaunch. Live: with *Ask me after* at its default, leave the Mac for 16 minutes (or lock it) and return — the quick card should appear under the item; answer it and the popover card must be gone. For the full prompt, set *Full-screen prompt after* to 20m and repeat with a 21-minute lock; Esc must dismiss, Return must answer break.
- [ ] **Step 5: Commit** *(recorded, skipped)* `app: away prompter — quick or full by absence length`

---

### Task 5: `SessionStore` split

**Files:**
- Create: `Sources/App/SessionStore+Dashboard.swift`
- Modify: `Sources/App/SessionStore.swift`

- [ ] **Step 1:** Cut everything from the line `    // MARK: - Timeline inspection` up to (not including) the doc comment line `    /// Cosmetic only, exactly like the AppKit build's title timer` out of `SessionStore.swift` and write it into `SessionStore+Dashboard.swift` as:

```swift
import SwiftUI

// The dashboard's half of the store: timeline inspection, per-app history, the
// day selection and the thread actions. Split from `SessionStore.swift` for
// size only — same object, same rules.
extension SessionStore {
<the cut text, re-indented as-is>
}
```

- [ ] **Step 2:** Relax these in `SessionStore.swift` from `private` to internal, each with the comment `// Internal for SessionStore+Dashboard.swift; views still never touch this.`: `let engine`, `var tracker`, `var usage`, `var cachedWindow`, `var earliestDay`. In the moved text, change `private func refreshDashboard()` to `func refreshDashboard()`. Build; for every remaining *"is inaccessible due to 'private' protection level"* error, make that one member internal with the same comment. `refresh()` in the main file still calls `refreshDashboard()`.

- [ ] **Step 3: Build, test — `86/86`.** `wc -l Sources/App/SessionStore.swift Sources/App/SessionStore+Dashboard.swift` — both under 500.
- [ ] **Step 4: Commit** *(recorded, skipped)* `store: dashboard half into its own file`

---

## Final checklist

- [x] No warnings; `86/86`.
- [x] Snapshots: `needsResolution-*`, `awayPrompt-quick-*`, `awayPrompt-full-*`, `components-*` opened and checked (archived in `2026-08-22-premium-design-screens/`).
- [ ] Live: quick prompt appears under the item and answers in one click; full prompt blurs, Esc/Return behave; popover card clears on either. *(Needs a real absence — the harness cannot stage one; see the report.)*
- [x] `SessionStore.swift` (452) and `SessionStore+Dashboard.swift` (416) both under 500 lines.
- [x] `Sources/Core` pure; one Timer.
