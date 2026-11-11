import SwiftUI

/// Scalar diagnostics align a short value with their title; a narrative status
/// needs the row's full reading width instead of a compressed trailing column.
enum SettingsReadOnlyRowLayout: Equatable {
    case trailingValue
    case statusBlock

    var usesTrailingValue: Bool { self == .trailingValue }
}

/// The row shapes every Settings group is built from. A row carries a detail
/// line only when its title and control leave something unsaid.
extension SettingsGroups {
    func preferenceRow<Accessory: View>(
        _ title: String,
        detail: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .center, spacing: Tokens.Space.m) {
            VStack(alignment: .leading, spacing: 3.zoomed) {
                Text(title).font(Tokens.Typography.rowTitle)
                if let detail { detailText(detail) }
            }
            Spacer(minLength: Tokens.Space.m)
            // Every control at its own width against the trailing edge, the
            // way System Settings lines them up. A pop-up draws at its widest
            // item whatever frame it is given, so a wider frame centred it and
            // each row's control stood at a different place.
            accessory()
                .fixedSize()
        }
        .frame(minHeight: rowMinHeight(hasDetail: detail != nil))
    }

    @ViewBuilder
    func readOnlyRow(_ title: String, value: String, detail: String? = nil,
                     valueLayout: SettingsReadOnlyRowLayout = .trailingValue) -> some View {
        switch valueLayout {
        case .trailingValue:
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.m) {
                    Text(title)
                        .font(Tokens.Typography.rowTitle)
                        .foregroundStyle(StoryStyle.supportingInk)
                    Spacer(minLength: Tokens.Space.m)
                    Text(value)
                        .font(Tokens.Typography.body)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
                if let detail { detailText(detail) }
            }
            .frame(minHeight: rowMinHeight(hasDetail: detail != nil))
            .accessibilityElement(children: .combine)
            .accessibilityLabel([title, value, detail].compactMap { $0 }.joined(separator: ", "))

        case .statusBlock:
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text(title)
                    .font(Tokens.Typography.rowTitle)
                    .foregroundStyle(StoryStyle.supportingInk)
                Text(value)
                    .font(Tokens.Typography.rowTitle)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                if let detail { detailText(detail) }
            }
            .frame(minHeight: layout.rowHeight)
            .accessibilityElement(children: .combine)
            .accessibilityLabel([title, value, detail].compactMap { $0 }.joined(separator: ", "))
        }
    }

    /// A switch whose label says what it does, not only what it is called.
    /// The description sits under the switch and is not part of its target:
    /// reading it must not flip it, and the whole row used to.
    func toggleRow(_ title: String, detail: String? = nil, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 3.zoomed) {
            Toggle(isOn: isOn) {
                Text(title).font(Tokens.Typography.rowTitle)
            }
            .accessibilityHint(detail ?? "")
            if let detail {
                detailText(detail)
                    .padding(.leading, 22.zoomed)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: rowMinHeight(hasDetail: detail != nil), alignment: .leading)
    }

    /// A system state this app cannot change for you, with the button that
    /// opens the place where you can.
    func systemSettingsRow(_ text: String, button: String,
                           action: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.m) {
            explanation(text)
            Spacer(minLength: Tokens.Space.s)
            Button(button, action: action)
                .fixedSize()
        }
    }

    var rowDivider: some View { Divider() }

    func explanation(_ text: String) -> some View {
        detailText(text)
    }

    /// A row is sized for a title and one detail line; without the detail
    /// that height left a lone title floating in empty space.
    private func rowMinHeight(hasDetail: Bool) -> CGFloat {
        hasDetail ? layout.rowHeight : layout.rowHeight - Tokens.Space.l
    }

    private func detailText(_ text: String) -> some View {
        Text(text)
            .font(Tokens.Typography.body)
            .foregroundStyle(StoryStyle.supportingInk)
            .fixedSize(horizontal: false, vertical: true)
    }
}
