import SwiftUI

/// A Settings pop-up at one width for every row, so the menus down a page
/// form a single column against the trailing edge instead of each hugging its
/// own longest item.
///
/// A menu `Picker` cannot be given that width: on macOS 27 it draws at its
/// widest item whatever frame it is given and centres itself in that frame.
/// A bordered menu button sizes to its label, so the label carries the width
/// here, and the up-and-down chevron stands in for the hidden pull-down
/// indicator, so the control reads as the pop-up it replaces. The inline
/// picker inside still marks the current choice with a check.
struct RowMenu<Value: Hashable, Content: View>: View {
    private let title: String
    @Binding private var selection: Value
    private let value: String
    private let systemImage: String?
    private let content: Content

    /// `value` is what the closed menu shows: the chosen item's own text.
    init(_ title: String, selection: Binding<Value>, value: String, systemImage: String? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        _selection = selection
        self.value = value
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        Menu {
            Picker(title, selection: $selection) { content }
                .pickerStyle(.inline)
                .labelsHidden()
        } label: {
            HStack(spacing: Tokens.Space.xs) {
                if let systemImage { Image(systemName: systemImage) }
                Text(value)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: Tokens.Space.xs)
                Image(systemName: "chevron.up.chevron.down")
                    .font(Tokens.Typography.caption)
            }
            // The pop-up's own 13pt at 100%, but following the zoom, as the
            // width does; the platform's label stayed small at 140%.
            .font(Tokens.Typography.control)
            .frame(width: Tokens.Control.rowMenuLabelWidth)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(value)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

extension RowMenu where Content == RowMenuOptions<Value> {
    /// A plain list of choices, each named by `label`, which also names the
    /// closed menu, so the two cannot disagree.
    init(_ title: String, selection: Binding<Value>, options: [Value],
         label: @escaping (Value) -> String) {
        self.init(title, selection: selection, value: label(selection.wrappedValue)) {
            RowMenuOptions(options: options, label: label)
        }
    }
}

struct RowMenuOptions<Value: Hashable>: View {
    let options: [Value]
    let label: (Value) -> String

    var body: some View {
        ForEach(options, id: \.self) { Text(label($0)).tag($0) }
    }
}
