import AppKit
import Combine
import SwiftUI

/// What the Edit menu's Undo and Redo need, republished only when it changes.
/// The store publishes every second while a session runs; observed directly,
/// the menu would be rebuilt every second.
///
/// The words and the enabled state are read from the app as it is (store, key
/// window, first responder, undo managers), so they follow focus as well as
/// the store. A stale answer can only mislabel the item: pressing it reads the
/// app again before it acts. Until the first read it is the system's plain
/// Undo and Redo, so a failure here leaves ⌘Z as it was.
final class EditCommandState: ObservableObject {
    @Published private(set) var items = EditUndo.Items()
    /// The main window, told by `EditUndoWindowAnchor`.
    weak var mainWindow: NSWindow? { didSet { refresh() } }
    private var store: SessionStore?
    private var watching: [AnyCancellable] = []
    private var responderWatch: AnyCancellable?

    /// Called from the commands' body, once the store exists.
    func bind(_ store: SessionStore) {
        guard self.store !== store else { return }
        self.store = store
        let center = NotificationCenter.default
        let changes: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
            NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
            .NSUndoManagerDidCloseUndoGroup, .NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange,
        ]
        Publishers.Merge(Publishers.MergeMany(changes.map { center.publisher(for: $0).map { _ in () } }),
                         store.objectWillChange.map { _ in () })
            // `objectWillChange` fires before the new value lands; the hop to
            // the main queue reads it after.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &watching)
        // Focus moving inside the key window changes who ⌘Z belongs to. The
        // window already key at launch gets no notification, so it is watched
        // now; every later one when it becomes key.
        watchResponder(of: NSApp?.keyWindow)
        center.publisher(for: NSWindow.didBecomeKeyNotification)
            .sink { [weak self] note in self?.watchResponder(of: note.object as? NSWindow) }
            .store(in: &watching)
        // Bound from a body: publish after it, not during it.
        DispatchQueue.main.async { [weak self] in self?.refresh() }
    }

    private func watchResponder(of window: NSWindow?) {
        responderWatch = window?.publisher(for: \.firstResponder)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        guard let store else { return }
        let next = EditUndo.items(store.editUndoKind, EditUndo.context(mainWindow: mainWindow))
        if next != items { items = next }
    }

    func performUndo() {
        guard let store else { return EditUndo.forward("undo:") }
        EditUndo.performUndo(on: store, context: EditUndo.context(mainWindow: mainWindow)) {
            EditUndo.forward("undo:")
        }
        refresh()
    }

    func performRedo() {
        EditUndo.forward("redo:")
    }
}

/// Edit > Undo and Redo. Undo reverses the newest correction, as the day
/// story's Undo banner does, unless text is being edited, which keeps its own
/// undo. Redo is left to the system, which has nothing for a correction: see
/// `EditUndo`.
struct EditCommands: Commands {
    let store: SessionStore
    @ObservedObject var state: EditCommandState

    var body: some Commands {
        let _ = state.bind(store)
        CommandGroup(replacing: .undoRedo) {
            Button(state.items.undoTitle) { state.performUndo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!state.items.undoEnabled)
            Button(state.items.redoTitle) { state.performRedo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!state.items.redoEnabled)
        }
    }
}

/// Tells the commands which window is the main one, so a correction is never
/// undone from Settings or a panel, whose Undo belongs to what they show.
struct EditUndoWindowAnchor: NSViewRepresentable {
    let state: EditCommandState

    func makeNSView(context: Context) -> Anchor {
        let anchor = Anchor()
        anchor.state = state
        return anchor
    }

    func updateNSView(_ nsView: Anchor, context: Context) { nsView.state = state }

    final class Anchor: NSView {
        weak var state: EditCommandState?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Resting takes this view out of its window; the window is still
            // the main one when it returns.
            guard let window else { return }
            DispatchQueue.main.async { [weak self] in self?.state?.mainWindow = window }
        }
    }
}
