import AppKit
import SwiftUI

/// One line of a panel's explanation: a control's name as the panel shows it,
/// then what it does.
struct HelpEntry: Hashable {
    let name: String
    let text: String

    init(_ name: String, _ text: String) {
        self.name = name
        self.text = text
    }
}

private struct PanelHelpKey: EnvironmentKey {
    static let defaultValue: [String: [HelpEntry]] = [:]
}

extension EnvironmentValues {
    /// Explanations by panel title. A `SurfacePanel` whose title is here draws
    /// an info mark; only Settings supplies any.
    var panelHelp: [String: [HelpEntry]] {
        get { self[PanelHelpKey.self] }
        set { self[PanelHelpKey.self] = newValue }
    }
}

/// The titled panels a surface drew, and whether each carries an explanation.
/// Production ignores it; checks read it to find a panel left unexplained.
struct PanelHelpEvidenceKey: PreferenceKey {
    static let defaultValue: [String: Bool] = [:]
    static func reduce(value: inout [String: Bool], nextValue: () -> [String: Bool]) {
        value.merge(nextValue()) { $0 || $1 }
    }
}

/// The rail tiles' circled "i" at a panel's corner, and the explanation it
/// opens. A popover, where the tiles unfold in place: a panel of settings is
/// too long to push down, and a popover closes on Escape or a click elsewhere.
struct InfoMark: View {
    let title: String
    let entries: [HelpEntry]
    @Environment(\.tipCenter) private var center

    var body: some View {
        InfoMarkButton(title: title, entries: entries, center: center)
    }
}

private struct InfoMarkButton: View {
    let title: String
    let entries: [HelpEntry]
    /// The hover tips' centre, so one explanation is open at a time.
    @ObservedObject var center: TipCenter

    private var id: String { "about:\(title)" }
    private var isOpen: Bool { center.active == id }

    var body: some View {
        IconButton(systemImage: isOpen ? "info.circle.fill" : "info.circle",
                   help: "About \(title)", prominent: isOpen, label: "About \(title)", action: toggle)
            // Space presses a focused button already; Return does here too.
            .onKeyPress(.return) {
                toggle()
                return .handled
            }
            .onExitCommand(perform: isOpen ? { center.active = nil } : nil)
            .popover(isPresented: Binding(get: { isOpen },
                                          set: { if !$0, isOpen { center.active = nil } }),
                     arrowEdge: .bottom) {
                HelpPopover(title: title, entries: entries)
            }
    }

    private func toggle() { center.active = isOpen ? nil : id }
}

/// The explanation as it reads: the panel's name, then each control's name
/// and what it does, in the words VoiceOver also reads.
struct HelpCard: View {
    let title: String
    let entries: [HelpEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            Text(title)
                .font(Tokens.Typography.heading)
                .accessibilityAddTraits(.isHeader)
            ForEach(entries, id: \.self) { entry in
                VStack(alignment: .leading, spacing: 3.zoomed) {
                    Text(entry.name)
                        .font(Tokens.Typography.rowTitle)
                    Text(entry.text)
                        .font(Tokens.Typography.body)
                        .foregroundStyle(StoryStyle.supportingInk)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            }
        }
        .multilineTextAlignment(.leading)
        .padding(Tokens.Space.l)
        .frame(width: Self.width, alignment: .leading)
    }

    /// Wide enough that most entries take two or three lines.
    static var width: CGFloat { 380.zoomed }
}

/// The card, scrolling once it is taller than most of the screen: a long
/// panel's explanation at a large zoom outgrows a laptop's height.
private struct HelpPopover: View {
    let title: String
    let entries: [HelpEntry]
    @StateObject private var height = HeightBox()

    private var cap: CGFloat { (NSScreen.main?.visibleFrame.height ?? 600.zoomed) * 0.8 }

    var body: some View {
        ScrollView {
            HelpCard(title: title, entries: entries)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                })
        }
        .frame(width: HelpCard.width, height: min(max(height.value, 1), cap))
        .onPreferenceChange(ContentHeightKey.self) { height.value = $0 }
    }
}
