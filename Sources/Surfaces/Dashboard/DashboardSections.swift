import SwiftUI

// Rows with hairline separators, never per-row cards: the native list idiom, and
// it lets icon, bar and number align on a real grid.

/// One line per session, precomputed so the type checker stays inside budget.
private func sessionLine(_ session: AppSession) -> String {
    let range = Tokens.timeRange(session.start, session.end)
    let attended = Tokens.preciseDuration(session.attended)
    guard session.visits > 1 else { return "\(range)  ·  \(attended)" }
    return "\(range)  ·  \(attended) over \(session.visits) visits"
}

/// Today-specific ranked app rows. Each row retains the stable app palette,
/// exact day total, share and full last-used range; selection routes back
/// through the ribbon so there is only one inspector state.
struct TodayAppsList: View {
    let apps: [AppRank]
    @ObservedObject var store: SessionStore
    var selectedBundleID: String?
    @StateObject private var hover = HoverBox()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "At the Mac",
                          trailing: apps.isEmpty ? nil
                            : (apps.count == 1 ? "1 app" : "\(apps.count) apps"))
                .padding(.bottom, Tokens.Space.xs)
            if apps.isEmpty {
                Text("No app activity recorded for this day.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, Tokens.Space.s)
            } else {
                ForEach(Array(apps.prefix(8).enumerated()), id: \.element.id) { index, app in
                    if index > 0 { Divider() }
                    row(app, rank: index)
                }
            }
        }
    }

    private func row(_ app: AppRank, rank: Int) -> some View {
        let selected = selectedBundleID == app.bundleID
        let span = store.span(for: app.bundleID)
        return Button { store.selectTodayApp(app.bundleID) } label: {
            HStack(spacing: Tokens.Space.s) {
                AppSwatch(rank: min(rank, 6), bundleID: app.bundleID,
                          appName: app.appName, size: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.appName)
                        .font(Tokens.Typography.rowTitle)
                        .lineLimit(1)
                    Text(span.map { Tokens.timeRange($0.start, $0.end) }
                         ?? "No recorded range")
                        .font(Tokens.Typography.metadata.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Tokens.Space.s)
                DataBar(share: app.share, tint: Tokens.Palette.app(rank: min(rank, 6)))
                    .frame(width: 72)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Tokens.preciseDuration(app.total))
                        .font(Tokens.Typography.rowTitle.monospacedDigit())
                    Text("\(Int((app.share * 100).rounded()))%")
                        .font(Tokens.Typography.metadata.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(width: 58, alignment: .trailing)
            }
            .padding(.horizontal, Tokens.Space.s)
            .frame(minHeight: Tokens.Density.compactRowHeight)
            .background(selected ? Tokens.Colour.focus.opacity(0.10)
                        : hover.id == app.bundleID ? Tokens.Colour.hover : Color.clear,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.nested,
                                             style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous)
                    .strokeBorder(Tokens.Colour.focus.opacity(selected ? 0.45 : 0), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(StoryPressStyle())
        .onHover { inside in
            hover.id = inside ? app.bundleID : nil
            store.highlightApp(inside ? app.bundleID : nil)
        }
        .help(selected ? "Close the app inspector" : "Inspect this app on the time ribbon")
        .accessibilityLabel("\(app.appName), \(Tokens.spent(app.total)), "
                            + "\(Int((app.share * 100).rounded()))% of At the Mac time")
    }
}

