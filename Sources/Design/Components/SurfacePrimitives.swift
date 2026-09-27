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

