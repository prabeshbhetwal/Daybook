import SwiftUI

/// An editable activity with a suggestion menu. The menu only fills the draft;
/// Start remains the single action that begins work.
struct ActivityChooser: View {
    @ObservedObject var store: SessionStore
    var intentFocused: FocusState<Bool>.Binding
    var compact = false
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField(compact ? "Choose or type an activity" : "Choose an activity or type your own",
                      text: $store.intent)
                .textFieldStyle(.plain)
                .font(compact ? .body : .title3)
                .focused(intentFocused)
                .onSubmit(onSubmit)
                .accessibilityLabel("Activity name")
                .accessibilityHint("Write your own activity, or choose a recent name from the menu.")
            Menu {
                if !recent.isEmpty {
                    Section("Recent activities") {
                        ForEach(recent) { item in
                            Button(item.name) { select(name: item.name, type: item.workType) }
                        }
                    }
                }
                Section("Suggestions") {
                    ForEach(WorkType.startable, id: \.self) { type in
                        Button(type.displayName) { select(name: type.displayName, type: type) }
                    }
                }
            } label: {
                Label("Choose an activity", systemImage: "chevron.down")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Choose an activity")
            .help("Choose a recent activity or suggestion. This does not start a session.")
        }
    }

    private func select(name: String, type: WorkType) {
        store.intent = name
        store.workType = type
        intentFocused.wrappedValue = true
    }

    private var recent: [QuickStart] {
        store.quickStarts.filter { item in
            !WorkType.startable.contains { type in
                item.workType == type && item.name.caseInsensitiveCompare(type.displayName) == .orderedSame
            }
        }
    }
}
