import SwiftUI

/// Shown once to an install from before automatic backups: they start off,
/// so an update never uploads the reader's history on its own. One click
/// turns on a daily backup to iCloud Drive; Not now leaves them off, and
/// either answer ends the offer. Settings › Privacy has the full choice.
struct BackupOfferNotice: View {
    @ObservedObject var settings: SettingsModel

    var body: some View {
        if settings.backupOfferPending {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                Label {
                    Text("Daybook can now back itself up every day, to iCloud Drive or a folder you choose.")
                        .font(Tokens.Typography.body)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "externaldrive.badge.icloud")
                        .foregroundStyle(StoryStyle.action)
                }
                HStack(spacing: Tokens.Space.s) {
                    Button("Back up every day") { settings.answerBackupOffer(backUpDaily: true) }
                        .buttonStyle(StoryActionStyle(tint: StoryStyle.action))
                        .accessibilityHint("Backs up to iCloud Drive every day. Settings, Privacy changes where and how often.")
                    Button("Not now") { settings.answerBackupOffer(backUpDaily: false) }
                        .buttonStyle(StoryLinkStyle(tint: .secondary))
                        .padding(.leading, Tokens.Space.s)
                        .accessibilityHint("Leaves backups off. Settings, Privacy can turn them on later.")
                }
            }
            .padding(Tokens.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tokens.Colour.elevated,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
            .accessibilityElement(children: .contain)
        }
    }
}
