import Foundation

/// The day's Expand All link: it offers to close rows whenever any is open.
enum StoryExpandAllChecks: CheckSuite {
    static let tests: [(String, () -> [String])] = [
        ("Expand All turns into Collapse All as soon as any row is open", closesWhenAnyIsOpen),
    ]

    private static func closesWhenAnyIsOpen() -> [String] {
        var problems: [String] = []
        let ids = ["a", "b", "c"]
        expect(!StoryExpandAllControl.closes(ids, open: []), "with nothing open it still says Collapse All", &problems)
        expect(StoryExpandAllControl.closes(ids, open: ["b"]), "with one open it does not say Collapse All", &problems)
        expect(StoryExpandAllControl.closes(ids, open: ["a", "c"]), "with two of three open it does not say Collapse All", &problems)
        expect(StoryExpandAllControl.closes(ids, open: Set(ids)), "with all open it does not say Collapse All", &problems)
        // A row that is open but not in the link's list does not count.
        expect(!StoryExpandAllControl.closes(ids, open: ["z"]), "an unrelated open row makes it say Collapse All", &problems)
        expect(!StoryExpandAllControl.closes([], open: ["a"]), "with no rows it says Collapse All", &problems)
        return problems
    }
}
