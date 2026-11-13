import Foundation

/// What Edit > Undo would reverse, with the session it concerns, worded for
/// the menu. It is the correction the day story's Undo banner reverses, so the
/// two always agree. The newest correction may belong to another day, so the
/// menu says which session it is about.
enum EditUndoKind: Equatable {
    /// The name the session has now; empty when the name was cleared.
    case rename(String)
    case category(String)
    case removal(String)
    case awayAnswer(UserDecision)

    init(_ state: SessionStoreCorrectionState) {
        switch state.correction {
        case .rename(let now): self = .rename(now)
        case .workType: self = .category(state.originalFields.name)
        case .removed: self = .removal(state.originalFields.name)
        }
    }

    /// Longest session name the menu shows, ellipsis included.
    static let nameLimit = 24

    /// The whole Undo item: "Undo Rename “Planning”". The away answers use the
    /// words of the buttons that gave them.
    var menuTitle: String {
        switch self {
        case .rename(let name): return Self.title("Rename", of: name)
        case .category(let name): return Self.title("Change Category", of: name)
        case .removal(let name): return Self.title("Remove Session", of: name)
        case .awayAnswer(.tookBreak): return "Undo Break"
        case .awayAnswer(.mergeTime): return "Undo Count as Focus"
        case .awayAnswer(.continueSession), .awayAnswer(.resetTimer): return "Undo Leave Uncounted"
        }
    }

    /// Runs of white space become one space and a long name is cut, so the
    /// item stays one short line. No name leaves just the action.
    private static func title(_ action: String, of name: String) -> String {
        let flat = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !flat.isEmpty else { return "Undo \(action)" }
        let shown = flat.count > nameLimit ? String(flat.prefix(nameLimit - 1)) + "…" : flat
        return "Undo \(action) “\(shown)”"
    }
}

extension SessionStore {
    /// The newest thing Undo reverses: an away answer, or a saved field
    /// correction. One definition, so the menu and `undoLastCorrection()`
    /// cannot pick different ones.
    enum LastUndo {
        case awayAnswer
        case field(SessionStoreCorrectionState)
    }

    var lastUndo: LastUndo? {
        if engine.lastAwayDecision?.isResolved == true,
           (engine.lastAwayDecision?.sequence ?? 0) >= (lastCorrection?.sequence ?? 0) { return .awayAnswer }
        return lastCorrection.map(LastUndo.field)
    }

    /// What Edit > Undo can reverse right now; nil when it would do nothing.
    /// Stricter than `canUndoCorrection`: the away answer must be one the
    /// engine will take back (not while its question is waiting), and a
    /// read-only history refuses every write.
    var editUndoKind: EditUndoKind? {
        guard canUndoCorrection, !engine.archive.isReadOnly else { return nil }
        switch lastUndo {
        case .awayAnswer?:
            guard engine.canUndoAwayDecision, let decision = engine.lastAwayDecision?.decision else { return nil }
            return .awayAnswer(decision)
        case .field(let state)?:
            return EditUndoKind(state)
        case nil:
            return nil
        }
    }

    /// Edit > Undo: the same undo as the banner's button, once, and only when
    /// there is something the store can undo.
    @discardableResult
    func performEditUndo() -> Bool {
        guard editUndoKind != nil else { return false }
        return undoLastCorrection()
    }
}
