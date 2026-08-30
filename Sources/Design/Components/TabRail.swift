import SwiftUI

/// Shared interaction metrics for compact desktop controls. Callers use the
/// same value for their visible frame, so the accessibility regression checks
/// the hit area that production actually consumes rather than a test-only
/// constant.
enum AccessibilityMetrics {
    static let minimumTargetSize: CGFloat = 28
}

enum TabRailPresentation {
    static let usesOuterSurface = false
    static let unselectedUsesBorder = false
    static let showsLabelsInIconFallback = true
}

extension AppTab {
    func accessibilityLabel(isSelected: Bool) -> String {
        "\(title), \(isSelected ? "selected" : "not selected"), Command \(commandNumber)"
    }
}

struct TabRail: View {
    let tabs: [AppTab]
    @Binding var selectedTab: AppTab
    let onSelect: (AppTab) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        tabs: [AppTab] = AppTab.allCases,
        selectedTab: Binding<AppTab>,
        onSelect: @escaping (AppTab) -> Void
    ) {
        self.tabs = tabs
        self._selectedTab = selectedTab
        self.onSelect = onSelect
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            pills(showsIcons: true)
            pills(showsIcons: false)
        }
        .quietFocus()
        .onMoveCommand { direction in
            switch direction {
            case .left: move(by: -1)
            case .right: move(by: 1)
            default: break
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Application tabs")
    }

    private func pills(showsIcons: Bool) -> some View {
        HStack(spacing: Tokens.Space.xs) {
            ForEach(tabs) { tab in
                let isSelected = tab == selectedTab
                Button { select(tab) } label: {
                    tabPill(tab, selected: isSelected, showsIcon: showsIcons,
                            showsLabel: !showsIcons || TabRailPresentation.showsLabelsInIconFallback)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character(String(tab.commandNumber))),
                                  modifiers: [.command])
                .help(tab.title)
                .accessibilityLabel(tab.accessibilityLabel(isSelected: isSelected))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private func move(by offset: Int) {
        guard !tabs.isEmpty else { return }
        let index = tabs.firstIndex(of: selectedTab) ?? 0
        let nextIndex = ((index + (offset % tabs.count)) + tabs.count) % tabs.count
        select(tabs[nextIndex])
    }

    private func select(_ tab: AppTab) {
        if reduceMotion {
            selectedTab = tab
        } else {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedTab = tab
            }
        }
        onSelect(tab)
    }

    private func tabPill(_ tab: AppTab, selected: Bool, showsIcon: Bool,
                         showsLabel: Bool) -> some View {
        HStack(spacing: Tokens.Space.xs) {
            if showsIcon {
                Image(systemName: tab.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
            }
            if showsLabel {
                Text(tab.title)
                    .font(Tokens.Typography.tabLabel)
                    .lineLimit(1)
            }
        }
        .fixedSize()
        .padding(.horizontal, Tokens.Space.m)
        .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
        .background(selected ? Tokens.Colour.focus : Color.clear, in: Capsule())
        .foregroundStyle(selected
                         ? AnyShapeStyle(Tokens.Colour.onFocus)
                         : AnyShapeStyle(Color.primary))
        .overlay(
            Capsule().strokeBorder(selected || !TabRailPresentation.unselectedUsesBorder
                                   ? Color.clear : Tokens.Colour.line,
                                   lineWidth: 1)
        )
        .contentShape(Capsule())
    }
}
