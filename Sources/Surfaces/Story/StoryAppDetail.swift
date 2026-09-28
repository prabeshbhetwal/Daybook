import SwiftUI

/// The compact app row used in both the rail and an opened entry. The duration
/// stays on the name's baseline; the bar explains its share without becoming
/// a second numeric column.
struct StoryAppRow: View {
    let app: AppRank
    let rank: Int
    var onOpen: (() -> Void)?
    @StateObject private var hovered = BoolBox()

    var body: some View {
        Group {
            if let onOpen {
                Button(action: onOpen) { row }
                    .buttonStyle(StoryPressStyle())
                    .accessibilityLabel(spokenLabel)
                    .accessibilityHint("Inspect recorded app visits")
            } else {
                row.accessibilityElement(children: .ignore)
                    .accessibilityLabel(spokenLabel)
            }
        }
        .onHover { hovered.value = $0 }
    }

    private var spokenLabel: String {
        "\(app.appName), \(Tokens.spent(app.total)), \(Int((app.share * 100).rounded())) per cent"
    }

    private var row: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                AppIcon(bundleID: app.bundleID, size: 14, appName: app.appName)
                Text(app.appName).lineLimit(1)
                Spacer(minLength: 4)
                Text(Tokens.preciseDuration(app.total))
                    .monospacedDigit().foregroundStyle(.secondary)
                if onOpen != nil {
                    Image(systemName: "chevron.right")
                        .font(Tokens.Typography.micro)
                        .foregroundStyle(.secondary)
                }
            }
            .font(Tokens.Typography.metadata)
            GeometryReader { geometry in
                Capsule().fill(StoryStyle.line)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Tokens.Palette.app(rank: rank))
                            .frame(width: geometry.size.width * min(1, max(0, app.share)))
                    }
            }
            .frame(height: 3)
        }
        .padding(.vertical, 3)
        .frame(minHeight: AccessibilityMetrics.minimumTargetSize)
        .background(hovered.value && onOpen != nil ? Tokens.Colour.hover : .clear,
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.mark))
        .contentShape(Rectangle())
    }
}

/// A read-only app drill-in for the day its source tile shows. It honours
/// the backed recent-visit preference without truncating totals.
struct StoryAppDetail: View {
    @ObservedObject var store: SessionStore
    let bundleID: String
    let onDismiss: () -> Void
    @StateObject private var showAll = BoolBox()

    var body: some View {
        let evidence = store.storyAppEvidence(for: bundleID, period: nil)
        let entries = evidence.visits
        let appName = entries.first?.appName ?? bundleID
        let shown = showAll.value ? entries.count : min(store.menuSessionCount, entries.count)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AppIcon(bundleID: bundleID, size: 28, appName: appName)
                VStack(alignment: .leading, spacing: 2) {
                    Text(appName).font(Tokens.Typography.sectionTitle)
                    Text(Tokens.longDate(store.selectedDay))
                        .font(Tokens.Typography.metadata).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Tokens.preciseDuration(evidence.total))
                    .font(Tokens.Typography.rowTitle.monospacedDigit())
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(StoryLinkStyle())
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close app detail")
                .help("Close app detail")
            }
            Text("Recorded app visits · newest first")
                .font(Tokens.Typography.metadata).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(entries.prefix(shown)) { entry in
                        HStack(alignment: .firstTextBaseline) {
                            Text(Tokens.timeRange(entry.start, entry.end))
                            Spacer(minLength: 12)
                            Text(Tokens.preciseDuration(entry.seconds)).monospacedDigit()
                        }
                        .font(Tokens.Typography.metadata)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .frame(height: min(260, CGFloat(max(1, shown)) * 26))
            if shown < entries.count {
                Button("Show all \(entries.count) visits") { showAll.value = true }
                    .buttonStyle(StoryLinkStyle())
            }
            if entries.isEmpty {
                Text("No app use was recorded on this day.")
                    .font(Tokens.Typography.metadata).foregroundStyle(.secondary)
            }
            Text("Visit limits affect this list only, never the total.")
                .font(Tokens.Typography.metadata).foregroundStyle(.secondary)
        }
        .padding(Tokens.Space.xl)
        .frame(width: 380)
        .background(StoryStyle.card)
        .onExitCommand(perform: onDismiss)
    }
}

/// Observed Mac use still belongs in the story when no focus session covers
/// it. It is not called a break or productivity, and it never earns goal credit.
struct StoryLooseAppUse: View {
    @ObservedObject var store: SessionStore
    let span: DateInterval
    let seconds: TimeInterval
    /// The day's shared open set drives this row, so Expand all reaches it;
    /// a row shown on its own keeps a flag of its own.
    var isOpen: Bool? = nil
    var onToggle: (() -> Void)? = nil
    @StateObject private var expanded = BoolBox()
    @Environment(\.focusInterfaceDensity) private var density

    private var open: Bool { isOpen ?? expanded.value }

    private var power: PowerContextSummary? { store.ambientPowerSummary(within: span) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { if let onToggle { onToggle() } else { expanded.value.toggle() } } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("App use outside a session").font(Tokens.Typography.metadata.weight(.medium))
                        Text(Tokens.timeRange(span.start, span.end))
                            .font(Tokens.Typography.metadata).foregroundStyle(.secondary)
                        // No session covers this block, so the Mac's power is
                        // the one fact the story can add to it.
                        if let power {
                            Label(power.headline, systemImage: power.symbolName)
                                .font(Tokens.Typography.metadata).foregroundStyle(.secondary)
                                .accessibilityLabel("Power: \(power.headline)")
                        }
                    }
                    Spacer(minLength: 8)
                    Text(Tokens.preciseDuration(seconds))
                        .font(Tokens.Typography.metadata.monospacedDigit())
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(Tokens.Typography.microLabel).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(StoryPressStyle())
            if open {
                ForEach(Array(store.appRanks(within: [span]).enumerated()), id: \.element.id) { index, app in
                    StoryAppRow(app: app, rank: store.storyAppColourIndices[app.bundleID] ?? index)
                }
                if let detail = power?.detail {
                    Text(detail).font(Tokens.Typography.metadata).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(StoryStyle.entryInsets(for: density))
        .background(StoryStyle.well.opacity(0.6),
                    in: RoundedRectangle(cornerRadius: StoryStyle.entryRadius))
    }
}
