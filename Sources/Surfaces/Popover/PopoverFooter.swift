import SwiftUI
import AppKit

/// Text-labelled destinations keep the compact footer explicit. The callbacks
/// reveal the Story or explicitly select Settings before window activation.
struct PopoverFooter: View {
    var onOpenApplication: () -> Void
    var onOpenSettings: () -> Void
    var onCheckForUpdates: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: Tokens.Space.m) {
            footerButton("Open Daybook", action: onOpenApplication)
            Spacer(minLength: Tokens.Space.s)
            footerButton("Settings", action: onOpenSettings)
                .keyboardShortcut(",", modifiers: .command)
            if let onCheckForUpdates {
                footerButton("Updates", action: onCheckForUpdates)
                    .help("Check for Updates")
                    .accessibilityLabel("Check for Updates")
            }
            footerButton("Quit") { NSApp.terminate(nil) }
        }
        .font(Tokens.Typography.body)
    }

    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(StoryPressStyle())
            .foregroundStyle(.secondary)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
            .accessibilityLabel(title)
    }
}
