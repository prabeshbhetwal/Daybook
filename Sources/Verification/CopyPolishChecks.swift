import Foundation
import SwiftUI

/// The final copy pass: button and menu labels read in Title Case, a released
/// control settles without bounce, the first-run tour names things the way the
/// rest of the app does, and a refusal says what to do next.
enum CopyPolishChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("A released control pops back once, and something closing does not bounce", releaseDoesNotBounce),
        ("Button and menu labels that checks can reach are in Title Case", labelsAreTitleCase),
        ("The title-case rule keeps small words down and capitalises the rest", titleCaseRule),
        ("The first-run tour uses one term per concept and Settings › Page paths", tourTerminology),
        ("A backup refused for want of a destination says how to fix it", backupRefusalNamesAStep),
    ]

    /// AP style: a, an, the, and, or, to, of, in, on, at, for, by, with and
    /// as stay lower case unless first or last. A number, a symbol and a unit
    /// ("min") are left as they are. A word before "…" is not last.
    static func isTitleCase(_ text: String) -> Bool {
        let small: Set<String> = ["a", "an", "the", "and", "or", "to", "of", "in", "on", "at", "for", "by", "with", "as"]
        let words = text.split(separator: " ").map(String.init)
        for (index, word) in words.enumerated() {
            let core = word.trimmingCharacters(in: .punctuationCharacters.union(.symbols))
            guard let first = core.first, first.isLetter, core != "min" else { continue }
            // A word before an ellipsis is not last: the title goes on in a dialog or submenu.
            let edge = index == 0 || (index == words.count - 1 && !word.hasSuffix("…"))
            if small.contains(core.lowercased()) && !edge {
                if core != core.lowercased() { return false }
            } else if !first.isUppercase {
                return false
            }
        }
        return true
    }

    private static func titleCaseRule() -> [String] {
        var problems: [String] = []
        for good in ["Start Focus", "Take a Break", "Go to Date…", "Count as Focus in…", "Remind Me in 15 min",
                     "Pause or Resume", "Take a Break, or End It", "Not Now", "Show 2 More", "+5 min", "I'm Back"] {
            expect(isTitleCase(good), "“\(good)” should pass the title-case rule", &problems)
        }
        for bad in ["Start focus", "Take a break", "Jump to date", "Add Note to the day", "Try again", "Show 2 more", "Count as Focus In…"] {
            expect(!isTitleCase(bad), "“\(bad)” should fail the title-case rule", &problems)
        }
        return problems
    }

    private static func releaseDoesNotBounce() -> [String] {
        var problems: [String] = []
        expect(Tokens.Motion.release == Animation.spring(response: 0.32, dampingFraction: 0.6),
               "release should pop back once (response 0.32, damping 0.6)", &problems)
        expect(Tokens.Motion.dismiss == Animation.spring(response: 0.26, dampingFraction: 1.0),
               "something closing should not bounce (damping 1.0)", &problems)
        return problems
    }

    private static func labelsAreTitleCase() -> [String] {
        var problems: [String] = []
        func check(_ labels: [String], from source: String) {
            for label in labels {
                expect(isTitleCase(label), "\(source) label “\(label)” is not in Title Case", &problems)
            }
        }
        let cards = FirstRunScript.chapters.flatMap(\.cards)
        check(cards.map(\.forward) + cards.compactMap(\.waiting), from: "tour")

        let prompts = [BreakPrompt(tier: .cognitive, worked: 50 * 60, appName: nil),
                       BreakPrompt(tier: .ultradian, worked: 90 * 60, appName: nil)]
        check(prompts.flatMap { BreakHUDCopy.reminder($0).buttons.map(\.title) }, from: "break reminder")
        check(BreakHUDCopy.breakOver(threadName: nil).buttons.map(\.title)
              + BreakHUDCopy.breakOver(threadName: "Parser").buttons.map(\.title), from: "break over")

        let session: [SessionCardMenu.Item] = [.continueSession, .startAgain, .rename, .addNote, .editNote,
                                                .seeFullReport, .remove]
        check(session.map(\.title), from: "session card menu")
        check(HistoryRowMenu.items(isEmpty: false, isOpen: true).map(\.title)
              + HistoryRowMenu.items(isEmpty: false, isOpen: false).map(\.title), from: "History row menu")
        check(ActivityRuleMenu.items().map(\.title), from: "activity rule menu")
        check(CategoryRowMenu.items(isRetired: true, isBreak: false, isLastStartable: false).map(\.title)
              + CategoryRowMenu.items(isRetired: false, isBreak: false, isLastStartable: false).map(\.title),
              from: "category row menu")
        check(SettingsGroups.windowKeys.map(\.action), from: "keyboard list")
        return problems
    }

    private static func tourTerminology() -> [String] {
        var problems: [String] = []
        let banned = ["evidence", "application", "app usage", "app recording", "tracked", "logged", "work type",
                      "interval", "Jump to date", "Settings under", "authoritative", "canonical", "classification"]
        for card in FirstRunScript.chapters.flatMap(\.cards) {
            let text = [card.sentence, card.body, card.note, card.result, card.waiting, card.forward]
                .compactMap { $0 }.joined(separator: " ")
            for word in banned where text.localizedCaseInsensitiveContains(word) {
                problems.append("tour card “\(card.sentence)” says “\(word)”")
            }
        }
        let tour = FirstRunScript.chapters.flatMap(\.cards)
            .map { [$0.body, $0.note ?? ""].joined(separator: " ") }.joined(separator: " ")
        for path in ["Settings › Away", "Settings › Activities", "Settings › Sessions", "Settings › Privacy",
                     "Settings › General"] {
            expect(tour.contains(path), "the tour should name “\(path)”", &problems)
        }
        return problems
    }

    private static func backupRefusalNamesAStep() -> [String] {
        var problems: [String] = []
        let text = DataBackup.Failure.noDestination.errorDescription ?? ""
        expect(text.contains("Turn it on") && text.contains("choose a folder"),
               "the refusal should say how to fix it, got “\(text)”", &problems)
        return problems
    }
}
