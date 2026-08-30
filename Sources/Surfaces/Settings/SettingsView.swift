import SwiftUI

/// Where Settings switches between the two-pane sidebar and the compact group
/// menu, and how wide its control column reads. Chosen against the real
/// 980–1,160 pt production window range.
enum SettingsLayout {
    static let detailMeasure: CGFloat = 720

    static func usesSidebar(at width: CGFloat) -> Bool { width >= 1_080 }
}

/// First-class Settings canvas. Search filters the navigation metadata; the
/// selected group remains the sole detail surface rather than expanding eight
/// forms into one exhaustive page.
struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var navigation: MainWindowModel
    var scrolls: Bool

    init(model: SettingsModel, navigation: MainWindowModel, scrolls: Bool = true) {
        self.model = model
        self.navigation = navigation
        self.scrolls = scrolls
    }

    /// Kept as the view's own spelling of the shared contract so existing call
    /// sites and tests read naturally.
    static func usesSidebar(at width: CGFloat) -> Bool {
        SettingsLayout.usesSidebar(at: width)
    }

    var body: some View {
        GeometryReader { proxy in
            let sections = SettingsSection.matching(navigation.settingsQuery)
            VStack(alignment: .leading, spacing: Tokens.Space.l) {
                search
                if let section = visibleSection(in: sections) {
                    if Self.usesSidebar(at: proxy.size.width) {
                        wide(sections: sections, section: section)
                    } else {
                        narrow(sections: sections, section: section)
                    }
                } else {
                    EmptyState("No matching settings",
                               detail: "Try a control label such as goal, privacy or appearance.",
                               icon: "magnifyingglass")
                        .frame(maxHeight: .infinity)
                }
            }
            .padding(Self.usesSidebar(at: proxy.size.width)
                     ? Tokens.Space.xxl : Tokens.Space.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Tokens.Colour.ground)
    }

    private var search: some View {
        HStack(spacing: Tokens.Space.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            if scrolls {
                TextField("Search settings", text: $navigation.settingsQuery)
                    .textFieldStyle(.plain)
            } else {
                Text(navigation.settingsQuery.isEmpty
                     ? "Search settings" : navigation.settingsQuery)
                    .foregroundStyle(navigation.settingsQuery.isEmpty
                                     ? AnyShapeStyle(.secondary)
                                     : AnyShapeStyle(.primary))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Tokens.Space.m)
        .frame(height: 36)
        .background(Tokens.Colour.elevated,
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.nested,
                                         style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.nested,
                                  style: .continuous)
            .stroke(Tokens.Colour.line, lineWidth: 1))
        .frame(maxWidth: 480)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search settings")
        .accessibilitySortPriority(2)
    }

    private func wide(sections: [SettingsSection], section: SettingsSection) -> some View {
        HStack(alignment: .top, spacing: Tokens.Space.xl) {
            if scrolls {
                ScrollView {
                    SettingsSidebar(sections: sections,
                                    selected: selectionBinding(in: sections))
                }
            } else {
                SettingsSidebar(sections: sections,
                                selected: selectionBinding(in: sections))
            }
            Divider()
            detail(section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilitySortPriority(1)
    }

    private func narrow(sections: [SettingsSection], section: SettingsSection) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.l) {
            if scrolls {
                SettingsGroupMenu(sections: sections,
                                  selected: selectionBinding(in: sections))
                    .frame(maxWidth: 360)
            } else {
                SettingsGroupLabel(selected: section)
                    .frame(maxWidth: 360)
            }
            detail(section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilitySortPriority(1)
    }

    @ViewBuilder private func detail(_ section: SettingsSection) -> some View {
        let content = VStack(alignment: .leading, spacing: Tokens.Space.l) {
            Label(section.title, systemImage: section.symbol)
                .font(Tokens.Typography.pageTitle)
                .symbolRenderingMode(.hierarchical)
                .accessibilityAddTraits(.isHeader)
            SettingsGroups(model: model, section: section)
                .frame(maxWidth: SettingsLayout.detailMeasure, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)

        if scrolls {
            ScrollView { content.padding(.bottom, Tokens.Space.xxl) }
        } else {
            content.frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func visibleSection(in sections: [SettingsSection]) -> SettingsSection? {
        guard !sections.isEmpty else { return nil }
        return sections.contains(navigation.settingsSection)
            ? navigation.settingsSection : sections[0]
    }

    private func selectionBinding(in sections: [SettingsSection]) -> Binding<SettingsSection> {
        Binding(
            get: { visibleSection(in: sections) ?? navigation.settingsSection },
            set: { navigation.settingsSection = $0 })
    }
}
