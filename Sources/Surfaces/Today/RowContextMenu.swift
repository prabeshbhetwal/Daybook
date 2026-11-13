import SwiftUI

/// One entry of a right-click menu. Each row kind lists its own entries as a
/// pure value, so what a menu offers can be checked without drawing it and the
/// view that shows it only maps an entry onto the call its visible button makes.
protocol RowMenuAction: Hashable {
    /// Title case, with an ellipsis where a dialog or an input follows.
    var title: String { get }
    var isDestructive: Bool { get }
}

extension RowMenuAction {
    var isDestructive: Bool { false }
}

extension Array where Element: RowMenuAction {
    /// True when every destructive entry comes after every other entry.
    var keepsDestructiveLast: Bool {
        guard let first = firstIndex(where: \.isDestructive) else { return true }
        return self[first...].allSatisfy(\.isDestructive)
    }
}

/// The entries of one menu, drawn in the order given. A destructive entry
/// carries `.destructive` and sits after a Divider, as the visible buttons do.
/// Used by `.contextMenu` and by an ellipsis `Menu` alike, so the two never
/// offer different things.
struct RowContextMenu<Action: RowMenuAction>: View {
    let items: [Action]
    let perform: (Action) -> Void

    var body: some View {
        ForEach(Array(items.enumerated()), id: \.element) { index, item in
            if item.isDestructive, index > 0, !items[index - 1].isDestructive { Divider() }
            Button(item.title, role: item.isDestructive ? .destructive : nil) { perform(item) }
        }
    }
}

/// What a session card in the day timeline offers. Every entry is a button
/// the open card already has, or the card's own toggle, so a closed card can
/// do what an open one can.
enum SessionCardMenu {
    enum Item: RowMenuAction {
        case continueSession, startAgain, rename, addNote, editNote, seeFullReport, remove

        var title: String {
            switch self {
            case .continueSession: "Continue Session"
            case .startAgain: "Start Again"
            case .rename: "Rename…"
            case .addNote: "Add Note…"
            case .editNote: "Edit Note…"
            case .seeFullReport: "See Full Report"
            case .remove: "Remove…"
            }
        }

        var isDestructive: Bool { self == .remove }
    }

    enum NoteState: Equatable { case unavailable, absent, present }

    /// What is true of the session and the card; each field is the condition
    /// the matching visible button is drawn or enabled under.
    struct Facts: Equatable {
        var isRunning = false
        var canRename = false
        var note = NoteState.unavailable
        var canContinue = false
        var canStartAgain = false
        var canSeeReport = false
        var canRemove = false
    }

    static func items(for facts: Facts) -> [Item] {
        var items: [Item] = []
        if facts.canContinue { items.append(.continueSession) }
        else if facts.canStartAgain { items.append(.startAgain) }
        if facts.canRename { items.append(.rename) }
        switch facts.note {
        case .absent: items.append(.addNote)
        case .present: items.append(.editNote)
        case .unavailable: break
        }
        if facts.canSeeReport { items.append(.seeFullReport) }
        // A session that is running is not removed from under itself.
        if facts.canRemove, !facts.isRunning { items.append(.remove) }
        return items
    }
}

/// What a History tree row offers: the one thing its header button does.
enum HistoryRowMenu {
    enum Item: RowMenuAction {
        case open, close
        var title: String { self == .open ? "Open" : "Close" }
    }

    /// An empty period has no body to open, and its header is disabled.
    static func items(isEmpty: Bool, isOpen: Bool) -> [Item] {
        isEmpty ? [] : [isOpen ? .close : .open]
    }
}

/// What an activity rule row offers: the items of its ellipsis menu.
enum ActivityRuleMenu {
    enum Item: RowMenuAction {
        case edit, duplicate, delete

        var title: String {
            switch self {
            case .edit: "Edit"
            case .duplicate: "Duplicate"
            case .delete: "Delete…"
            }
        }

        var isDestructive: Bool { self == .delete }
    }

    static func items() -> [Item] { [.edit, .duplicate, .delete] }
}

/// What a category row offers: Edit, which the row itself does, and the
/// Restore and Retire the open editor carries.
enum CategoryRowMenu {
    enum Item: RowMenuAction {
        case edit, restore, retire

        var title: String {
            switch self {
            case .edit: "Edit"
            case .restore: "Restore"
            case .retire: "Retire"
            }
        }

        var isDestructive: Bool { self == .retire }
    }

    /// Break cannot be retired, nor the last category that can start a session.
    static func items(isRetired: Bool, isBreak: Bool, isLastStartable: Bool) -> [Item] {
        var items: [Item] = [.edit]
        if isRetired { items.append(.restore) }
        else if !isBreak, !isLastStartable { items.append(.retire) }
        return items
    }
}
