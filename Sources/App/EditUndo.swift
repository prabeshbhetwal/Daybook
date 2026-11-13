import AppKit

/// Edit > Undo and Redo, which `EditCommands` draws.
///
/// ⌘Z reverses the newest correction, the one the day story's Undo banner
/// reverses, only when the main window is key, no text is being edited and the
/// window's own undo manager has nothing newer. Anything else is the system's:
/// typing in a field, and what a view registered on the window's undo manager
/// (History search's rescue), which goes first. The
/// system's own undo goes down the responder chain as `undo:`, which NSWindow
/// answers from its undo manager, so a forwarded ⌘Z behaves as it did before.
///
/// Redo is the system's alone: a correction, once undone, is not kept to redo.
enum EditUndo {
    /// What the app and the key window say at this moment.
    struct Context: Equatable {
        var inMainWindow = false
        /// A text field or text view that accepts typing has focus.
        var isEditingText = false
        /// The responder chain's undo manager, as the system's menu would word
        /// them; nil when it has nothing to undo or redo.
        var systemUndo: String?
        var systemRedo: String?
    }

    enum Route: Equatable {
        case correction(EditUndoKind)
        case system
        case nothing
    }

    /// Who handles ⌘Z. Text always keeps its own undo, even while a correction
    /// could be undone. What the window's own undo manager holds (History
    /// search's rescue) goes before a correction: it may be the newer of the
    /// two, and the correction is next once it is spent. Outside the main
    /// window the store is never reached.
    static func route(_ target: EditUndoKind?, _ context: Context) -> Route {
        if context.isEditingText || context.systemUndo != nil { return .system }
        if context.inMainWindow, let target { return .correction(target) }
        return .nothing
    }

    /// The two menu items, derived from the store and the context alone.
    struct Items: Equatable {
        var undoTitle = "Undo"
        var undoEnabled = true
        var redoTitle = "Redo"
        var redoEnabled = true
    }

    static func items(_ target: EditUndoKind?, _ context: Context) -> Items {
        var items = Items()
        switch route(target, context) {
        case .correction(let kind): items.undoTitle = kind.menuTitle
        case .system: items.undoTitle = context.systemUndo ?? "Undo"
        case .nothing: items.undoEnabled = false
        }
        // Text can always be asked: it knows its own history.
        items.redoEnabled = context.isEditingText || context.systemRedo != nil
        items.redoTitle = context.systemRedo ?? "Redo"
        return items
    }

    /// Whether `responder` is somewhere the person is typing. A selectable
    /// but read-only text view is not: it has no text history to protect.
    static func isEditingText(_ responder: NSResponder?) -> Bool {
        if let text = responder as? NSText { return text.isEditable }
        if let field = responder as? NSTextField { return field.isEditable }
        return false
    }

    /// Runs ⌘Z. The correction is undone once, by the store's own undo, or the
    /// system's undo is asked; never both. Returns who handled it.
    @discardableResult
    static func performUndo(on store: SessionStore, context: Context,
                            forwardToSystem: () -> Void) -> Route {
        let chosen = route(store.editUndoKind, context)
        switch chosen {
        case .correction: store.performEditUndo()
        case .system: forwardToSystem()
        case .nothing: break
        }
        return chosen
    }

    // MARK: - The live app

    static func context(mainWindow: NSWindow?) -> Context {
        let key = NSApp?.keyWindow
        let manager = (key?.firstResponder ?? key)?.undoManager
        return Context(inMainWindow: key != nil && key === mainWindow,
                       isEditingText: isEditingText(key?.firstResponder),
                       systemUndo: manager?.canUndo == true ? manager?.undoMenuItemTitle : nil,
                       systemRedo: manager?.canRedo == true ? manager?.redoMenuItemTitle : nil)
    }

    /// The same action the standard Edit menu sends, down the responder chain.
    static func forward(_ action: String) {
        _ = NSApp?.sendAction(Selector((action)), to: nil, from: nil)
    }
}
