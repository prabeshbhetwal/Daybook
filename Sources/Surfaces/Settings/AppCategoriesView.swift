import SwiftUI

extension SettingsGroups {
    var appCategoriesPanel: some View {
        SurfacePanel(title: "App categories", layout: layout) {
            AppCategoriesView(model: model)
        }
    }
}

/// Every app on this Mac by the kind of work it is, each with its pill and
/// where its category came from. "Everything else" folds away: it is the
/// long tail, and the categories that matter sit above it.
struct AppCategoriesView: View {
    @ObservedObject var model: SettingsModel
    @State private var query = ""
    @State private var showsEverythingElse = false

    private var overrides: [String: String] { model.purposeOverrides }

    private var applications: [InstalledApplication] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = model.installedAppCatalog.applications.filter(\.isInstalled)
        return value.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(value) }
    }

    var body: some View {
        let byPurpose = Dictionary(grouping: applications) {
            PurposeMap.shownPurpose(for: $0.bundleID, overrides: overrides)
        }
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Text("Daybook sorts each app by the kind of work it is. Change any that look wrong; past days follow.")
                .font(Tokens.Typography.body)
                .foregroundStyle(StoryStyle.supportingInk)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Search apps", text: $query).textFieldStyle(.roundedBorder)
            if applications.isEmpty {
                EmptyState(query.isEmpty ? "Looking for apps" : "No matching apps",
                           detail: query.isEmpty ? nil : "Try part of the app's name.",
                           icon: "magnifyingglass")
            }
            ForEach(AppPurpose.allCases, id: \.self) { purpose in
                if let apps = byPurpose[purpose], !apps.isEmpty {
                    section(purpose, apps)
                }
            }
        }
        .onAppear { model.installedAppCatalog.refresh() }
    }

    private func section(_ purpose: AppPurpose, _ apps: [InstalledApplication]) -> some View {
        // A search shows every match; otherwise the long tail waits behind a button.
        let folded = purpose == .utility && query.isEmpty && !showsEverythingElse
        return VStack(alignment: .leading, spacing: 2.zoomed) {
            HStack(spacing: Tokens.Space.s) {
                AppPurposeLabel(purpose: purpose).font(Tokens.Typography.label)
                Text("\(apps.count)").monospacedDigit()
                    .font(Tokens.Typography.body).foregroundStyle(StoryStyle.supportingInk)
                Spacer(minLength: 0)
                if purpose == .utility && query.isEmpty {
                    Button(showsEverythingElse ? "Hide" : "Show") { showsEverythingElse.toggle() }
                        .buttonStyle(StoryLinkStyle())
                        .accessibilityLabel(showsEverythingElse ? "Hide everything else" : "Show everything else")
                }
            }
            .padding(.top, Tokens.Space.s)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isHeader)
            if !folded {
                ForEach(apps) { app in row(app, purpose) }
            }
        }
    }

    private func row(_ app: InstalledApplication, _ purpose: AppPurpose) -> some View {
        let source = PurposeMap.source(for: app.bundleID, overrides: overrides)
        return HStack(spacing: Tokens.Space.s) {
            AppIcon(bundleID: app.bundleID, size: 22.zoomed, appName: app.name)
            VStack(alignment: .leading, spacing: 1.zoomed) {
                Text(app.name).font(Tokens.Typography.control).lineLimit(1)
                Text(source.label).font(Tokens.Typography.caption)
                    .foregroundStyle(StoryStyle.supportingInk)
            }
            Spacer(minLength: Tokens.Space.s)
            AppPurposePill(bundleID: app.bundleID, appName: app.name, purpose: purpose, source: source) { choice in
                var next = overrides
                next[app.bundleID] = choice?.rawValue
                model.purposeOverrides = next
            }
        }
        .padding(.vertical, 3.zoomed)
        .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
    }
}
