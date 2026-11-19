import SwiftUI

/// The site signal's consent, with the apps it may read. Opened by turning the
/// switch on, and again by Change Apps…. Nothing is stored before Turn On, and
/// the Accessibility prompt comes only after it. Turn On is deliberately not the
/// Return key's button: consent takes a click.
struct SiteSignalConsentSheet: View {
    @ObservedObject var model: SiteSignalModel

    private var purpose: SiteSignalModel.Purpose { model.appChoice?.purpose ?? .turnOn }
    private var candidates: [SiteSignalModel.Candidate] { model.appChoice?.candidates ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Text(purpose.title)
                .font(Tokens.Typography.heading)
                .accessibilityAddTraits(.isHeader)
            Text(SiteSignalConstants.consentText)
                .font(Tokens.Typography.body)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                Text("Only the apps you tick are ever read.")
                    .font(Tokens.Typography.rowTitle)
                if candidates.isEmpty {
                    Text("No app on this Mac opens web links.")
                        .font(Tokens.Typography.body)
                        .foregroundStyle(StoryStyle.supportingInk)
                }
                ForEach(candidates) { app in
                    Toggle(app.name, isOn: Binding(get: { app.ticked },
                                                   set: { model.setTicked(app.bundleID, $0) }))
                        .toggleStyle(.checkbox)
                }
            }
            if purpose == .turnOn, !model.trusted {
                Text("Turn On then asks macOS for Accessibility permission. Nothing is read until you allow "
                     + "Daybook in Privacy & Security › Accessibility.")
                    .font(Tokens.Typography.body)
                    .foregroundStyle(StoryStyle.supportingInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Tokens.Space.s) {
                Spacer(minLength: 0)
                Button("Cancel", action: model.cancelAppChoice)
                    .keyboardShortcut(.cancelAction)
                Button(purpose.confirmTitle, action: model.confirmApps)
                    .disabled(!model.canConfirm)
                    .accessibilityHint(model.canConfirm ? "" : "Tick at least one app first")
            }
        }
        .padding(Tokens.Space.xl)
        .frame(width: 420.zoomed, alignment: .leading)
        .zoomRoot()
    }
}
