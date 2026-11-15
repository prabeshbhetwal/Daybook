import SwiftUI

/// Settings — every panel's explanation, each card as its info mark's popover
/// draws it. A popover is a window of its own, so a still of a Settings page
/// shows the mark only; this still is where a clipped or crowded card shows.
extension Snapshotter {
    static func settingsHelpCards() -> some View {
        let groups = SettingsHelpText.groups.sorted { $0.key < $1.key }
        let columns = 6
        return HStack(alignment: .top, spacing: Tokens.Space.l) {
            ForEach(0..<columns, id: \.self) { column in
                VStack(alignment: .leading, spacing: Tokens.Space.l) {
                    ForEach(groups.indices.filter { $0 % columns == column }, id: \.self) { index in
                        HelpCard(title: groups[index].key, entries: groups[index].value)
                            .background(Tokens.Colour.surface,
                                        in: RoundedRectangle(cornerRadius: Tokens.Radius.panel, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.panel, style: .continuous)
                                .strokeBorder(Tokens.Colour.line, lineWidth: 1))
                    }
                }
            }
        }
        .padding(Tokens.Space.l)
        .fixedSize()
        .background(Tokens.Colour.ground)
    }
}
