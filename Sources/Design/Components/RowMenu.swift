import SwiftUI

/// A Settings pop-up at one width for every row, so the menus down a page
/// form a single column against the trailing edge instead of each hugging its
/// own longest item.
///
/// A menu `Picker` cannot be given that width: on macOS 27 it draws at its
/// widest item whatever frame it is given and centres itself in that frame.
/// A bordered menu button sizes to its label there, so the label carries the
/// width, and the up-and-down chevron stands in for the hidden pull-down
/// indicator, so the control reads as the pop-up it replaces. The inline
/// picker inside still marks the current choice with a check.
///
/// Before macOS 27 a menu button is an AppKit pull-down that sizes to its
/// title and ignores both the label's frame and its own, so there the same
/// label sits on a bordered button, which keeps it, and the choices open as a
/// native menu over the control (`RowMenuAnchor`).
struct RowMenu<Value: Hashable>: View {
    private let title: String
    @Binding private var selection: Value
    private let items: [RowMenuItem<Value>]
    @State private var anchor = RowMenuAnchor()

    /// The closed menu shows the chosen item's own text and symbol, so the two
    /// cannot disagree.
    init(_ title: String, selection: Binding<Value>, items: [RowMenuItem<Value>]) {
        self.title = title
        _selection = selection
        self.items = items
    }

    /// A plain list of choices, each named by `label`.
    init(_ title: String, selection: Binding<Value>, options: [Value],
         label: @escaping (Value) -> String) {
        self.init(title, selection: selection, items: options.map { .option($0, label($0)) })
    }

    private var chosen: (text: String, systemImage: String?) {
        for case let .option(value, text, systemImage) in items where value == selection {
            return (text, systemImage)
        }
        return ("", nil)
    }

    var body: some View {
        Group {
            if #available(macOS 27, *) {
                menu
            } else {
                Button { anchor.popUp(items, selected: selection) { selection = $0 } } label: { label }
                    .buttonStyle(.bordered)
                    .background(RowMenuAnchorView(anchor: anchor))
            }
        }
        .fixedSize()
        .help(chosen.text)
        .accessibilityLabel(title)
        .accessibilityValue(chosen.text)
    }

    private var menu: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(items.indices, id: \.self) { index in
                    switch items[index] {
                    case let .option(value, text, systemImage?):
                        Label(text, systemImage: systemImage).labelStyle(.titleAndIcon).tag(value)
                    case let .option(value, text, nil):
                        Text(text).tag(value)
                    case .divider:
                        Divider()
                    }
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            label
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .menuIndicator(.hidden)
    }

    private var label: some View {
        HStack(spacing: Tokens.Space.xs) {
            if let systemImage = chosen.systemImage { Image(systemName: systemImage) }
            Text(chosen.text)
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
}

/// One line of a `RowMenu`: a choice with its text and optional symbol, or a
/// separator between groups of choices.
enum RowMenuItem<Value: Hashable> {
    case option(Value, String, systemImage: String? = nil)
    case divider
}
