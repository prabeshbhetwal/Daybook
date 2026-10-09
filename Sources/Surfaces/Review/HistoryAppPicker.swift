import SwiftUI

/// The app filter's choices, laid out as a grid rather than a menu's single
/// column: a native menu cannot have columns, and a long history holds
/// scores of apps. Presented by `FilterChip` in a popover; "All apps" sits
/// above a grid that scrolls once it outgrows `maxGridHeight`.
///
/// Built from plain values so it never observes the store: the chip around it
/// is redrawn only when the list changes, not on each second the store
/// publishes.
struct HistoryAppPicker: View {
    struct Entry: Identifiable, Equatable {
        let id: String
        let name: String
    }

    let apps: [Entry]
    let picked: String?
    let onPick: (String?) -> Void
    @Environment(\.dismiss) private var dismiss

    private static let columnCount = 3
    private static var cellHeight: CGFloat { 36.zoomed }
    private static var maxGridHeight: CGFloat { 288.zoomed }
    private static var width: CGFloat { 540.zoomed }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Tokens.Radius.well, style: .continuous) }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Tokens.Space.xs), count: Self.columnCount)
    }

    /// Exact, so the popover is no taller than its rows until the cap.
    private var gridHeight: CGFloat {
        let rows = CGFloat((apps.count + Self.columnCount - 1) / Self.columnCount)
        let spacing = Tokens.Space.xs
        return min(Self.maxGridHeight, rows * Self.cellHeight + max(0, rows - 1) * spacing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            cell(title: "All apps", isSelected: picked == nil, help: "Show every app") {
                Image(systemName: "app")
                    .frame(width: 20.zoomed, height: 20.zoomed)
                    .foregroundStyle(.secondary)
            } action: { choose(nil) }
            ScrollView {
                LazyVGrid(columns: columns, spacing: Tokens.Space.xs) {
                    ForEach(apps) { app in
                        cell(title: app.name, isSelected: picked == app.id, help: app.name) {
                            AppIcon(bundleID: app.id, size: 20.zoomed, appName: app.name)
                        } action: { choose(app.id) }
                    }
                }
            }
            .frame(height: gridHeight)
        }
        .padding(Tokens.Space.m)
        .frame(width: Self.width)
    }

    private func choose(_ bundleID: String?) {
        onPick(bundleID)
        dismiss()
    }

    private func cell<Icon: View>(title: String, isSelected: Bool, help: String,
                                  @ViewBuilder icon: () -> Icon,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Tokens.Space.s) {
                icon()
                Text(title)
                    .font(Tokens.Typography.control)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isSelected ? AnyShapeStyle(StoryStyle.action) : AnyShapeStyle(.primary))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Tokens.Space.s)
            .frame(maxWidth: .infinity, minHeight: Self.cellHeight, maxHeight: Self.cellHeight, alignment: .leading)
            .background(isSelected ? AnyShapeStyle(StoryStyle.action.opacity(0.12)) : AnyShapeStyle(.clear), in: shape)
            .overlay(shape.strokeBorder(isSelected ? StoryStyle.action.opacity(0.35) : .clear))
            .contentShape(shape)
        }
        .buttonStyle(StoryPressStyle(hovers: true, cornerRadius: Tokens.Radius.well))
        .help(help)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
