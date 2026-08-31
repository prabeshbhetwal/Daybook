import Foundation
import SwiftUI
import AppKit

/// Focused contracts for the compact-control presentation batch. Expectations
/// are derived from the supported 980pt and 1,160pt window widths and from the
/// actual usable display passed to the menu-bar sizing boundary.
enum CompactControlsChecks {
    static let tests: [(String, () -> [String])] = [
        ("Focus routes reveal controls without changing reading context", focusRoute),
        ("Pinned controls survive relaunch without mutating the session", pinPersistence),
        ("Menu-bar controls remain a clamped single column", popoverBounds),
        ("Popover owns one real overflow region and excludes current continuations", popoverComposition),
        ("Settings keeps one bounded frame across pages and search", settingsFrame),
        ("Settings fixtures retain a real editable search field", settingsSearchField),
        ("Month remains compact when the Story column grows wider", monthHeight),
        ("Month duration consumers keep short and invalid evidence factual", monthDurationText),
        ("Rail ordering is gated, one-step and deliberately dismissible", railArrangement),
        ("Scope keyboard commands move one coherent selection", scopeKeyboard),
        ("Native scope adapter owns focus, pointer and key selection", nativeScopeAdapter),
        ("Compact Focus consumers retain general save failures and exact Retry", generalFailurePresentation),
        ("Away Return routing is scoped to its own focused controls", awayReturnScope)
    ]

    private static func focusRoute() -> [String] {
        MainActor.assumeIsolated {
            let navigation = MainWindowModel(storyScope: .month)
            let workspace = navigation.workspace
            let scope = navigation.storyScope

            navigation.openSheet(.focus)

            var failures: [String] = []
            if navigation.sheet != nil {
                failures.append("Opening session controls still presents a Focus sheet")
            }
            if navigation.workspace != workspace || navigation.storyScope != scope {
                failures.append("Opening session controls changed the Month reading context")
            }
            navigation.dismissSessionControls()
            if navigation.focusRestorationRequest != .sessionControls {
                failures.append("Dismissing the strip did not request focus for its timer pill")
            }
            navigation.consumeFocusRestorationRequest()
            navigation.openSettings()
            navigation.closeSheet()
            if navigation.focusRestorationRequest != .settings {
                failures.append("Closing Settings did not request focus for its invoking control")
            }
            return failures
        }
    }

    private static func pinPersistence() -> [String] {
        MainActor.assumeIsolated {
            let suite = "com.prabesh.focuscontinuity.compact-pin.\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: suite) else {
                return ["Could not create isolated pin defaults"]
            }
            defer { defaults.removePersistentDomain(forName: suite) }
            let persistence = PersistenceStore(defaults: defaults)
            persistence.removeAll()
            let store = FixtureFactory.store(for: .running)
            defer { FixtureFactory.cleanUp() }
            let stateBefore = store.engine.state
            let settings = SettingsModel(store: persistence, isTrackingEnabled: true,
                                         onChange: {}, onTrackingChanged: { _ in })
            settings.sessionControlsPinned = true

            let reloaded = SettingsModel(store: persistence, isTrackingEnabled: true,
                                         onChange: {}, onTrackingChanged: { _ in })
            let navigation = MainWindowModel(storyScope: .week, store: store)
            var failures: [String] = []
            if !reloaded.sessionControlsPinned
                || !SessionControlsVisibility.isVisible(
                    expanded: navigation.sessionControlsExpanded,
                    pinned: reloaded.sessionControlsPinned) {
                failures.append("A persisted pin did not reveal controls after model relaunch")
            }
            if navigation.sessionControlsExpanded {
                failures.append("Ordinary launch expanded the transient session-controls state")
            }
            if store.engine.state != stateBefore {
                failures.append("Writing or reading the pin changed the running session")
            }
            return failures
        }
    }

    private static func popoverBounds() -> [String] {
        var failures: [String] = []
        let large = PopoverMetrics.fitting(CGSize(width: 1_440, height: 900))
        if large.width != 340 || large.twoColumn {
            failures.append("A large display produced a \(Int(large.width))pt, "
                            + "\(large.twoColumn ? "two-column" : "single-column") panel")
        }

        let smallSize = CGSize(width: 312, height: 420)
        let small = PopoverMetrics.fitting(smallSize)
        if small.width > smallSize.width || small.maxHeight > smallSize.height {
            failures.append("Small-display metrics escaped the supplied usable geometry")
        }
        if small.twoColumn {
            failures.append("Small-display metrics enabled a second column")
        }
        return failures
    }

    private static func popoverComposition() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .running, accurateUsage: true)
            defer { FixtureFactory.cleanUp() }
            store.refresh()
            let settings = SettingsModel(store: store.engine.store,
                                         isTrackingEnabled: true,
                                         onChange: {}, onTrackingChanged: { _ in })
            let metrics = PopoverMetrics.fitting(CGSize(width: 1_000, height: 680))
            let host = NSHostingView(rootView: PopoverView(store: store,
                                                          settings: settings,
                                                          metricsOverride: metrics,
                                                          scrolls: true))
            host.frame = NSRect(x: 0, y: 0, width: metrics.width, height: metrics.maxHeight)
            host.layoutSubtreeIfNeeded()
            let scrollRegions = descendantCount(in: host) { $0 is NSScrollView }
            var failures: [String] = []
            if scrollRegions != 1 {
                failures.append("The compact popover rendered \(scrollRegions) overflow regions instead of one")
            }
            let active = store.engine.activeThreadID
            let rows = FocusContinuationSource.rows(threads: store.continuableThreads,
                                                     quickStarts: store.quickStarts,
                                                     limit: 3)
            if rows.contains(where: { row in
                if case .thread(let thread) = row { return thread.id == active || thread.isRunning }
                return false
            }) {
                failures.append("Continue duplicated the current running session")
            }
            return failures
        }
    }

    @MainActor private static func descendantCount(in view: NSView,
                                                    matching: (NSView) -> Bool) -> Int {
        (matching(view) ? 1 : 0)
            + view.subviews.reduce(0) { $0 + descendantCount(in: $1, matching: matching) }
    }

    private static func settingsFrame() -> [String] {
        var failures: [String] = []
        let normal = SettingsSection.allCases.map {
            SettingsLayout.sheetHeight(section: $0, query: "")
        }
        let searched = SettingsSection.allCases.map {
            SettingsLayout.sheetHeight(section: $0, query: "privacy")
        }
        let all = normal + searched
        if Set(all).count != 1 {
            failures.append("Settings still changes height between category or search states: \(all)")
        }
        if let height = all.first, height > 600 {
            failures.append("Settings exceeds its 600pt title-inclusive height bound")
        }
        return failures
    }

    private static func settingsSearchField() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .running)
            defer { FixtureFactory.cleanUp() }
            let navigation = MainWindowModel(store: store)
            let settings = SettingsModel(store: store.engine.store,
                                         isTrackingEnabled: true,
                                         onChange: {}, onTrackingChanged: { _ in })
            let host = NSHostingView(rootView: SettingsView(model: settings,
                                                            navigation: navigation,
                                                            scrolls: false)
                .frame(width: 560, height: 520))
            host.frame = NSRect(x: 0, y: 0, width: 560, height: 520)
            host.layoutSubtreeIfNeeded()
            return containsTextInput(host) ? []
                : ["The non-scrolling Settings fixture replaced Search with static text"]
        }
    }

    @MainActor private static func containsTextInput(_ view: NSView) -> Bool {
        if view is NSTextField { return true }
        return view.subviews.contains(where: containsTextInput)
    }

    private static func monthHeight() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .idleWithHistory, accurateUsage: true)
            defer { FixtureFactory.cleanUp() }
            store.refreshReview(period: .month)
            let navigation = MainWindowModel(storyScope: .month, store: store)

            @MainActor func renderedHeight(width: CGFloat) -> CGFloat {
                let view = MonthStoryGrid(store: store, navigation: navigation)
                    .frame(width: width)
                    .fixedSize(horizontal: false, vertical: true)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 1
                return renderer.nsImage?.size.height ?? .infinity
            }

            let minimum = renderedHeight(width: 600)
            let comfortable = renderedHeight(width: 780)
            var failures: [String] = []
            if !minimum.isFinite || !comfortable.isFinite {
                failures.append("Month could not be rendered at both supported Story widths")
            } else if comfortable > minimum + 8 {
                failures.append("Widening Month increased its height from "
                                + "\(Int(minimum))pt to \(Int(comfortable))pt")
            }
            if max(minimum, comfortable) > 500 {
                failures.append("Six-row Month leaves too little room for its inline story")
            }
            return failures
        }
    }

    private static func monthDurationText() -> [String] {
        var failures: [String] = []
        if MonthStoryLayout.durationLabel(for: 31) != "31s" {
            failures.append("A 31-second Month cell was rounded to a whole-minute label")
        }
        for value in [TimeInterval.nan, .infinity, -.infinity, -1] {
            if MonthStoryLayout.durationLabel(for: value) != "—" {
                failures.append("An invalid Month-cell duration was presented as ordinary time")
                break
            }
        }
        return failures
    }

    private static func railArrangement() -> [String] {
        let original = StoryTileKind.allCases
        let arrangement = StoryRailArrangement(order: original)
        var failures: [String] = []
        if arrangement.allowsDrag || arrangement.move(.apps, by: -1)
            || arrangement.order != original {
            failures.append("Ordinary reading mode accepted a tile reorder")
        }
        arrangement.begin()
        if !arrangement.allowsDrag || !arrangement.move(.apps, by: -1)
            || arrangement.order != [.focus, .apps, .mac, .rhythm, .streak] {
            failures.append("Arranging mode did not move Apps exactly one position")
        }
        arrangement.finish()
        if arrangement.isArranging || arrangement.move(.apps, by: -1) {
            failures.append("Finish arranging did not gate subsequent movement")
        }
        arrangement.begin()
        arrangement.escape()
        if arrangement.isArranging {
            failures.append("Escape did not finish arranging")
        }
        arrangement.begin()
        arrangement.reset()
        if arrangement.order != StoryTileKind.allCases {
            failures.append("Reset did not restore the shipped tile order")
        }
        let suite = "com.prabesh.focuscontinuity.rail-order.\(UUID().uuidString)"
        if let defaults = UserDefaults(suiteName: suite) {
            defer { defaults.removePersistentDomain(forName: suite) }
            let persistence = PersistenceStore(defaults: defaults)
            let settings = SettingsModel(store: persistence, isTrackingEnabled: true,
                                         onChange: {}, onTrackingChanged: { _ in })
            arrangement.finish()
            arrangement.begin()
            _ = arrangement.move(.apps, by: -1)
            settings.storyTileOrder = arrangement.order
            let reloaded = SettingsModel(store: persistence, isTrackingEnabled: true,
                                         onChange: {}, onTrackingChanged: { _ in })
            if reloaded.storyTileOrder != arrangement.order {
                failures.append("The production Settings boundary did not persist arranged order")
            }
        } else {
            failures.append("Could not create isolated rail-order defaults")
        }
        return failures
    }

    private static func scopeKeyboard() -> [String] {
        var failures: [String] = []
        if StoryScopeKeyboardSelection.apply(.right, to: .day) != .week
            || StoryScopeKeyboardSelection.apply(.right, to: .month) != .month
            || StoryScopeKeyboardSelection.apply(.left, to: .week) != .day
            || StoryScopeKeyboardSelection.apply(.home, to: .month) != .day
            || StoryScopeKeyboardSelection.apply(.end, to: .day) != .month {
            failures.append("Left, Right, Home or End produced the wrong selected scope")
        }
        if StoryScopeKeyboardSelection.accessibilityValue(for: .week) != "Week, selected" {
            failures.append("The coherent scope target did not expose its selected value")
        }
        return failures
    }

    private final class ScopeSelectionBox {
        var value: StoryScope = .day
        var writes = 0
    }

    private static func nativeScopeAdapter() -> [String] {
        MainActor.assumeIsolated {
            let box = ScopeSelectionBox()
            let selection = Binding<StoryScope>(
                get: { box.value },
                set: { box.value = $0; box.writes += 1 })
            let host = NSHostingView(rootView: NativeStoryScopeControl(selection: selection)
                .frame(width: 190, height: AccessibilityMetrics.minimumTargetSize))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 220, height: 60),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            host.frame = window.contentView?.bounds ?? .zero
            host.layoutSubtreeIfNeeded()
            guard let control = embeddedScopeControl(in: host) else {
                window.contentView = nil
                return ["Could not locate the native Story scope control"]
            }
            var failures: [String] = []
            if !window.makeFirstResponder(control) || window.firstResponder !== control {
                failures.append("The native scope control could not become the coherent first responder")
            }
            control.updateIntegratedFocusCue()
            if control.focusRingType != .none || control.layer?.borderWidth != 2 {
                failures.append("The native outer ring was not replaced by the integrated focus cue")
            }

            box.writes = 0
            control.onKeyboardSelection?(.right)
            if box.value != .week || box.writes != 1 || control.selectedSegment != 1 {
                failures.append("The real Right-key adapter path did not select Week exactly once")
            }

            box.writes = 0
            control.selectedSegment = 2
            control.sendAction(control.action, to: control.target)
            if box.value != .month || box.writes != 1 {
                failures.append("The real pointer/action path did not select Month exactly once")
            }
            if control.accessibilityValue() as? String != "Month, selected" {
                failures.append("The native target did not expose its current selected value")
            }
            window.contentView = nil
            return failures
        }
    }

    @MainActor private static func embeddedScopeControl(in view: NSView)
        -> StoryScopeNSSegmentedControl? {
        if let control = view as? StoryScopeNSSegmentedControl { return control }
        for child in view.subviews {
            if let control = embeddedScopeControl(in: child) { return control }
        }
        return nil
    }

    private static func awayReturnScope() -> [String] {
        var failures: [String] = []
        if AwayAnswerDefaultAction.installsShortcut(focus: nil, reasonHasText: false) {
            failures.append("Return outside the question still activates an away answer")
        }
        if AwayAnswerDefaultAction.installsShortcut(focus: .reason, reasonHasText: true) {
            failures.append("Return in the reason editor still activates the default break button")
        }
        if !AwayAnswerDefaultAction.installsShortcut(
            focus: .answer(.tookBreak), reasonHasText: false) {
            failures.append("The focused break answer lost its local Return route")
        }
        return failures
    }

    private static func generalFailurePresentation() -> [String] {
        MainActor.assumeIsolated {
            let store = FixtureFactory.store(for: .running)
            defer { FixtureFactory.cleanUp() }
            let origin = (store.engine.activeThreadID, store.engine.sessionStartDate)
            store.publishCorrectionError("The original Stop could not be saved.")
            store.correctionRetry = .ending(threadID: origin.0, sessionStart: origin.1)
            guard let failure = store.focusOperationFailure else {
                return ["A general finalisation failure disappeared from compact Focus consumers"]
            }
            var failures: [String] = []
            if failure.message != "The original Stop could not be saved."
                || !failure.hasOriginBoundRetry {
                failures.append("Compact Focus did not retain the error and its origin-bound Retry")
            }
            let pending = FixtureFactory.store(for: .needsResolution)
            if let id = pending.engine.pendingDecisionID {
                pending.publishCorrectionError("The answer was not saved.")
                pending.correctionRetry = .awayDecision(.tookBreak, label: "walk",
                                                        reviewing: false, expectedID: id)
            }
            if pending.pendingAwaySaveError == nil || pending.focusOperationFailure != nil {
                failures.append("A pending-away question duplicated its save error as a general failure")
            }
            return failures
        }
    }
}
