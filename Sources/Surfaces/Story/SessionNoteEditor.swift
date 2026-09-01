import SwiftUI

private final class SessionNoteEditorState: ObservableObject {
    @Published var confirmsDiscard = false
}

/// A record-scoped plain-text editor. Draft ownership remains in SessionStore,
/// so collapsing the row or navigating away cannot silently erase the text.
struct SessionNoteEditor: View {
    @ObservedObject var store: SessionStore
    let recordID: UUID
    @FocusState private var isFocused: Bool
    @StateObject private var state = SessionNoteEditorState()

    private var draft: Binding<String> {
        Binding(get: { store.noteDraft(for: recordID) },
                set: { store.setNoteDraft($0, for: recordID) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            TextEditor(text: draft)
                .font(Tokens.Typography.metadata)
                .frame(minHeight: 64, maxHeight: 112)
                .focused($isFocused)
                .accessibilityLabel("Session note")
            if let error = store.noteError(for: recordID) {
                Text(error).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Tokens.Space.s) {
                saveButton
                Button("Cancel") {
                    if !store.cancelNoteEditing(for: recordID) { state.confirmsDiscard = true }
                }
                .font(Tokens.Typography.metadata)
            }
        }
        .onAppear { isFocused = true }
        .onChange(of: isFocused) { focused in
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

    @ViewBuilder private var saveButton: some View {
        if isFocused {
            Button("Save") { _ = store.saveFocusedNote() }
                .keyboardShortcut(.return, modifiers: .command)
                .font(Tokens.Typography.metadata.weight(.semibold))
        } else {
            Button("Save") { _ = store.saveNote(for: recordID) }
                .font(Tokens.Typography.metadata.weight(.semibold))
        }
    }
}
