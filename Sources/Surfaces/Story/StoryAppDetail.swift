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
        "\(app.appName), \(Tokens.spent(app.total)), \(DurationText.percent(app.share, spoken: true))"
    }

    private var row: some View {
        VStack(spacing: Tokens.Space.xs) {
            HStack(spacing: 6.zoomed) {
                AppIcon(bundleID: app.bundleID, size: 14.zoomed, appName: app.appName)
                Text(app.appName).lineLimit(1)
                Spacer(minLength: Tokens.Space.xs)
                Text(durations: Tokens.preciseDuration(app.total))
                    .monospacedDigit().foregroundStyle(.secondary)
                if onOpen != nil {
                    Image(systemName: "chevron.right")
                        .font(Tokens.Typography.micro)
                        .foregroundStyle(.secondary)
                }
            }
            .font(Tokens.Typography.body)
            GeometryReader { geometry in
                Capsule().fill(StoryStyle.line)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Tokens.Palette.app(rank: rank))
                            .frame(width: geometry.size.width * min(1, max(0, app.share)))
                    }
            }
            .frame(height: 3.zoomed)
        }
        .padding(.vertical, 3.zoomed)
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
    /// History's open day; nil is the dashboard's.
    var day: Date?
    let onDismiss: () -> Void
    @StateObject private var showAll = BoolBox()

    var body: some View {
        let evidence = store.storyAppEvidence(for: bundleID, period: nil, day: day)
        let entries = evidence.visits
        let appName = entries.first?.appName ?? bundleID
        let shown = showAll.value ? entries.count : min(store.menuSessionCount, entries.count)
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            HStack(spacing: 10.zoomed) {
                AppIcon(bundleID: bundleID, size: 28.zoomed, appName: appName)
                VStack(alignment: .leading, spacing: 2.zoomed) {
                    Text(appName).font(Tokens.Typography.heading)
                        .accessibilityAddTraits(.isHeader)
                    Text(Tokens.longDate(day ?? store.selectedDay))
                        .font(Tokens.Typography.body).foregroundStyle(.secondary)
                }
                Spacer()
                Text(durations: Tokens.preciseDuration(evidence.total))
                    .font(Tokens.Typography.heading.monospacedDigit())
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(StoryLinkStyle())
                .padding(.leading, Tokens.Space.s)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close app detail")
                .help("Close app detail")
            }
            Text("Recorded app visits · newest first")
                .font(Tokens.Typography.body).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: Tokens.Space.s) {
                    ForEach(entries.prefix(shown)) { entry in
                        HStack(alignment: .firstTextBaseline) {
                            Text(Tokens.timeRange(entry.start, entry.end))
                            Spacer(minLength: Tokens.Space.m)
                            Text(durations: Tokens.preciseDuration(entry.seconds)).monospacedDigit()
                        }
                        .font(Tokens.Typography.body)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .frame(height: min(260.zoomed, CGFloat(max(1, shown)) * 26.zoomed))
            if shown < entries.count {
                Button("Show all \(entries.count) visits") { showAll.value = true }
                    .buttonStyle(StoryLinkStyle())
            }
            if entries.isEmpty {
                Text("No app use was recorded on this day.")
                    .font(Tokens.Typography.body).foregroundStyle(.secondary)
            }
            Text(shown < entries.count
                 ? "The list shows the newest \(shown) visits, set by Recent app visits in Settings. "
                    + "The total counts every visit."
                 : "The total counts every visit.")
                .font(Tokens.Typography.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Tokens.Space.xl)
        .frame(width: 380.zoomed)
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
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Button { if let onToggle { onToggle() } else { expanded.value.toggle() } } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2.zoomed) {
                        Text("App use outside a session").font(Tokens.Typography.label)
                        Text(Tokens.timeRange(span.start, span.end))
                            .font(Tokens.Typography.body).foregroundStyle(.secondary)
                        // No session covers this block, so the Mac's power is
                        // the one fact the story can add to it.
                        if let power {
                            Label(power.headline, systemImage: power.symbolName)
                                .font(Tokens.Typography.body).foregroundStyle(.secondary)
                                .accessibilityLabel("Power: \(power.headline)")
                        }
                    }
                    Spacer(minLength: Tokens.Space.s)
                    Text(durations: Tokens.preciseDuration(seconds))
                        .font(Tokens.Typography.body.monospacedDigit())
                    Image(systemName: "chevron.right")
                        .font(Tokens.Typography.caption).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(StoryPressStyle())
            .accessibilityValue(open ? "Expanded" : "Collapsed")
            if open {
                ForEach(Array(store.appRanks(within: [span]).enumerated()), id: \.element.id) { index, app in
                    StoryAppRow(app: app, rank: store.storyAppColourIndices[app.bundleID] ?? index)
                }
                if let detail = power?.detail {
                    Text(detail).font(Tokens.Typography.body).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(StoryStyle.entryInsets(for: density))
        .background(StoryStyle.well.opacity(0.6),
                    in: RoundedRectangle(cornerRadius: StoryStyle.entryRadius))
    }
}
