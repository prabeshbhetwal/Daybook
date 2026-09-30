import Combine
import SwiftUI

/// The Session menu's shortcuts, named once so the buttons' tooltips cannot
/// drift from the menu. Option-Command keeps clear of the ⌘-digit and ⌘F
/// routes in Navigate and of the standard ⌘P, ⌘S and ⌘A.
enum SessionShortcut {
    case start
    case pauseOrResume
    case stepAway
    case stop

    var shortcut: KeyboardShortcut { KeyboardShortcut(key, modifiers: [.command, .option]) }

    /// As the menu draws it, for tooltips.
    var glyphs: String { "⌥⌘" + String(key.character).uppercased() }

    private var key: KeyEquivalent {
        switch self {
        case .start: return "n"
        case .pauseOrResume: return "p"
        case .stepAway: return "a"
        case .stop: return "s"
        }
    }
}

/// What the Session menu needs, republished only when it changes. The store
/// publishes every second while a session runs; observed directly, it would
/// rebuild the menu bar's items every second for nothing.
final class SessionCommandState: ObservableObject {
    struct Snapshot: Equatable {
        let mode: FocusSurfaceMode
        let isAway: Bool

        init(_ store: SessionStore) {
            mode = store.focusSurfaceComposition.mode
            isAway = store.isAway
        }
    }

    @Published private(set) var snapshot: Snapshot

    init(store: SessionStore) {
        snapshot = Snapshot(store)
        // `objectWillChange` fires before the new value lands; the hop to the
        // main queue reads it after.
        store.objectWillChange
            .receive(on: DispatchQueue.main)
            .compactMap { [weak store] _ in store.map(Snapshot.init) }
            .removeDuplicates()
            .assign(to: &$snapshot)
    }
}

/// Session control from the keyboard. Without Full Keyboard Access the
/// hero's buttons cannot be reached with Tab, so these are the way a
/// keyboard-only reader starts, pauses and ends a session. The app is an
/// LSUIElement and never shows a menu bar, so the menu itself is not seen:
/// it exists for its key equivalents, which the buttons' tooltips name. Each item runs the
/// same store action as its button and is disabled exactly when that button
/// is not shown.
struct SessionCommands: Commands {
    let store: SessionStore
    @ObservedObject var state: SessionCommandState

    private var mode: FocusSurfaceMode { state.snapshot.mode }
    private var isLive: Bool { mode == .running || mode == .paused || mode == .watching }

    var body: some Commands {
        CommandMenu("Session") {
            Button("Start focus") { store.performFocusPrimaryAction() }
                .keyboardShortcut(SessionShortcut.start.shortcut)
                .disabled(mode != .idle)
            Button(pauseOrResumeTitle) { store.performFocusPrimaryAction() }
                .keyboardShortcut(SessionShortcut.pauseOrResume.shortcut)
                .disabled(!isLive)
            Button("Away") { store.markAway() }
                .keyboardShortcut(SessionShortcut.stepAway.shortcut)
                .disabled(mode != .running)
            Divider()
            Button("Stop") { store.stop() }
                .keyboardShortcut(SessionShortcut.stop.shortcut)
                .disabled(!isLive)
        }
    }

    /// The hero's filled button in the same state says the same word.
    private var pauseOrResumeTitle: String {
        switch mode {
        case .paused, .watching: return state.snapshot.isAway ? "I'm back" : "Resume"
        default: return "Pause"
        }
    }
}
