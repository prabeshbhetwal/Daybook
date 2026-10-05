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
                .font(Tokens.Typography.headline)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(message)
                .font(Tokens.Typography.rowTitle)
            if let detail {
                Text(detail)
                    .font(Tokens.Typography.body)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
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
                .font(Tokens.Typography.label)
                .foregroundStyle(StoryStyle.attentionInk)
            Text(message)
                .font(Tokens.Typography.body)
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
        // One element with one label; without `.ignore` the label sat over
        // the warning glyph and the message, read again beneath it.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Integrity notice: \(message)")
    }
}


/// Draws its content only when `value` changes. The store publishes every
/// second while anything is live, and a menu redrawn while it is open loses
/// the item under the pointer: the highlight blinks off each second. A menu
/// is wrapped in one of these, keyed by everything it shows, so it redraws
/// only when that does. Nothing inside may observe the store itself.
private struct RedrawsOn<Value: Equatable, Content: View>: View, Equatable {
    let value: Value
    let content: Content

    var body: some View { content }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.value == rhs.value }
}

extension View {
    /// See `RedrawsOn`.
    func redrawn<Value: Equatable>(on value: Value) -> some View {
        RedrawsOn(value: value, content: self).equatable()
    }
}
