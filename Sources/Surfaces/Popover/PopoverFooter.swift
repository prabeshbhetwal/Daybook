import SwiftUI
import AppKit

/// Text-labelled destinations keep the compact footer explicit. The callbacks
/// reveal the Story or explicitly select Settings before window activation.
/// Three destinations fit the panel at every zoom; a fourth, Check for
/// Updates, truncated to "Check for Upd…". It lives in Settings, About &
/// Updates, and in the Daybook menu.
struct PopoverFooter: View {
    var onOpenApplication: () -> Void
    var onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: Tokens.Space.m) {
            footerButton("Open Daybook", action: onOpenApplication)
            Spacer(minLength: Tokens.Space.s)
            footerButton("Settings", action: onOpenSettings)
                .keyboardShortcut(",", modifiers: .command)
            footerButton("Quit") { NSApp.terminate(nil) }
        }
        .font(Tokens.Typography.body)
    }

    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(StoryPressStyle(hovers: true))
            .foregroundStyle(StoryStyle.supportingInk)
            .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
            .contentShape(Rectangle())
            .accessibilityLabel(title)
    }
}
