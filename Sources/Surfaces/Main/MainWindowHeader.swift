import SwiftUI

/// Fixed title/status band for the desktop shell. It formats only figures the
/// session store already publishes; no duration or focus accounting lives here.
struct MainWindowHeader: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel

    var body: some View {
        HStack(spacing: Tokens.Space.m) {
            Image(systemName: "infinity")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Tokens.Colour.onFocus)
                .frame(width: 30, height: 30)
                .background(Tokens.Colour.focus, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(navigation.selectedTab.title)
                    .font(Tokens.Typography.pageTitle)
                Text("FocusContinuity")
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: Tokens.Space.xl)

            Text(status)
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .accessibilityLabel(status.replacingOccurrences(of: " · ", with: ", "))
        }
        .padding(.horizontal, Tokens.Space.xl)
        .padding(.vertical, Tokens.Space.m)
        .frame(maxWidth: .infinity)
    }

    private var status: String {
        switch store.state {
        case .running:
            return "Focus active · \(Tokens.duration(store.threadElapsed))"
        case .paused:
            return "Focus paused · \(Tokens.duration(store.threadElapsed))"
        case .awaitingUserDecision:
            return "Focus needs an answer · \(Tokens.duration(store.threadElapsed))"
        case .idle:
            return "Today · \(Tokens.duration(store.todayTotal)) focused"
        }
    }
}
