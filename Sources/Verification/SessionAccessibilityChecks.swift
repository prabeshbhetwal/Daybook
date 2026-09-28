import AppKit
import SwiftUI

/// What the session surfaces say to someone who cannot see them, and the
/// keyboard route to the controls. These break if the menu bar item stops
/// speaking its marks, the praise panel stops saying where its Undo is, the
/// Session menu's shortcuts collide, or History's range goes nameless.
enum SessionAccessibilityChecks {
    static let tests: [(String, () -> [String])] = [
        ("The menu bar item speaks its marks and holds still within a minute", menuBarSpeaksMarks),
        ("The praise panel's spoken line says where its Undo also lives", hudSpokenLine),
        ("The Session menu's shortcuts are distinct and leave Navigate's alone", sessionShortcutsDistinct),
        ("History's range control names a span picked on the calendar", scopeNamesCustomSpan)
    ]

    private static func menuBarSpeaksMarks() -> [String] {
        MainActor.assumeIsolated {
            var failures: [String] = []
            let goal = GoalProgress(goal: 14_400, achieved: 7_200, typical: nil)
            let met = GoalProgress(goal: 3_600, achieved: 3_700, typical: nil)
            func label(_ state: SessionState, _ elapsed: TimeInterval,
                       attention: Bool = false, goal: GoalProgress = goal) -> String {
                MenuBarDisplay(state: state, elapsed: elapsed, needsAttention: attention,
                               goal: goal, showsTime: true).accessibilityLabel
            }
            if label(.running, 5) != label(.running, 45) || !label(.running, 5).contains("under a minute") {
                failures.append("The first minute is not spoken as one steady value: \(label(.running, 5))")
            }
            if !label(.running, 750).contains("Running, 12 minutes") {
                failures.append("A running session is not said to be running: \(label(.running, 750))")
            }
            if !label(.paused(reason: .manual), 750).contains("Paused, 12 minutes") {
                failures.append("A paused session is not said to be paused: \(label(.paused(reason: .manual), 750))")
            }
            if !label(.running, 750, attention: true).contains("Away question waiting") {
                failures.append("A waiting question is not spoken")
            }
            if !label(.running, 750, goal: met).contains("Daily goal met") {
                failures.append("A met goal is not spoken")
            }
            return failures
        }
    }

    private static func hudSpokenLine() -> [String] {
        MainActor.assumeIsolated {
            var failures: [String] = []
            let plain = RewardHUD.spoken(title: "Goal reached", detail: "Four hours today.", hasUndo: false)
            if plain != "Goal reached. Four hours today." {
                failures.append("A praise line was not spoken as two sentences: \(plain)")
            }
            let undoable = RewardHUD.spoken(title: "Writing session started",
                                            detail: "Writing after 90 seconds in the assigned application",
                                            hasUndo: true)
            if !undoable.contains("application. To undo it")
                || !undoable.contains("Undo automatic session") || !undoable.hasSuffix(".") {
                failures.append("An undoable notice did not say where else Undo is: \(undoable)")
            }
            return failures
        }
    }

    private static func sessionShortcutsDistinct() -> [String] {
        let all: [SessionShortcut] = [.start, .pauseOrResume, .stepAway, .stop]
        let glyphs = all.map(\.glyphs)
        var failures: [String] = []
        if Set(glyphs).count != glyphs.count {
            failures.append("Two Session commands share a shortcut: \(glyphs)")
        }
        // Option-Command only: plain ⌘ letters and digits belong to the
        // standard menus and Navigate.
        for shortcut in all where shortcut.shortcut.modifiers != [.command, .option] {
            failures.append("\(shortcut.glyphs) is not an Option-Command chord")
        }
        return failures
    }

    private static func scopeNamesCustomSpan() -> [String] {
        MainActor.assumeIsolated {
            let host = NSHostingView(rootView: NativeScopeControl(titles: ["7 days", "30 days"],
                                                                  selectedIndex: .constant(-1),
                                                                  controlLabel: "History range")
                .frame(width: 190, height: AccessibilityMetrics.minimumTargetSize))
            host.frame = NSRect(x: 0, y: 0, width: 220, height: 60)
            host.layoutSubtreeIfNeeded()
            func control(in view: NSView) -> ScopeNSSegmentedControl? {
                if let found = view as? ScopeNSSegmentedControl { return found }
                return view.subviews.lazy.compactMap(control(in:)).first
            }
            guard let found = control(in: host) else { return ["Could not locate the scope control"] }
            let value = found.accessibilityValue() as? String
            return value == "Custom span" ? [] : ["A calendar span was spoken as \(value ?? "nothing")"]
        }
    }
}
