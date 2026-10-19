import SwiftUI

/// End break and +5 min, in the break card and in the window's row. Both run
/// the store's own actions; Resume, Start and Stop end a break there too.
struct FocusBreakButtons: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        HStack(spacing: Tokens.Space.s) {
            FocusActionButton(title: "End break", symbol: "stop.fill", prominent: true) { store.endBreak() }
                .help(store.isIdle
                      ? "Ends the break (\(SessionShortcut.takeBreak.glyphs))"
                      : "Ends the break and goes back to your session (\(SessionShortcut.takeBreak.glyphs))")
            FocusActionButton(title: "+\(Int(BreakLength.extra / 60)) min", symbol: "plus",
                              spoken: "Add \(Int(BreakLength.extra / 60)) minutes to the break") {
                store.extendBreak()
            }
            .help("Adds \(Int(BreakLength.extra / 60)) minutes to the break")
        }
    }
}

/// What the break is, under its time: the label the person typed, and where
/// the session paused beneath it will go back to.
private func breakSubtitle(_ store: SessionStore) -> String {
    if let label = store.activeBreak?.label { return label }
    return store.isIdle ? "No session running" : "Then back to \(store.activeIntent)"
}

private extension View {
    /// The countdown, spoken to the minute. The text itself changes each
    /// second in the last minute; this value does not, and the trait tells
    /// VoiceOver it moves on its own, so nothing is announced as it ticks.
    func breakCountdownAccessibility(_ remaining: TimeInterval) -> some View {
        accessibilityLabel("Break timer")
            .accessibilityValue(BreakCountdown.spoken(remaining: remaining))
            .accessibilityAddTraits(.updatesFrequently)
    }
}

/// The break, stacked: the popover and a page. The card the popover leads
/// with while a break runs.
struct FocusBreakBody: View {
    @ObservedObject var store: SessionStore
    let compact: Bool

    var body: some View {
        VStack(alignment: compact ? .leading : .center,
               spacing: compact ? Tokens.Space.s : Tokens.Space.m) {
            Label(FocusSurfaceMode.onBreak.primaryPrompt, systemImage: "cup.and.saucer.fill")
                .font(Tokens.Typography.label)
                .foregroundStyle(StoryStyle.supportingInk)
            Text(BreakCountdown.cardText(remaining: store.breakRemaining))
                .font(Tokens.Typography.display.monospacedDigit())
                .breakCountdownAccessibility(store.breakRemaining)
            Text(breakSubtitle(store))
                .font(Tokens.Typography.body)
                .foregroundStyle(StoryStyle.supportingInk)
                .lineLimit(1)
            FocusBreakButtons(store: store)
        }
        .frame(maxWidth: .infinity, alignment: compact ? .leading : .center)
    }
}

/// The break in the window's chrome row, where the clock and the session's
/// controls stand: the time left, what it is, and the two buttons.
struct FocusBreakRowLead: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        HStack(spacing: Tokens.Space.m) {
            Image(systemName: "cup.and.saucer.fill")
                .font(Tokens.Typography.rowTitle)
                .foregroundStyle(StoryStyle.supportingInk)
                .accessibilityHidden(true)
            Text(BreakCountdown.cardText(remaining: store.breakRemaining))
                .font(Tokens.Typography.clock.monospacedDigit())
                .fixedSize()
                .breakCountdownAccessibility(store.breakRemaining)
            VStack(alignment: .leading, spacing: 1) {
                Text(FocusSurfaceMode.onBreak.primaryPrompt)
                    .font(Tokens.Typography.rowTitle)
                    .lineLimit(1)
                Text(breakSubtitle(store))
                    .font(Tokens.Typography.body)
                    .foregroundStyle(StoryStyle.supportingInk)
                    .lineLimit(1)
            }
            .layoutPriority(1)
            FocusBreakButtons(store: store)
                .fixedSize()
        }
    }
}
