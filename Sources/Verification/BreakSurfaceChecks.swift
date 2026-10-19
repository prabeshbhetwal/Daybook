import Foundation

/// What the break HUD says and offers. The copy is pure, so it is checked
/// here without a panel or a screen.
enum BreakSurfaceChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A reminder offers Later only while it may", reminderButtons),
        ("Break's over names the thread, or offers Done without one", breakOverCopy),
    ]

    private static func cognitive(canLater: Bool) -> BreakPrompt {
        var prompt = BreakPrompt(tier: .cognitive, worked: 50 * 60, appName: nil)
        prompt.canLater = canLater
        return prompt
    }

    private static func ultradian(canLater: Bool) -> BreakPrompt {
        var prompt = BreakPrompt(tier: .ultradian, worked: 90 * 60, appName: nil)
        prompt.canLater = canLater
        return prompt
    }

    private static func reminderButtons() -> [String] {
        var problems: [String] = []
        expect(BreakHUDCopy.reminder(cognitive(canLater: true)).buttons == ["Start break", "Later", "Skip"],
               "full set", &problems)
        expect(BreakHUDCopy.reminder(cognitive(canLater: false)).buttons == ["Start break", "Skip"],
               "no third Later", &problems)
        expect(BreakHUDCopy.reminder(ultradian(canLater: true)).buttons == ["Start break", "Remind me in 15 min"],
               "guard has no Skip", &problems)
        return problems
    }

    private static func breakOverCopy() -> [String] {
        var problems: [String] = []
        expect(BreakHUDCopy.breakOver(threadName: "Parser") == ("Break's over", "Back to Parser?", ["Resume", "+5 min"]),
               "with thread", &problems)
        expect(BreakHUDCopy.breakOver(threadName: nil).buttons == ["Done", "+5 min"],
               "without thread", &problems)
        return problems
    }
}
