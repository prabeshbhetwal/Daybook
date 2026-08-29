import SwiftUI

struct SurfacePanel<Content: View>: View {
    let title: String?
    let layout: InterfaceDensity.Layout
    let showsHeader: Bool
    @ViewBuilder let content: Content

    init(
        title: String? = nil,
        layout: InterfaceDensity.Layout = .comfortable,
        showsHeader: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.layout = layout
        self.showsHeader = showsHeader
        self.content = content()
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
    let label: String
    let value: String
    var note: String?
    var tint: Color = .primary
    var isDense: Bool = false
    var layout: InterfaceDensity.Layout = .comfortable

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
                        .font(Tokens.Typography.detail)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: layout.rowHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([label, value, note].compactMap { $0 }.joined(separator: ", "))
    }
}

struct AppUsageRow: View {
    let appName: String
    let bundleID: String?
    let rank: Int
    let seconds: TimeInterval
    let share: Double?
    let layout: InterfaceDensity.Layout
    var onRow: (() -> Void)?

    init(appName: String, bundleID: String? = nil, rank: Int = 0, seconds: TimeInterval,
         share: Double? = nil, layout: InterfaceDensity.Layout = .comfortable,
         onRow: (() -> Void)? = nil) {
        self.appName = appName
        self.bundleID = bundleID
        self.rank = rank
        self.seconds = seconds
        self.share = share
        self.layout = layout
        self.onRow = onRow
    }

    @ViewBuilder
    var body: some View {
        if let onRow {
            Button(action: onRow) { row }
                .buttonStyle(.plain)
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
    let title: String
    let value: String?
    let layout: InterfaceDensity.Layout
    let accessory: AnyView?

    init(_ title: String, value: String? = nil,
         layout: InterfaceDensity.Layout = .comfortable) {
        self.title = title
        self.value = value
        self.layout = layout
        self.accessory = nil
    }

    init<Accessory: View>(_ title: String, value: String? = nil,
                          layout: InterfaceDensity.Layout = .comfortable,
                          @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.value = value
        self.layout = layout
        self.accessory = AnyView(accessory())
    }

    var body: some View {
        HStack(alignment: .center, spacing: Tokens.Space.s) {
            Text(title)
                .font(Tokens.Typography.rowTitle)
            Spacer()
            if let value {
                Text(value)
                    .font(Tokens.Typography.detail)
                    .foregroundStyle(.secondary)
            }
            if let accessory {
                accessory
                    .font(Tokens.Typography.detail)
            }
        }
        .frame(minHeight: layout.rowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
