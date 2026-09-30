import SwiftUI

/// An editable activity with a suggestion menu. The menu only fills the draft;
/// Start remains the single action that begins work.
///
/// The control owns its own box. It used to be a bare `HStack` that each caller
/// padded and framed, which made the visible field 32pt tall while only the
/// 16pt text view accepted a click — the padding looked like part of the target
/// and did nothing. Drawing the box here keeps the thing you see and the thing
/// you can hit the same shape.
struct ActivityChooser: View {
    @ObservedObject var store: SessionStore
    var intentFocused: FocusState<Bool>.Binding
    var compact = false
    let onSubmit: () -> Void
    @Environment(\.openActivityEditor) private var openActivityEditor

    var body: some View {
        HStack(spacing: Tokens.Space.s) {
            TextField(compact ? "Choose or type an activity" : "Choose an activity or type your own",
                      text: $store.intent)
                .textFieldStyle(.plain)
                .font(compact ? Tokens.Typography.control : Tokens.Typography.rowTitle)
                .focused(intentFocused)
                .onSubmit(onSubmit)
                .accessibilityLabel("Activity name")
                .accessibilityHint("Write your own activity, or choose a recent name from the menu.")
            Menu {
                // What the user does, not what it is filed under. The
                // category picker beside this field owns categories; listing
                // them here too was the same choice offered twice.
                if !store.savedActivities.isEmpty {
                    Section("Pinned") {
                        ForEach(store.savedActivities) { item in
                            Button { store.chooseActivity(item); intentFocused.wrappedValue = true } label: {
                                Label(item.name, systemImage: item.workType.symbolName)
                                    .labelStyle(.titleAndIcon)
                            }
                        }
                    }
                }
                let recent = store.recentActivities
                if !recent.isEmpty {
                    Section("Recent") {
                        ForEach(recent) { item in
                            Button { select(name: item.name, type: item.workType) } label: {
                                Label(item.name, systemImage: item.workType.symbolName)
                                    .labelStyle(.titleAndIcon)
                            }
                        }
                    }
                }
                if openActivityEditor != nil { Divider() }
                if let openActivityEditor {
                    Button { openActivityEditor(.new) } label: {
                        Label("Pin activity…", systemImage: "pin")
                            .labelStyle(.titleAndIcon)
                    }
                    if !store.savedActivities.isEmpty {
                        Button { openActivityEditor(.edit) } label: {
                            Label("Edit pinned…", systemImage: "slider.horizontal.3")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                }
            } label: {
                Label("Choose an activity", systemImage: "chevron.down")
                    .labelStyle(.iconOnly)
                    .font(Tokens.Typography.metadata.weight(.semibold))
                    // A bordered button is sized by its label. At 12pt the
                    // chevron alone left a 21pt target.
                    .frame(height: 16)
            }
            // Same reason as WorkTypePicker: a borderless menu's popup is
            // 14pt tall and no frame around it changes that. Bordered and
            // large, it becomes the right-hand half of a combo box.
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .controlSize(.large)
            .foregroundStyle(.secondary)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Choose an activity")
            .help("Choose one of your activities or a recent name. This does not start a session.")
            .redrawn(on: MenuContents(pinned: store.savedActivities, recent: store.recentActivities,
                                      canEdit: openActivityEditor != nil))
        }
        .padding(.leading, Tokens.Space.m)
        .padding(.trailing, Tokens.Space.xs)
        .frame(minHeight: fieldHeight)
        .background(Tokens.Colour.elevated,
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous)
                .strokeBorder(Tokens.Colour.line)
        )
        // The whole box is the field: clicking its padding puts the caret in
        // the text rather than doing nothing.
        .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
        .onTapGesture { intentFocused.wrappedValue = true }
    }

    private var fieldHeight: CGFloat { compact ? Tokens.Control.compactHeight : 38 }

    /// What the menu lists; it redraws only when this changes.
    private struct MenuContents: Equatable {
        let pinned: [SavedActivity]
        let recent: [QuickStart]
        let canEdit: Bool
    }

    private func select(name: String, type: WorkType) {
        store.intent = name
        store.workType = type
        intentFocused.wrappedValue = true
    }
}
