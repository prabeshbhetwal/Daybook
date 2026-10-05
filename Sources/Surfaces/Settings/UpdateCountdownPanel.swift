import AppKit
import SwiftUI

/// What the countdown does at a moment: show the seconds left, wait for the
/// reader to finish something a relaunch would lose, or install.
enum UpdateCountdownStep: Equatable {
    case counting(secondsLeft: Int)
    case waiting
    case install

    static func at(_ now: Date, deadline: Date, busy: Bool) -> UpdateCountdownStep {
        let left = Int(deadline.timeIntervalSince(now).rounded(.up))
        if left > 0 { return .counting(secondsLeft: left) }
        return busy ? .waiting : .install
    }
}

/// "FocusContinuity 1.1 is ready": installs and relaunches when the count
/// reaches zero, or now, or later. The count runs from a deadline the panel
/// controller owns, not from a timer in the view; at zero it waits while a
/// note, the away question or a naming is open.
final class UpdateCountdownPanel {
    static let seconds: TimeInterval = 30
    private var panel: NSPanel?
    private var check: DispatchWorkItem?
    private let state = UpdateCountdownState()

    func show(version: String, isBusy: @escaping () -> Bool,
              install: @escaping () -> Void, later: @escaping () -> Void) {
        close()
        state.deadline = Date().addingTimeInterval(Self.seconds)
        state.waiting = false
        let view = UpdateCountdownView(
            version: version, state: state,
            onInstall: { [weak self] in self?.close(); install() },
            onLater: { [weak self] in self?.close(); later() })
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
        Announcement.post("FocusContinuity \(version) is ready. It installs in \(Int(Self.seconds)) seconds.")
        schedule(at: state.deadline, isBusy: isBusy, install: install)
    }

    /// At the deadline, install unless something would be lost; then look
    /// again every few seconds until it would not.
    private func schedule(at date: Date, isBusy: @escaping () -> Bool, install: @escaping () -> Void) {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            switch UpdateCountdownStep.at(Date(), deadline: self.state.deadline, busy: isBusy()) {
            case .install:
                self.close()
                install()
            case .waiting:
                self.state.waiting = true
                self.schedule(at: Date().addingTimeInterval(3), isBusy: isBusy, install: install)
            case .counting:
                self.schedule(at: self.state.deadline, isBusy: isBusy, install: install)
            }
        }
        check = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, date.timeIntervalSinceNow), execute: work)
    }

    func close() {
        check?.cancel()
        check = nil
        panel?.close()
        panel = nil
    }
}

final class UpdateCountdownState: ObservableObject {
    @Published var deadline = Date()
    @Published var waiting = false
}

private struct UpdateCountdownView: View {
    let version: String
    @ObservedObject var state: UpdateCountdownState
    let onInstall: () -> Void
    let onLater: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Label("FocusContinuity \(version) is ready", systemImage: "arrow.down.circle.fill")
                .font(Tokens.Typography.rowTitle.weight(.semibold))
            // Redrawn once a second only while the panel is up; the deadline,
            // not this view, decides when to install.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(message(at: context.date))
                    .font(Tokens.Typography.metadata.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Tokens.Space.s) {
                Spacer(minLength: 0)
                Button("Later", action: onLater)
                    .keyboardShortcut(.cancelAction)
                    .help("Offers it again in a few hours, and installs it the next time FocusContinuity quits")
                Button("Install Now", action: onInstall)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Tokens.Space.xl)
        .frame(width: 380)
    }

    private func message(at date: Date) -> String {
        if state.waiting {
            return "Waiting until you finish your note or answer. Then it installs and relaunches."
        }
        let left = max(1, Int(state.deadline.timeIntervalSince(date).rounded(.up)))
        return "It installs and relaunches in \(left) seconds. A running session carries on; "
            + "the moments it takes may show as a short pause."
    }
}
