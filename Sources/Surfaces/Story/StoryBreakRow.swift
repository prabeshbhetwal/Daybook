import SwiftUI

private final class BreakChangeDraft: ObservableObject {
    @Published var confirming = false
    var decision: UserDecision = .continueSession
    var target: SessionRecord?
    var original: SessionRecord?
}

/// Every recorded break, one row, whichever way it was recorded: its name and
/// length, a way to name it, a way to change how it counts, and Undo when the
/// break was an answer to the away question. Rest is not work, so it is a
/// quiet row rather than a card, and never coloured like a session.
///
/// A break the away question recorded is changed by re-answering that
/// question: counted into the session the absence interrupted, or left
/// uncounted. Any other break is reclassified in place, into any of its
/// day's sessions, with the real break kept as the reversible before-state.
///
/// The store publishes every second while anything is live, and a menu whose
/// view is redrawn while it is open loses the item under the pointer. So the
/// store is held, not observed, and the row redraws only when what it shows
/// changes. Place it with `.equatable()`.
struct StoryBreakRow: View, Equatable {
    let store: SessionStore
    let rest: RestEntry
    /// The away answer that recorded this break, when it was one.
    let receipt: AwayDecisionReceipt?
    /// The archive's revision, so the targets and names follow a change to it.
    let archiveRevision: Int
    let isBlocked: Bool
    let canUndo: Bool
    @StateObject private var draft = BreakChangeDraft()
    @StateObject private var editing = BoolBox()
    @StateObject private var nameDraft = TextBox()
    @FocusState private var nameFocused: Bool
    @FocusState private var nameButtonFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(store: SessionStore, rest: RestEntry, receipt: AwayDecisionReceipt? = nil) {
        self.store = store
        self.rest = rest
        self.receipt = receipt
        archiveRevision = store.evidenceRevision.sessions
        isBlocked = store.hasUnresolvedAwayDecision
        canUndo = receipt.map { store.engine.canUndoAwayDecision(expectedID: $0.id) } ?? false
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.store === rhs.store && lhs.rest == rhs.rest && lhs.receipt == rhs.receipt
            && lhs.archiveRevision == rhs.archiveRevision && lhs.isBlocked == rhs.isBlocked
            && lhs.canUndo == rhs.canUndo
    }

    /// An unnamed break is already called one; only a name the user gave is
    /// worth putting before the explanation.
    static func label(_ name: String) -> String {
        name.isEmpty || name == "Break"
            ? "Recorded break, not counted as focus"
            : "\(name) — recorded break, not counted as focus"
    }

    /// The name the user gave, or nil while it is the default.
    private var name: String? {
        let trimmed = rest.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "Break" ? nil : trimmed
    }

    private var canName: Bool {
        receipt.map(store.canNameBreak(for:)) ?? (store.legacyBreakRecord(id: rest.id) != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            HStack(spacing: Tokens.Space.m) {
                Text(Self.label(rest.name))
                    .font(Tokens.Typography.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Tokens.Space.s)
                Text(durations: Tokens.preciseDuration(rest.length))
                    .font(Tokens.Typography.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                if canName, !editing.value { nameButton }
                changeMenu
                if receipt != nil { undoButton }
            }
            if editing.value {
                nameField
                    .transition(Tokens.Motion.transition(Tokens.Motion.unfold, reduceMotion: reduceMotion))
            }
        }
        .padding(.horizontal, Tokens.Space.m)
        .padding(.vertical, Tokens.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Colour.elevated,
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
        .onExitCommand { if editing.value { closeNameField() } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(Self.label(rest.name)), \(Tokens.spent(rest.length)), "
                            + Tokens.timeRange(rest.start, rest.end))
        .confirmationDialog("Change this recorded interval?", isPresented: $draft.confirming,
                            titleVisibility: .visible) {
            Button(draft.decision == .mergeTime ? "Count as focus" : "Leave uncounted", action: perform)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(scopeMessage)
        }
    }

    // MARK: - Name

    private var nameButton: some View {
        Button(name == nil ? "Name it" : "Rename") {
            nameDraft.text = name ?? ""
            withAnimation(Tokens.Motion.animation(Tokens.Motion.reveal, reduceMotion: reduceMotion)) {
                editing.value = true
            }
        }
        .buttonStyle(StoryLinkStyle())
        .font(Tokens.Typography.label)
        .frame(minHeight: 28.zoomed)
        .disabled(isBlocked)
        .help(isBlocked ? StoryDecisionRow.awayQuestionFirst : "")
        .accessibilityLabel(name == nil ? "Name this break" : "Rename \(name ?? "this break")")
        .focused($nameButtonFocused)
    }

    /// The away prompt's own field, for a break that was answered without it.
    private var nameField: some View {
        HStack(spacing: Tokens.Space.s) {
            Image(systemName: "pencil.line")
                .font(Tokens.Typography.label)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            TextField("Name it: dinner, a call, a walk", text: $nameDraft.text)
                .textFieldStyle(.plain)
                .font(Tokens.Typography.body)
                .onSubmit(saveName)
                .focused($nameFocused)
                .onAppear {
                    // The field must be installed before it can take focus;
                    // the "Name it" button that had it has just gone.
                    DispatchQueue.main.async {
                        if editing.value { nameFocused = true }
                    }
                }
                .accessibilityLabel("Break name")
            Button("Save", action: saveName)
                .buttonStyle(StoryLinkStyle())
                .padding(.leading, Tokens.Space.s)
                .font(Tokens.Typography.label)
                .disabled(nameDraft.text.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", action: closeNameField)
                .buttonStyle(StoryLinkStyle())
                .padding(.leading, Tokens.Space.s)
                .font(Tokens.Typography.body)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Tokens.Space.m)
        .frame(minHeight: 30.zoomed)
        .background(StoryStyle.canvas,
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.well, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.well, style: .continuous)
            .strokeBorder(Tokens.Colour.line))
    }

    private func saveName() {
        let text = nameDraft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let saved = receipt.map { store.nameBreak(for: $0, to: text) }
            ?? store.renameBreak(recordID: rest.id, to: text)
        if saved || text == name { closeNameField() }
    }

    /// Focus goes back to the button that opened the field, so a keyboard
    /// reader is not dropped at the top of the window.
    private func closeNameField() {
        nameFocused = false
        editing.value = false
        DispatchQueue.main.async { nameButtonFocused = true }
    }

    // MARK: - Change how it counts

    private var changeMenu: some View {
        Menu("Change how this counts") {
            Button("Leave uncounted") { choose(.continueSession) }
            if let receipt {
                Button("Count as focus in \(receipt.name.isEmpty ? "Unnamed session" : receipt.name) · "
                       + receipt.workType.displayName) {
                    choose(.mergeTime)
                }
            } else {
                let targets = store.legacyFocusTargets(for: rest)
                if targets.isEmpty {
                    Text("No focus session was recorded on this day.")
                    Text("You can still leave this interval uncounted.")
                } else {
                    Menu("Count as focus in…") {
                        ForEach(targets) { record in
                            Button(SessionStore.legacyFocusTargetLabel(record)) {
                                choose(.mergeTime, target: record)
                            }
                        }
                    }
                }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(isBlocked)
        .help(isBlocked ? StoryDecisionRow.awayQuestionFirst : "")
        .accessibilityLabel(name.map { "Change how \($0) counts" } ?? "Change how this break counts")
        .accessibilityHint(isBlocked ? StoryDecisionRow.awayQuestionFirst : "")
    }

    private func choose(_ decision: UserDecision, target: SessionRecord? = nil) {
        draft.decision = decision
        draft.target = target
        draft.original = store.legacyBreakRecord(id: rest.id)
        draft.confirming = true
    }

    private func perform() {
        if let receipt {
            store.changeBreak(receipt, to: draft.decision)
        } else {
            store.reclassifyLegacyBreak(recordID: rest.id, decision: draft.decision, focusTargetID: draft.target?.id,
                                        expectedRecord: draft.original, expectedTarget: draft.target)
        }
    }

    private var scopeMessage: String {
        guard let record = store.legacyBreakRecord(id: rest.id) else { return "This record is no longer available." }
        let full = receipt?.range ?? DateInterval(start: record.start, end: record.end)
        var text = "Changes the full \(Tokens.preciseDuration(full.duration)) recorded interval. "
        if draft.decision == .mergeTime {
            let sessionName = draft.target?.name ?? receipt?.name ?? ""
            if let type = draft.target?.workType ?? receipt?.workType {
                text += "Attribute it to \(sessionName.isEmpty ? "the unnamed session" : sessionName) "
                    + "as \(type.displayName). "
            }
        } else { text += "Its break classification will be removed, with no focus time added. " }
        if let note = StoryDecisionScope.note(visible: DateInterval(start: rest.start, end: rest.end), full: full) {
            text += note + " "
        }
        let undo = receipt == nil ? "Undo restores the original recorded break."
            : "Undo reopens the question for this interval, where you can call it a break again."
        return text + undo + " App-use evidence is unchanged."
    }

    // MARK: - Undo

    private var undoButton: some View {
        Button("Undo") {
            if let receipt { store.undoAwayDecision(expectedID: receipt.id) }
        }
        .buttonStyle(StoryLinkStyle())
        .font(Tokens.Typography.label)
        .foregroundStyle(StoryStyle.action)
        .frame(minWidth: 36.zoomed, minHeight: 28.zoomed)
        .disabled(!canUndo)
        .help(canUndo ? "" : StoryDecisionRow.awayQuestionFirst)
        .accessibilityLabel("Undo recorded as a break")
        .accessibilityHint(canUndo ? "Reopens the question for this interval; later work is unchanged."
                           : StoryDecisionRow.awayQuestionFirst)
    }
}
