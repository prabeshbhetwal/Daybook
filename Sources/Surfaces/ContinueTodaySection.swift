import SwiftUI

/// Earlier work, resumable in one click. Each row is a thread: what it was, how
/// long it has taken across every segment, and what it was worked in.
struct ContinueTodaySection: View {
    @ObservedObject var store: SessionStore
    var limit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            SectionHeader(title: "Continue today",
                          trailing: store.threadsToday.isEmpty ? nil
                              : store.threadsToday.count == 1 ? "1 session"
                                                              : "\(store.threadsToday.count) sessions")
            if store.threadsToday.isEmpty {
                Text("No sessions yet today.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.threadsToday.prefix(limit)) { thread in
                    ThreadRow(thread: thread,
                              apps: store.threadApps(thread),
                              onContinue: { store.continueThread(thread) })
                }
            }
        }
    }
}

private struct ThreadRow: View {
    let thread: ThreadSummary
    let apps: ThreadApps
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Line one: what, and how long — with the segment count beside the
            // figure it qualifies. Line two: where, and the one action. The
            // count used to share line two with the pill, and on a narrow
            // column the pill was what gave way, breaking "Continue" in half.
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                Text(title)
                    .font(Tokens.Typography.row.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: Tokens.Space.s)
                Text(Tokens.preciseDuration(thread.totalWorked))
                    .font(Tokens.Typography.row.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("· \(segmentLabel)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .fixedSize()
            }
            HStack(spacing: Tokens.Space.xs) {
                if let primary = apps.primary {
                    AppIcon(bundleID: primary.bundleID, size: 14, appName: primary.appName)
                    Text(primary.appName)
                        .font(.caption)
                        .lineLimit(1)
                }
                if !apps.side.isEmpty {
                    Text(sideLabel)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: Tokens.Space.s)
                if thread.isRunning {
                    Text("running")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tint)
                        .fixedSize()
                } else {
                    Button("Continue", action: onContinue)
                        .buttonStyle(.plain)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tint)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, Tokens.Space.s)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .accessibilityLabel("Continue \(title)")
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// An unnamed session still needs something to click on.
    private var title: String {
        thread.name.isEmpty ? thread.workType.displayName : thread.name
    }

    private var sideLabel: String {
        "+ " + apps.side.prefix(3).map(\.appName).joined(separator: ", ")
    }

    private var segmentLabel: String {
        thread.segments == 1 ? "1 segment" : "\(thread.segments) segments"
    }
}
