import SwiftUI

/// The search that reaches the whole archive: a field for names, notes,
/// apps, categories and dates, the two menus that narrow it, and a way to
/// clear them. It heads History, so it is always there to type into.
struct HistoryFindBar: View {
    @ObservedObject var store: SessionStore
    /// Bumped by ⌘F; each bump puts the cursor in the field.
    let focusRequest: Int
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Tokens.Space.s) {
                field
                appMenu
                workTypeMenu
                clearButton
            }
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                field
                HStack(spacing: Tokens.Space.s) {
                    appMenu
                    workTypeMenu
                    clearButton
                }
            }
        }
        .onChange(of: focusRequest) { _ in fieldFocused = true }
    }

    private var field: some View {
        HStack(spacing: Tokens.Space.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Find a session: name, note, app, category or date", text: queryBinding)
                .textFieldStyle(.plain)
                .focused($fieldFocused)
                .onExitCommand { fieldFocused = false }
            if !store.historyFilter.query.isEmpty {
                Button { store.setHistoryQuery("") } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Tokens.Space.m)
        .frame(minHeight: 32)
        .background(Tokens.Colour.elevated,
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous)
            .strokeBorder(Tokens.Colour.line))
        .accessibilityLabel("Find a session")
    }

    /// Only while something is being searched.
    @ViewBuilder private var clearButton: some View {
        if store.historyFilter.isActive {
            Button("Clear") {
                store.clearHistoryFilters()
                fieldFocused = false
            }
            .buttonStyle(StoryLinkStyle())
            .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
            .accessibilityLabel("Clear search and filters")
        }
    }

    private var appMenu: some View {
        Menu {
            Button("All apps") { store.setHistoryApp(nil) }
            Divider()
            ForEach(store.historyAppBundleIDs, id: \.self) { bundleID in
                Button(store.historyAppName(for: bundleID)) { store.setHistoryApp(bundleID) }
            }
        } label: {
            Label(store.historyFilter.appBundleID.map(store.historyAppName(for:)) ?? "All apps",
                  systemImage: "app")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
        .accessibilityLabel("App filter, selected "
                            + (store.historyFilter.appBundleID.map(store.historyAppName(for:)) ?? "all apps"))
    }

    private var workTypeMenu: some View {
        Menu {
            Button { store.setHistoryWorkType(nil) } label: {
                Label("All categories", systemImage: "square.grid.2x2").labelStyle(.titleAndIcon)
            }
            Divider()
            ForEach(WorkType.allCases) { type in
                Button { store.setHistoryWorkType(type) } label: {
                    Label(type.displayName, systemImage: type.symbolName).labelStyle(.titleAndIcon)
                }
            }
        } label: {
            Label(store.historyFilter.workType?.displayName ?? "All categories",
                  systemImage: store.historyFilter.workType?.symbolName ?? "square.grid.2x2")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
        .accessibilityLabel("Category filter, selected "
                            + (store.historyFilter.workType?.displayName ?? "all categories"))
    }

    private var queryBinding: Binding<String> {
        Binding(get: { store.historyFilter.query }, set: store.setHistoryQuery)
    }
}
