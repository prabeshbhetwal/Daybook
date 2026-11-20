import SwiftUI

/// In a finished automatic session's report, shadow mode's offer (rulings C8 and C21), saying who suggests it:
/// "On-device AI suggests Writing." or "On-device AI suggests a new category, Films.", with Use. `SessionStore.aiReport` decides what is offered, and offers nothing while a
/// remembered correction is; the card draws this only while there is one.
struct AISuggestionRow: View {
    /// Only for the click; not observed, so the 1 Hz ticker does not redraw this.
    let store: SessionStore
    let session: DaySession
    let suggestion: AISessionReport.Suggestion
    /// Use changes the session the report is open on, so the card closes; Edit > Undo takes it back.
    let onChanged: () -> Void

    static func line(for suggestion: AISessionReport.Suggestion) -> String {
        switch suggestion {
        case .pick(let type), .label(let type): return "On-device AI suggests \(type.displayName)."
        case .newCategory(let name): return "On-device AI suggests a new category, \(name)."
        }
    }

    /// What Use does, said in full where it also adds a category: a label the AI made, or a new one, is kept first.
    static func useHint(for suggestion: AISessionReport.Suggestion) -> String {
        switch suggestion {
        case .pick(let type): return "Files this session under \(type.displayName)."
        case .label(let type): return "Adds \(type.displayName) to your categories and files this session under it."
        case .newCategory(let name): return "Adds \(name) to your categories and files this session under it."
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
            Image(systemName: "sparkle")
                .font(Tokens.Typography.caption)
                .accessibilityHidden(true)
            Text(Self.line(for: suggestion))
                .font(Tokens.Typography.body)
                .fixedSize(horizontal: false, vertical: true)
                .help("On-device AI's suggestion for this session.")
            Spacer(minLength: Tokens.Space.s)
            Button("Use", action: use)
                .buttonStyle(StoryLinkStyle())
                .accessibilityLabel("Use suggestion")
                .accessibilityHint(Self.useHint(for: suggestion))
        }
        .foregroundStyle(StoryStyle.supportingInk)
        .accessibilityElement(children: .contain)
    }

    private func use() {
        guard store.useAISuggestion(suggestion, for: session) else { return }
        Announcement.post("Suggestion used")
        onChanged()
    }
}
