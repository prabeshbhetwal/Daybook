import SwiftUI

/// Dimensions include StorySheet's title band. Every category and search result
/// shares this bounded frame; only genuinely overflowing page content scrolls.
enum SettingsLayout {
    static let detailMeasure: CGFloat = 720
    static let sheetHeight: CGFloat = 560
    static let sheetMaximumHeight: CGFloat = 600

    static func sheetHeight(section: SettingsSection, query: String) -> CGFloat {
        sheetHeight
    }

}

/// First-class preferences canvas. Logical settings sections remain precise,
/// while the presentation has five compact pages that all fit the native sheet.
struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var navigation: MainWindowModel
    var scrolls: Bool

    init(model: SettingsModel, navigation: MainWindowModel, scrolls: Bool = true) {
        self.model = model
        self.navigation = navigation
        self.scrolls = scrolls
    }

    var body: some View {
        let pages = SettingsPage.matching(navigation.settingsQuery)
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            search
            if let page = visiblePage(in: pages) {
                SettingsPageTabs(pages: pages, selected: pageBinding(in: pages))
                content(for: page)
            } else {
                EmptyState("No matching settings",
                           detail: "Try a control such as goal, visits, timestamps or privacy.",
                           icon: "magnifyingglass")
                    .frame(maxHeight: .infinity)
            }
        }
        .padding(Tokens.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(StoryStyle.canvas)
    }

    private var search: some View {
        HStack(spacing: Tokens.Space.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search settings", text: $navigation.settingsQuery)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, Tokens.Space.m)
        .frame(height: 36)
        .background(StoryStyle.card, in: RoundedRectangle(cornerRadius: Tokens.Radius.nested,
                                                           style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous)
            .stroke(StoryStyle.line, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search settings")
        .accessibilitySortPriority(2)
    }

    @ViewBuilder private func content(for page: SettingsPage) -> some View {
        let sections = page.sections(matching: navigation.settingsQuery)
        let detail = VStack(alignment: .leading, spacing: Tokens.Space.l) {
            ForEach(sections) { section in
                if !navigation.settingsQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label("\(page.title) — \(section.title)", systemImage: section.symbol)
                        .font(Tokens.Typography.sectionTitle)
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                }
                SettingsGroups(model: model, section: section)
            }
        }
        .frame(maxWidth: SettingsLayout.detailMeasure, alignment: .topLeading)
        .accessibilitySortPriority(1)

        if scrolls {
            ScrollView { detail.padding(.bottom, Tokens.Space.l) }
                // A new page or search result starts at its first control.
                // The search field lives outside this identity, retaining focus.
                .id("\(page.rawValue):\(navigation.settingsQuery)")
        } else {
            detail.frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func visiblePage(in pages: [SettingsPage]) -> SettingsPage? {
        guard !pages.isEmpty else { return nil }
        let selected = SettingsPage(section: navigation.settingsSection)
        return pages.contains(selected) ? selected : pages[0]
    }

    private func pageBinding(in pages: [SettingsPage]) -> Binding<SettingsPage> {
        Binding(
            get: { visiblePage(in: pages) ?? SettingsPage(section: navigation.settingsSection) },
            set: { navigation.settingsSection = $0.sections[0] })
    }
}
