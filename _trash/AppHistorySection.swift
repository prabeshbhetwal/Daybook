import SwiftUI

/// Per-app usage history for the popover: the most-used apps, each with its
/// recent sessions, and a Continue action when the app is still running.
struct AppHistorySection: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            HStack {
                Text("Recent apps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Tokens.duration(store.trackedToday) + " tracked")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if store.appSummaries.isEmpty {
                Text(store.isTrackingEnabled
                     ? "No app usage recorded yet."
                     : "App tracking is off.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.appSummaries) { summary in
                    AppHistoryRow(summary: summary,
                                  isRunning: store.isRunning(bundleID: summary.bundleID),
                                  todayTotal: store.totalToday(for: summary.bundleID)) {
                        store.continueApp(summary)
                    }
                }
            }
        }
    }
}

struct AppHistoryRow: View {
    let summary: AppUsageSummary
    let isRunning: Bool
    let todayTotal: TimeInterval
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            HStack(spacing: Tokens.Space.s) {
                Circle()
                    .fill(isRunning ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text(summary.appName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Spacer()
                if isRunning {
                    Button("Continue", action: onContinue)
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                        .font(.caption)
                        .accessibilityLabel("Continue \(summary.appName)")
                } else {
                    Text("not running")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // The headline the request asked for: how long ago, the clock range,
            // and the time spent.
            if let last = summary.lastSession {
                Text("Last session: \(Tokens.relative(last.end))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(Tokens.timeRange(last.start, last.end)) · \(Tokens.spent(last.seconds))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: Tokens.Space.m) {
                Text("Today \(Tokens.spent(todayTotal))")
                Text("Longest \(Tokens.spent(summary.longestSeconds))")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            // Older sessions, most recent first.
            if summary.recent.count > 1 {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(summary.recent.dropFirst()) { session in
                        Text("\(Tokens.timeRange(session.start, session.end))  ·  "
                             + Tokens.spent(session.seconds))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.leading, Tokens.Space.m)
            }
        }
        .padding(Tokens.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.25),
                    in: RoundedRectangle(cornerRadius: Tokens.cardCorner))
        .accessibilityElement(children: .combine)
    }
}
