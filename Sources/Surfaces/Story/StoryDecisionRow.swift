import SwiftUI

enum StoryDecisionScope {
    static func note(visible: DateInterval, full: DateInterval) -> String? {
        guard visible != full else { return nil }
        let calendar = Calendar.current
        let days = max(2, (calendar.dateComponents([.day],
            from: calendar.startOfDay(for: full.start),
            to: calendar.startOfDay(for: full.end.addingTimeInterval(-0.001))).day ?? 1) + 1)
        let scope = days == 2 ? "both days" : "all \(days) days"
        return "Changes apply to the full \(Tokens.preciseDuration(full.duration)) interval across \(scope)."
    }
}

struct StoryDecisionRow: View {
    @ObservedObject var store: SessionStore
    let receipt: AwayDecisionReceipt
    let range: DateInterval

    var body: some View {
        if receipt.isResolved {
            // A named break reads by its name; an unnamed one keeps the plain
            // statement and offers the field the away prompt has.
            let name = store.breakName(for: receipt)
            StorySavedActionRow(title: name ?? receipt.title, range: range,
                                kind: name == nil ? nil : "Break",
                                // A decision can be undone except while the
                                // away question is waiting for its answer.
                                undoBlockReason: store.engine.canUndoAwayDecision(expectedID: receipt.id)
                                    ? nil : Self.awayQuestionFirst,
                                scopeNote: StoryDecisionScope.note(visible: range, full: receipt.range),
                                currentName: name,
                                onName: store.canNameBreak(for: receipt)
                                    ? { store.nameBreak(for: receipt, to: $0) } : nil) {
                store.undoAwayDecision(expectedID: receipt.id)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("How should this interval be recorded?")
                    .font(Tokens.Typography.rowTitle)
                Text("\(Tokens.timeRange(range.start, range.end)) · \(Tokens.preciseDuration(range.duration)) is not counted. Later work is unchanged.")
                    .font(Tokens.Typography.metadata).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Count as focus") { answer(.mergeTime) }
                        .buttonStyle(StoryActionStyle(tint: StoryStyle.focus))
                    Button("Call it a break") { answer(.tookBreak) }
                        .buttonStyle(StoryActionStyle())
                    Button("Leave uncounted") { answer(.continueSession) }
                        .buttonStyle(StoryActionStyle())
                }
                .disabled(store.hasUnresolvedAwayDecision)
                .help(store.hasUnresolvedAwayDecision ? Self.awayQuestionFirst : "")
                .accessibilityHint(store.hasUnresolvedAwayDecision ? Self.awayQuestionFirst : "")
                if let note = StoryDecisionScope.note(visible: range, full: receipt.range) {
                    Text(note)
                        .font(Tokens.Typography.metadata).foregroundStyle(.secondary)
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tokens.Colour.attention.opacity(0.08), in: RoundedRectangle(cornerRadius: StoryStyle.entryRadius))
            .overlay(RoundedRectangle(cornerRadius: StoryStyle.entryRadius).strokeBorder(Tokens.Colour.attention.opacity(0.25)))
        }
    }

    private func answer(_ decision: UserDecision) {
        store.applyAwayDecision(decision, reviewing: true, expectedID: receipt.id)
    }

    /// Why a past interval's answers wait: the same words Remove uses.
    static let awayQuestionFirst = "Answer the away question first."
}

struct StorySavedActionRow: View {
    let title: String
    let range: DateInterval
    /// What the row is, when its title is a name rather than a statement.
    var kind: String?
    /// Set while Undo cannot act yet; the button says why.
    var undoBlockReason: String?
    var scopeNote: String?
    var currentName: String?
    /// Present when the row stands for a break that can be named.
    var onName: ((String) -> Bool)?
    let undo: () -> Void
    @StateObject private var editing = BoolBox()
    @StateObject private var draft = TextBox()
    @FocusState private var nameFocused: Bool
    @FocusState private var nameButtonFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 10) {
            Image(systemName: "checkmark").font(Tokens.Typography.metadata.weight(.semibold))
                .foregroundStyle(StoryStyle.successInk)
            Text(title).font(Tokens.Typography.metadata.weight(.semibold))
                .lineLimit(1)
            Text((kind.map { "\($0) · " } ?? "") + Tokens.timeRange(range.start, range.end))
                .font(Tokens.Typography.metadata).foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if onName != nil, !editing.value {
                Button(currentName == nil ? "Name it" : "Rename") {
                    draft.text = currentName ?? ""
                    withAnimation(Tokens.Motion.animation(Tokens.Motion.reveal, reduceMotion: reduceMotion)) {
                        editing.value = true
                    }
                }
                .buttonStyle(StoryLinkStyle())
                .font(Tokens.Typography.metadata.weight(.semibold))
                .frame(minHeight: 28)
                .accessibilityLabel(currentName == nil ? "Name this break" : "Rename this break")
                .focused($nameButtonFocused)
            }
            Button("Undo", action: undo)
                .buttonStyle(StoryLinkStyle())
                .font(Tokens.Typography.metadata.weight(.semibold))
                .foregroundStyle(StoryStyle.action)
                .frame(minWidth: 36, minHeight: 28)
                .disabled(undoBlockReason != nil)
                .help(undoBlockReason ?? "")
                .accessibilityLabel("Undo \(title.lowercased())")
                .accessibilityHint(undoBlockReason ?? scopeNote ?? "Reverts only this action; later work is unchanged.")
          }
          if editing.value, onName != nil {
              nameField
                  .padding(.leading, 22)
                  .transition(Tokens.Motion.transition(Tokens.Motion.unfold, reduceMotion: reduceMotion))
          }
          if let scopeNote {
              Text(scopeNote).font(Tokens.Typography.metadata).foregroundStyle(.secondary)
                  .fixedSize(horizontal: false, vertical: true)
                  .padding(.leading, 22)
          }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, Tokens.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onExitCommand { if editing.value { closeNameField() } }
        .background(LinearGradient(colors: [StoryStyle.successWash, StoryStyle.successWash.opacity(0.45)],
                                   startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: StoryStyle.entryRadius))
        .overlay(RoundedRectangle(cornerRadius: StoryStyle.entryRadius).strokeBorder(StoryStyle.successInk.opacity(0.22)))
    }

    /// The away prompt's own field, for a break that was answered without it.
    private var nameField: some View {
        HStack(spacing: Tokens.Space.s) {
            Image(systemName: "pencil.line")
                .font(Tokens.Typography.metadata.weight(.medium))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            TextField("Name it: dinner, a call, a walk", text: $draft.text)
                .textFieldStyle(.plain)
                .font(Tokens.Typography.metadata)
                .onSubmit(save)
                .focused($nameFocused)
                .onAppear {
                    // The field must be installed before it can take focus;
                    // the "Name it" button that had it has just gone.
                    DispatchQueue.main.async {
                        if editing.value { nameFocused = true }
                    }
                }
                .accessibilityLabel("Break name")
            Button("Save", action: save)
                .buttonStyle(StoryLinkStyle())
                .font(Tokens.Typography.metadata.weight(.semibold))
                .disabled(draft.text.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", action: closeNameField)
                .buttonStyle(StoryLinkStyle())
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Tokens.Space.m)
        .frame(minHeight: 30)
        .background(Tokens.Colour.elevated,
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.well, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.well, style: .continuous)
            .strokeBorder(Tokens.Colour.line))
    }

    private func save() {
        guard let onName, !draft.text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if onName(draft.text) || draft.text.trimmingCharacters(in: .whitespaces) == currentName {
            closeNameField()
        }
    }

    /// Focus goes back to the button that opened the field, so a keyboard
    /// reader is not dropped at the top of the window.
    private func closeNameField() {
        nameFocused = false
        editing.value = false
        DispatchQueue.main.async { nameButtonFocused = true }
    }
}
