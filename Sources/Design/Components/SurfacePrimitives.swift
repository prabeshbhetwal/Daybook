import SwiftUI

struct SurfacePanel<Content: View>: View {
    @Environment(\.focusInterfaceDensity) private var density
    let title: String?
    let layoutOverride: InterfaceDensity.Layout?
    let showsHeader: Bool
    @ViewBuilder let content: Content

    init(
        title: String? = nil,
        layout: InterfaceDensity.Layout? = nil,
        showsHeader: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.layoutOverride = layout
        self.showsHeader = showsHeader
        self.content = content()
    }

    private var layout: InterfaceDensity.Layout {
        layoutOverride ?? density.layout
    }

    var body: some View {
        VStack(alignment: .leading, spacing: layout.sectionSpacing) {
            if let title, showsHeader {
                SectionHeader(title: title)
            }
            content
        }
        .padding(layout.insetPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Colour.surface,
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.panel,
                                         style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.panel, style: .continuous)
                .strokeBorder(Tokens.Colour.line, lineWidth: 1)
        )
    }
}

struct MetricLine: View {
    @Environment(\.focusInterfaceDensity) private var density
    let label: String
    let value: String
    var note: String?
    var tint: Color = .primary
    var isDense: Bool = false
    var layout: InterfaceDensity.Layout?

    private var effectiveLayout: InterfaceDensity.Layout {
        layout ?? density.layout
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.m) {
            Text(label)
                .font(Tokens.Typography.rowTitle)
                .foregroundStyle(.secondary)
            Spacer(minLength: Tokens.Space.s)
            VStack(alignment: .trailing, spacing: 1) {
                Text(value)
                    .font(Tokens.Typography.metricValue)
                    .foregroundStyle(isDense
                                     ? AnyShapeStyle(.secondary)
                                     : AnyShapeStyle(tint))
                if let note {
                    Text(note)
                        .font(Tokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: effectiveLayout.rowHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([label, value, note].compactMap { $0 }.joined(separator: ", "))
    }
}

struct AppUsageRow: View {
    @Environment(\.focusInterfaceDensity) private var density
    let appName: String
    let bundleID: String?
    let rank: Int
    let seconds: TimeInterval
    let share: Double?
    let layoutOverride: InterfaceDensity.Layout?
    var onRow: (() -> Void)?

    init(appName: String, bundleID: String? = nil, rank: Int = 0, seconds: TimeInterval,
         share: Double? = nil, layout: InterfaceDensity.Layout? = nil,
         onRow: (() -> Void)? = nil) {
        self.appName = appName
        self.bundleID = bundleID
        self.rank = rank
        self.seconds = seconds
        self.share = share
        self.layoutOverride = layout
        self.onRow = onRow
    }

    private var layout: InterfaceDensity.Layout {
        layoutOverride ?? density.layout
    }

    @ViewBuilder
    var body: some View {
        if let onRow {
            Button(action: onRow) { row }
                .buttonStyle(StoryPressStyle())
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: Tokens.Space.s) {
            AppSwatch(rank: rank, bundleID: bundleID, appName: appName, size: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(appName)
                    .font(Tokens.Typography.rowTitle)
                    .lineLimit(1)
                Text(Tokens.preciseDuration(seconds))
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let share {
                DataBar(share: min(1, max(0, share)),
                        tint: Tokens.Palette.app(rank: rank))
                    .frame(width: 90)
            }
        }
        .frame(minHeight: layout.rowHeight)
        .contentShape(Rectangle())
        .accessibilityLabel("\(appName), \(Tokens.preciseDuration(seconds))")
    }
}

/// One column heading in a data table. A table states its measures once, here,
/// instead of repeating a label beside every value in every row.
struct TableColumnHeader: View {
    let title: String
    var width: CGFloat?
    var alignment: Alignment = .trailing

    var body: some View {
        Text(title)
            .font(Tokens.Typography.metadata)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(width: width, alignment: alignment)
            .accessibilityAddTraits(.isHeader)
    }
}

struct EmptyState: View {
    let message: String
    let detail: String?
    let icon: String

    init(_ message: String, detail: String? = nil, icon: String = "tray") {
        self.message = message
        self.detail = detail
        self.icon = icon
    }

    var body: some View {
        VStack(spacing: Tokens.Space.s) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text(message)
                .font(Tokens.Typography.rowTitle)
            if let detail {
                Text(detail)
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
    }
}

struct IntegrityNotice: View {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Space.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Tokens.Colour.attention)
            Text(message)
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Tokens.Space.s)
        .background(Tokens.Colour.attention.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.nested,
                                         style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous)
                .strokeBorder(Tokens.Colour.attention.opacity(0.22), lineWidth: 1)
        )
        .accessibilityLabel("Integrity notice: \(message)")
    }
}

struct SettingsRow: View {
    @Environment(\.focusInterfaceDensity) private var density
    let title: String
    let value: String?
    let layoutOverride: InterfaceDensity.Layout?
    let accessory: AnyView?

    init(_ title: String, value: String? = nil,
         layout: InterfaceDensity.Layout? = nil) {
        self.title = title
        self.value = value
        self.layoutOverride = layout
        self.accessory = nil
    }

    init<Accessory: View>(_ title: String, value: String? = nil,
                          layout: InterfaceDensity.Layout? = nil,
                          @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.value = value
        self.layoutOverride = layout
        self.accessory = AnyView(accessory())
    }

    private var layout: InterfaceDensity.Layout {
        layoutOverride ?? density.layout
    }

    var body: some View {
        HStack(alignment: .center, spacing: Tokens.Space.s) {
            Text(title)
                .font(Tokens.Typography.rowTitle)
            Spacer()
            if let value {
                Text(value)
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }
            if let accessory {
                accessory
                    .font(Tokens.Typography.metadata)
            }
        }
        .frame(minHeight: layout.rowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
