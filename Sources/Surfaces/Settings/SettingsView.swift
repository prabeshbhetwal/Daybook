import SwiftUI

/// Dimensions include StorySheet's title band. Every category and search result
/// shares this bounded frame; only genuinely overflowing page content scrolls.
/// Sized like a settings window rather than a dialog: wide enough for a
/// sidebar beside a reading measure, and as tall as the smallest window
/// allows with a margin around it.
enum SettingsLayout {
    static let sheetWidth: CGFloat = 1_000
    static let sidebarWidth: CGFloat = 196
    static let detailMeasure: CGFloat = 720
    static let sheetHeight: CGFloat = 720
    static let sheetMaximumHeight: CGFloat = 740
    /// Room kept to the window's edge when the window is smaller than the
    /// sheet would like to be.
    static let windowMargin: CGFloat = 40

    /// The sheet wants its full size; a smaller window gets a sheet that
    /// fits it, never one that runs off the edge.
    static func sheetSize(for kind: StorySheetKind, within window: CGSize?) -> CGSize {
        let wanted = kind == .settings ? CGSize(width: sheetWidth, height: sheetHeight)
                                       : CGSize(width: 880, height: 570)
        guard let window else { return wanted }
        return CGSize(width: min(wanted.width, max(600, window.width - windowMargin * 2)),
                      height: min(wanted.height, max(420, window.height - windowMargin * 2)))
    }

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
        HStack(spacing: 0) {
            sidebar(pages: pages)
                .frame(width: SettingsLayout.sidebarWidth)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(StoryStyle.rail)
            Divider()
            Group {
                if let page = visiblePage(in: pages) {
                    content(for: page)
                } else {
                    EmptyState("No matching settings",
                               detail: "Try a control such as goal, visits, timestamps or privacy.",
                               icon: "magnifyingglass")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(StoryStyle.canvas)
        .environment(\.categoryEditorRequest, navigation.categoryEditorRequest)
    }

    private func sidebar(pages: [SettingsPage]) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            search
            if !pages.isEmpty {
                SettingsSidebarList(pages: pages, selected: pageBinding(in: pages))
            }
        }
        .padding(Tokens.Space.m)
    }

    private var search: some View {
        HStack(spacing: Tokens.Space.xs) {
            Image(systemName: "magnifyingglass")
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search", text: $navigation.settingsQuery)
                .textFieldStyle(.plain)
                .font(Tokens.Typography.control)
        }
        .padding(.horizontal, Tokens.Space.s)
        .frame(height: 30)
        .background(StoryStyle.card, in: RoundedRectangle(cornerRadius: Tokens.Radius.well,
                                                           style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.well, style: .continuous)
            .stroke(StoryStyle.line, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search settings")
        .accessibilitySortPriority(2)
    }

    @ViewBuilder private func content(for page: SettingsPage) -> some View {
        let query = navigation.settingsQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let sections = page.sections(matching: navigation.settingsQuery)
        let detail = VStack(alignment: .leading, spacing: Tokens.Space.l) {
            VStack(alignment: .leading, spacing: 3) {
                Text(query.isEmpty ? page.title : "\(page.title) · matching “\(query)”")
                    .font(Tokens.Typography.pageTitle)
                    .accessibilityAddTraits(.isHeader)
                Text(page.summary)
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(sections) { section in
                SettingsGroups(model: model, section: section)
            }
        }
        .padding(Tokens.Space.xl)
        .frame(maxWidth: SettingsLayout.detailMeasure + Tokens.Space.xl * 2, alignment: .topLeading)
        .accessibilitySortPriority(1)

        if scrolls {
            ScrollView { detail }
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
            set: { page in
                // A page change is a view being replaced; give it a transaction.
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    navigation.settingsSection = page.sections[0]
                } else {
                    withAnimation(Tokens.Motion.swap) { navigation.settingsSection = page.sections[0] }
                }
            })
    }
}
