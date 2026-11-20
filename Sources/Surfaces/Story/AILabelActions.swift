import SwiftUI

/// At the top of a session's report, beside the AI mark: what Apple Intelligence filed the session under and
/// the person's answers (rulings C13, C31 and C32). On a pick, Keep and Change…; on a label it made, live or aged
/// out, Keep, Rename…, Merge Into and Remove; on one the person retired that the session still carries, Merge Into
/// and Remove. Keep on a label
/// makes the category the person's, and the mark stays on each of its sessions until that session is kept.
/// `SessionStore.aiReport` decides what is offered; this draws it and calls the actions.
struct AILabelActions: View {
    /// Only for the clicks; not observed, so the 1 Hz ticker does not redraw this.
    let store: SessionStore
    let session: DaySession
    let filing: AISessionReport.Filing
    /// Where Merge Into can take a label's sessions (`AISessionReport.mergeTargets`).
    let mergeTargets: [WorkType]
    /// A change of category leaves the card's session stale, so the card closes; Edit > Undo takes it back.
    let onChanged: () -> Void
    @State private var renaming = false
    @State private var typed = ""
    @FocusState private var nameFocused: Bool

    static func sentence(_ filing: AISessionReport.Filing) -> String {
        switch filing {
        case .pick(let type): return "On-device AI filed this under \(type.displayName)."
        case .label(let type): return "On-device AI made the category \(type.displayName) for this."
        case .lapsedLabel(let type):
            return "On-device AI made the category \(type.displayName) for this. It is no longer suggested."
        case .retiredLabel(let type): return "This still carries \(type.displayName), a category you merged or removed."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                AIMark()
                Text(Self.sentence(filing))
                    .font(Tokens.Typography.body)
                    .foregroundStyle(StoryStyle.supportingInk)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Tokens.Space.s)
                actions(filing)
            }
            if renaming, let type = filing.keepableLabel { renameField(type) }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func actions(_ filing: AISessionReport.Filing) -> some View {
        switch filing {
        case .pick(let type):
            link("Keep", hint: "Makes \(type.displayName) your choice for this session and takes the sparkle away.") {
                if store.keepAIPick(session) { Announcement.post("Kept \(type.displayName)") }
            }
            menu("Change…", label: "Change category", items: WorkType.allCases.filter { $0 != type }) { picked in
                if store.setWorkType(picked, for: session) { Announcement.post("Filed under \(picked.displayName)"); onChanged() }
            }
        case .label(let type), .lapsedLabel(let type):
            link("Keep", hint: "Adds \(type.displayName) to your categories. Each of its sessions keeps the sparkle "
                 + "until you keep it there.") {
                if store.keepAILabel(type.rawValue) { Announcement.post("Kept \(type.displayName)") }
            }
            link("Rename…", hint: "Keeps \(type.displayName) under a name you type.") {
                typed = type.displayName
                renaming = true
                nameFocused = true
            }
            retireActions(type)
        case .retiredLabel(let type):
            retireActions(type)
        }
    }

    @ViewBuilder private func retireActions(_ type: WorkType) -> some View {
        menu("Merge Into", label: "Merge \(type.displayName) into", items: mergeTargets.filter { $0 != type }) { target in
            if store.mergeAILabel(type.rawValue, into: target) { Announcement.post("Merged into \(target.displayName)"); onChanged() }
        }
        link("Remove", hint: "Files every session in \(type.displayName) as Unsorted. Undo is in the Edit menu.") {
            if store.removeAILabel(type.rawValue) { Announcement.post("Removed \(type.displayName)"); onChanged() }
        }
    }

    private func renameField(_ type: WorkType) -> some View {
        HStack(spacing: Tokens.Space.s) {
            TextField("Category name", text: $typed)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit { rename(type) }
                .onExitCommand { renaming = false }
                .accessibilityLabel("New name for \(type.displayName)")
            link("Cancel", hint: "Leaves the name as it is.") { renaming = false }
            link("Rename", hint: "Keeps the category under this name.") { rename(type) }
                .disabled(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func rename(_ type: WorkType) {
        guard store.keepAILabel(type.rawValue, as: typed) else { return }
        renaming = false
        Announcement.post("Kept as \(typed)")
    }

    private func link(_ title: String, hint: String, _ perform: @escaping () -> Void) -> some View {
        Button(title, action: perform)
            .buttonStyle(StoryLinkStyle())
            .help(hint)
            .accessibilityHint(hint)
    }

    /// A pull-down in the link buttons' ink and weight, its chevron kept to say it opens a menu.
    private func menu(_ title: String, label: String, items: [WorkType],
                      pick: @escaping (WorkType) -> Void) -> some View {
        Menu {
            ForEach(items) { type in
                Button { pick(type) } label: { Label(type.displayName, systemImage: type.symbolName) }
            }
        } label: {
            Text(title).font(Tokens.Typography.label).foregroundStyle(StoryStyle.action)
        }
        .menuStyle(.borderlessButton)
        .tint(StoryStyle.action)
        .foregroundStyle(StoryStyle.action)
        .fixedSize()
        .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
        .accessibilityLabel(label)
    }
}
