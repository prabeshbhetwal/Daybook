import SwiftUI
import AppKit

private final class SessionNoteEditorState: ObservableObject {
    @Published var confirmsDiscard = false
    /// The note as it stood when the first words arrived (not when the button
    /// was pressed: permission can take a while); the transcript is added
    /// after it, not typed over it, and a note typed into since is left alone.
    var dictatedNote: DictationNote?
}

/// A record-scoped plain-text editor. Draft ownership remains in SessionStore,
/// so collapsing the row or navigating away cannot silently erase the text.
struct SessionNoteEditor: View {
    @ObservedObject var store: SessionStore
    let recordID: UUID
    @FocusState private var isFocused: Bool
    @StateObject private var state = SessionNoteEditorState()
    @StateObject private var dictation = SpeechDictation()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var draft: Binding<String> {
        Binding(get: { store.noteDraft(for: recordID) },
                set: { store.setNoteDraft($0, for: recordID) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            TextEditor(text: draft)
                .font(Tokens.Typography.body)
                .frame(minHeight: 64, maxHeight: 112)
                .focused($isFocused)
                .accessibilityLabel("Session note")
            if let error = store.noteError(for: recordID) {
                Text(error).font(Tokens.Typography.body).foregroundStyle(Tokens.Colour.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message = dictation.status.message {
                Label(message, systemImage: "mic.slash.fill")
                    .font(Tokens.Typography.body)
                    .foregroundStyle(Tokens.Colour.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Dictation error: \(message)")
                if let settings = dictation.status.privacySettings {
                    Button("Open Privacy Settings") { NSWorkspace.shared.open(settings) }
                        .buttonStyle(StoryLinkStyle())
                }
            }
            HStack(spacing: Tokens.Space.s) {
                saveButton
                cancelButton
                Spacer(minLength: Tokens.Space.s)
                dictateButton
            }
        }
        .announcesChanges(to: store.noteError(for: recordID))
        .announcesChanges(to: dictation.status.message.map { "Dictation error: \($0)" })
        .onAppear { isFocused = true }
        .onChange(of: isFocused) { _, focused in
            if focused { store.focusedNoteEditorID = recordID }
            else if store.focusedNoteEditorID == recordID { store.focusedNoteEditorID = nil }
        }
        .confirmationDialog("Discard unsaved note?", isPresented: $state.confirmsDiscard) {
            Button("Discard", role: .destructive) {
                _ = store.cancelNoteEditing(for: recordID, discardingChanges: true)
            }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("This note has not been saved.")
        }
    }

    /// One button that listens or stops. Words land in the note as they are
    /// recognised, after whatever was already written.
    private var dictateButton: some View {
        Button {
            if dictation.isBusy {
                dictation.stop()
            } else {
                state.dictatedNote = nil
                dictation.start()
            }
        } label: {
            HStack(spacing: Tokens.Space.xs) {
                if dictation.isListening {
                    Circle()
                        .fill(Tokens.Colour.danger)
                        .frame(width: 7, height: 7)
                        .modifier(ListeningPulse(reduceMotion: reduceMotion))
                }
                Label(dictation.isListening ? "Stop" : dictation.status == .requesting ? "Starting…" : "Dictate",
                      systemImage: dictation.isListening ? "stop.fill" : "mic.fill")
                    .labelStyle(.titleAndIcon)
            }
        }
        .font(Tokens.Typography.body)
        .tint(dictation.isListening ? Tokens.Colour.danger : nil)
        .disabled(!dictation.isSupported || dictation.status == .requesting)
        .help(dictation.isSupported
              ? "Speak this note. Words appear as they are recognised; press again to stop."
              : "Speech recognition is not available for your language on this Mac.")
        .accessibilityLabel(dictation.isListening ? "Stop dictating" : "Dictate note")
        .animation(Tokens.Motion.animation(Tokens.Motion.swap, reduceMotion: reduceMotion),
                   value: dictation.isListening)
        .onChange(of: dictation.transcript) { _, transcript in
            guard dictation.isListening else { return }
            // Typed into while listening: the reader's text stands, and the
            // words that would have gone over it end the dictation instead.
            var dictated = state.dictatedNote ?? DictationNote(startingFrom: draft.wrappedValue)
            guard let note = dictated.applying(transcript, to: draft.wrappedValue) else {
                dictation.stop()
                return
            }
            state.dictatedNote = dictated
            store.setNoteDraft(note, for: recordID)
        }
        .onDisappear { dictation.stop() }
    }

    @ViewBuilder private var saveButton: some View {
        if isFocused {
            Button("Save") { _ = store.saveFocusedNote() }
                .keyboardShortcut(.return, modifiers: .command)
                .font(Tokens.Typography.label)
        } else {
            Button("Save") { _ = store.saveNote(for: recordID) }
                .font(Tokens.Typography.label)
        }
    }

    /// Escape cancels, as Command-Return saves, only in the editor that has
    /// focus: two open notes must not both answer the one key.
    @ViewBuilder private var cancelButton: some View {
        if isFocused {
            Button("Cancel", action: cancel)
                .keyboardShortcut(.cancelAction)
                .font(Tokens.Typography.body)
        } else {
            Button("Cancel", action: cancel)
                .font(Tokens.Typography.body)
        }
    }

    private func cancel() {
        if !store.cancelNoteEditing(for: recordID) { state.confirmsDiscard = true }
    }
}

/// A soft breathing dot while the microphone is open. Still under Reduce
/// Motion; the red alone says it.
private struct ListeningPulse: ViewModifier {
    let reduceMotion: Bool
    @StateObject private var phase = BoolBox()

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion || !phase.value ? 1 : 0.35)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                       value: phase.value)
            .onAppear { phase.value = true }
    }
}
