import SwiftUI

/// An opened card's apps, grouped by category: a bar split by category, one
/// summary line, then each category with its apps. Each app carries a small
/// pill that changes its category, with Undo where the change was made.
struct StoryAppGroups: View {
    let groups: [AppPurposeGroup]
    let store: SessionStore
    @ObservedObject var changes: PurposeChangeBox

    /// Apps shown under each heading; the rest are counted by the card's
    /// "N more apps · See Full Report".
    static let appsPerGroup = 2

    static func hiddenCount(_ groups: [AppPurposeGroup]) -> Int {
        groups.reduce(0) { $0 + max(0, $1.apps.count - appsPerGroup) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6.zoomed) {
            if groups.count > 1 { AppPurposeBar(groups: groups) }
            if let summary = AppPurposeGroups.summary(groups) {
                Text(summary)
                    .font(Tokens.Typography.body)
                    .foregroundStyle(StoryStyle.supportingInk)
            }
            // A notice another edit has since replaced is gone: its Undo would overwrite the newer choice.
            if let change = changes.last,
               PurposeMap.override(for: change.bundleID, in: store.purposeOverrides) == change.now {
                PurposeChangeNotice(change: change) {
                    store.setAppPurpose(change.previous, for: change.bundleID)
                    changes.last = nil
                }
            }
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 2.zoomed) {
                    heading(group)
                    ForEach(group.apps.prefix(Self.appsPerGroup)) { app in
                        HStack(spacing: Tokens.Space.s) {
                            StoryAppRow(app: app)
                            // A folded app keeps its own category: the heading may read Everything else.
                            pill(for: app, purpose: store.appPurpose(app.bundleID))
                        }
                    }
                }
                .padding(.top, Tokens.Space.xs)
            }
        }
    }

    private func heading(_ group: AppPurposeGroup) -> some View {
        HStack(spacing: Tokens.Space.s) {
            Image(systemName: group.purpose.symbolName)
                .font(Tokens.Typography.caption)
                .foregroundStyle(.white)
                .frame(width: 20.zoomed, height: 20.zoomed)
                .background(Tokens.Palette.purpose(group.purpose),
                            in: RoundedRectangle(cornerRadius: Tokens.Radius.mark))
                .accessibilityHidden(true)
            Text(group.purpose.displayName).font(Tokens.Typography.label)
            Spacer(minLength: Tokens.Space.xs)
            Text(durations: Tokens.preciseDuration(group.total))
                .font(Tokens.Typography.body)
                .monospacedDigit()
                .foregroundStyle(StoryStyle.supportingInk)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(group.purpose.displayName), \(Tokens.spent(group.total))")
        .accessibilityAddTraits(.isHeader)
    }

    private func pill(for app: AppRank, purpose: AppPurpose) -> some View {
        AppPurposePill(bundleID: app.bundleID, appName: app.appName, purpose: purpose,
                       source: store.appPurposeSource(app.bundleID), compact: true) { choice in
            let previous = store.setAppPurpose(choice, for: app.bundleID)
            changes.last = .init(bundleID: app.bundleID, appName: app.appName, previous: previous,
                                 now: choice, shown: store.appPurpose(app.bundleID))
        }
    }
}

/// The stretch split by category, each segment in its category's colour.
/// VoiceOver hears the figures; the bar itself is one element.
struct AppPurposeBar: View {
    let groups: [AppPurposeGroup]

    var body: some View {
        let total = max(1, groups.reduce(0) { $0 + $1.total })
        GeometryReader { geometry in
            let gaps = 2.zoomed * CGFloat(groups.count - 1)
            HStack(spacing: 2.zoomed) {
                ForEach(groups) { group in
                    Rectangle()
                        .fill(Tokens.Palette.purpose(group.purpose))
                        .frame(width: max(2.zoomed, (geometry.size.width - gaps) * group.total / total))
                }
            }
        }
        .frame(height: 8.zoomed)
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(groups.map { "\($0.purpose.displayName) \(Tokens.spent($0.total))" }
            .joined(separator: ", "))
    }
}
