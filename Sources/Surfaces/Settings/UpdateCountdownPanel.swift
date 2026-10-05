import AppKit
import Combine
import SwiftUI

/// "FocusContinuity 1.1 is ready": installs and relaunches when the count
/// reaches zero, or now, or later. Later leaves the update to install when
/// the app next quits. A running session is saved and comes back on relaunch.
final class UpdateCountdownPanel {
    static let seconds = 30
    private var panel: NSPanel?

    func show(version: String, install: @escaping () -> Void) {
        close()
        let view = UpdateCountdownView(
            version: version,
            onInstall: { [weak self] in self?.close(); install() },
            onLater: { [weak self] in self?.close() })
        let host = NSHostingView(rootView: view)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        panel.center()
        panel.orderFrontRegardless()
        self.panel = panel
        Announcement.post("FocusContinuity \(version) is ready. It installs in \(Self.seconds) seconds.")
    }

    func close() {
        panel?.close()
        panel = nil
    }
}

private struct UpdateCountdownView: View {
    let version: String
    let onInstall: () -> Void
    let onLater: () -> Void
    @State private var remaining = UpdateCountdownPanel.seconds
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Label("FocusContinuity \(version) is ready", systemImage: "arrow.down.circle.fill")
                .font(Tokens.Typography.rowTitle.weight(.semibold))
                .foregroundStyle(.primary)
            Text("It installs and relaunches in \(remaining) seconds. A running session carries on.")
                .font(Tokens.Typography.metadata.monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ProgressView(value: Double(UpdateCountdownPanel.seconds - remaining),
                         total: Double(UpdateCountdownPanel.seconds))
                .accessibilityHidden(true)
            HStack(spacing: Tokens.Space.s) {
                Spacer(minLength: 0)
                Button("Later", action: onLater)
                    .keyboardShortcut(.cancelAction)
                    .help("Installs the next time FocusContinuity quits")
                Button("Install Now", action: onInstall)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Tokens.Space.xl)
        .frame(width: 380)
        .onReceive(tick) { _ in
            guard remaining > 0 else { return }
            remaining -= 1
            if remaining == 0 { onInstall() }
        }
    }
}
