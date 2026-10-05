import SwiftUI

/// The line under the chrome. The bar's row holds what begins, pauses and
/// ends a session; this holds only what that row cannot — the away
/// question, a quiet activity choice, the automatic session's Adopt and
/// Undo, a note the reader is held to, a save that failed — and is not there
/// at all otherwise. Nothing here is dismissable, so there is nothing to pin.
struct SessionUnderline: View {
    @ObservedObject var store: SessionStore
    @FocusState private var intentFocused: Bool

    static func hasContent(_ store: SessionStore) -> Bool {
        FocusHero.underlineHasContent(store)
            || store.pendingActivityChoice != nil
            || store.activityAutomationError != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            FocusHero(store: store, intentFocused: $intentFocused, compact: true, wide: true,
                      showsGoal: false, chromePart: .underline)
            if let choice = store.pendingActivityChoice {
                ActivityQuietChoiceView(store: store, choice: choice)
            }
            if let error = store.activityAutomationError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(Tokens.Typography.metadata).foregroundStyle(Tokens.Colour.danger)
            }
        }
        .padding(.horizontal, Tokens.Space.xl)
        .padding(.vertical, Tokens.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StoryStyle.rail)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Session question")
    }
}

struct ActivityQuietChoiceView: View {
    @ObservedObject var store: SessionStore
    let choice: ActivityQuietChoice

    private var question: String { choice.candidates.map(\.name).joined(separator: " or ") + "?" }

    /// Choosing starts a session of that activity from when the time in the
    /// other app began; the time since, spent here, is left out.
    static let explanation = "Choose the one you were doing. Your time in the other app "
        + "just now becomes a session of it. Time in Daybook isn't counted."

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Text(question)
                .font(Tokens.Typography.rowTitle)
            Text(Self.explanation)
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                ForEach(choice.candidates, id: \.ruleID) { candidate in
                    Button(candidate.name) { store.chooseActivity(ruleID: candidate.ruleID) }
                        .buttonStyle(StoryActionStyle())
                }
            }
        }
        .padding(Tokens.Space.m)
        .background(StoryStyle.well, in: RoundedRectangle(cornerRadius: Tokens.Radius.nested))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Choose activity for recorded app use")
        .storyRenderEvidence(.activityQuietChoice)
        // It arrives on its own, between whatever else is on screen; said
        // aloud, a listener knows there is a question to answer.
        .onAppear { announce() }
        .onChange(of: choice.id) { _ in announce() }
    }

    private func announce() {
        Announcement.post("\(question) \(Self.explanation)")
    }
}
