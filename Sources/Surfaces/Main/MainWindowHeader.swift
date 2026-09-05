import SwiftUI
import AppKit

/// Pure context for the one-row window chrome. It keeps the visible title and
/// live status in the same visual band as the application tabs.
enum MainWindowChrome {
    static let trafficLightClearance: CGFloat = 76
    static let usesNativeFocusRing = false
    static let appMarkFallbackSymbol = "target"
    static let appMarkSize: CGFloat = 24

    enum AppMarkPresentation: Equatable {
        case bundledIcon
        case targetFallback
    }

    static func appMarkPresentation(hasBundledIcon: Bool) -> AppMarkPresentation {
        hasBundledIcon ? .bundledIcon : .targetFallback
    }

    struct Context: Equatable {
        let title: String
        let subtitle: String
        let status: String
    }

    static func context(
        tab: AppTab,
        state: SessionState,
        threadElapsed: TimeInterval,
        todayTotal: TimeInterval
    ) -> Context {
        let status: String
        switch state {
        case .running:
            status = "Focus active · \(Tokens.duration(threadElapsed))"
        case .paused:
            status = "Focus paused · \(Tokens.duration(threadElapsed))"
        case .awaitingUserDecision:
            status = "Focus needs an answer · \(Tokens.duration(threadElapsed))"
        case .idle:
            status = "Today · \(Tokens.duration(todayTotal)) focused"
        }
        return Context(title: tab.title, subtitle: "FocusContinuity", status: status)
    }
}

private struct FocusContinuityMark: View {
    private var icon: NSImage? {
        Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            .flatMap(NSImage.init(contentsOf:))
    }

    var body: some View {
        Group {
            switch MainWindowChrome.appMarkPresentation(hasBundledIcon: icon != nil) {
            case .bundledIcon:
                if let icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                }
            case .targetFallback:
                Image(systemName: MainWindowChrome.appMarkFallbackSymbol)
                    .font(Tokens.Typography.tabLabel.weight(.semibold))
                    .foregroundStyle(Tokens.Colour.focus)
                    .background(Tokens.Colour.focus.opacity(0.12), in: Circle())
            }
        }
            .frame(width: MainWindowChrome.appMarkSize,
                   height: MainWindowChrome.appMarkSize)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.control, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The title, status and tab rail share one fixed content-titlebar row. The
/// actual macOS traffic lights remain native; the leading inset gives them
/// space when the scene uses `.hiddenTitleBar`.
struct MainWindowChromeBar: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var navigation: MainWindowModel
    @ObservedObject var settings: SettingsModel

    private var context: MainWindowChrome.Context {
        MainWindowChrome.context(
            tab: navigation.selectedTab,
            state: store.state,
            threadElapsed: store.threadElapsed,
            todayTotal: store.todayTotal
        )
    }

    var body: some View {
        HStack(spacing: Tokens.Space.m) {
            FocusContinuityMark()

            VStack(alignment: .leading, spacing: 0) {
                Text(context.title)
                    .font(Tokens.Typography.sectionTitle)
                    .lineLimit(1)
                Text(context.subtitle)
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 128, alignment: .leading)

            Spacer(minLength: 0)

            TabRail(selectedTab: $navigation.selectedTab) { tab in
                navigation.select(tab)
            }

            Spacer(minLength: 0)

            Text(context.status)
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: 148, alignment: .trailing)
                .accessibilityLabel(context.status.replacingOccurrences(of: " · ", with: ", "))
        }
        .padding(.leading, MainWindowChrome.trafficLightClearance)
        .padding(.trailing, Tokens.Space.xl)
        .padding(.vertical, settings.interfaceDensity == .compact ? Tokens.Space.xs : Tokens.Space.s)
        .frame(maxWidth: .infinity)
    }
}
