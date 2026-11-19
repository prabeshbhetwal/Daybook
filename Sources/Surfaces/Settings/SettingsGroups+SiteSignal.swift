import AppKit
import SwiftUI

private struct SiteSignalModelKey: EnvironmentKey {
    static let defaultValue = SiteSignalModel.unavailable
}

extension EnvironmentValues {
    /// The Settings window's Site signal model. Anywhere else (checks, stills)
    /// it is one that can do nothing, so the panel shows what every Mac shows
    /// until a probe report opens the gate.
    var siteSignal: SiteSignalModel {
        get { self[SiteSignalModelKey.self] }
        set { self[SiteSignalModelKey.self] = newValue }
    }
}

/// Settings › Privacy › Site signal: the opt-in switch and its state, the apps
/// it reads, Remember sites with its list, and what Daybook can see on this Mac.
struct SiteSignalSection: View {
    let groups: SettingsGroups
    let onDeviceAI: Bool
    @Environment(\.siteSignal) private var model

    var body: some View { SiteSignalPanel(groups: groups, model: model, onDeviceAI: onDeviceAI) }
}

private struct SiteSignalPanel: View {
    let groups: SettingsGroups
    @ObservedObject var model: SiteSignalModel
    let onDeviceAI: Bool

    var body: some View {
        SurfacePanel(title: "Site signal", layout: groups.layout) {
            groups.toggleRow("Read the kind of site in the front browser tab", detail: model.stateText,
                             isOn: $model.isOn)
                .disabled(!model.canChangeSwitch)
            if model.state == .awaitingPermission {
                groups.systemSettingsRow("Nothing is read until Daybook is allowed in Privacy & Security › Accessibility.",
                                         button: "Open Accessibility Settings",
                                         action: model.openAccessibilitySettings)
            }
            if model.canChangeApps {
                groups.rowDivider
                groups.preferenceRow("Apps Daybook reads") {
                    Button("Change Apps…", action: model.changeApps)
                        .accessibilityHint("Chooses the apps whose front tab Daybook reads")
                }
            }
            groups.rowDivider
            groups.toggleRow("Remember sites", detail: SiteSignalConstants.rememberDisclosure, isOn: $model.remembers)
                .disabled(!model.canChangeRemembers)
                .confirmationDialog(SiteSignalModel.forgetTitle(model.pendingForgetCount ?? 0),
                                    isPresented: Binding(get: { model.pendingForgetCount != nil },
                                                         set: { if !$0 { model.cancelForgetSites() } }),
                                    titleVisibility: .visible) {
                    Button("Delete", role: .destructive, action: model.confirmForgetSites)
                    Button("Cancel", role: .cancel, action: model.cancelForgetSites)
                } message: {
                    Text("Turning off Remember sites deletes the list. This cannot be undone.")
                }
            if model.remembers { rememberedSites }
            groups.rowDivider
            whatDaybookSees
        }
        .sheet(isPresented: Binding(get: { model.appChoice != nil },
                                    set: { if !$0 { model.cancelAppChoice() } })) {
            SiteSignalConsentSheet(model: model)
        }
        // Permission is granted in System Settings, so it is read again on return; no timer.
        .onAppear(perform: model.refreshTrust)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshTrust()
        }
        .announcesChanges(to: model.refused ? SiteSignalModel.refusal : nil)
    }

    @ViewBuilder private var rememberedSites: some View {
        ForEach(model.rememberedSites) { site in
            HStack(spacing: Tokens.Space.m) {
                Text(site.name)
                    .font(Tokens.Typography.rowTitle)
                    .textSelection(.enabled)
                Spacer(minLength: Tokens.Space.m)
                Text(site.kind.displayName)
                    .font(Tokens.Typography.body)
                    .foregroundStyle(StoryStyle.supportingInk)
                Button("Remove") { model.forget(site.name) }
                    .accessibilityLabel("Remove \(site.name)")
            }
        }
        HStack(spacing: Tokens.Space.s) {
            TextField("Site, such as example.com", text: $model.newSite)
                .textFieldStyle(.roundedBorder)
                .onSubmit(model.addSite)
                .accessibilityLabel("Site to remember")
            RowMenu("Kind of site", selection: $model.newSiteKind, options: SiteKind.allCases) { $0.displayName }
                .fixedSize()
            Button("Add", action: model.addSite)
                .disabled(!model.canAdd)
                .accessibilityHint("Remembers the site with the kind chosen beside it")
        }
        if model.refused { groups.explanation(SiteSignalModel.refusal) }
    }

    private var whatDaybookSees: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text("What Daybook can see now")
                .font(Tokens.Typography.label)
                .accessibilityAddTraits(.isHeader)
            ForEach(model.tiers(onDeviceAI: onDeviceAI), id: \.title) { tier in
                groups.readOnlyRow(tier.title, value: tier.on ? "On" : "Off")
            }
        }
    }
}
