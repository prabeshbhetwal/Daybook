import SwiftUI
import AppKit

/// What the floating panel is showing. Published so a second "Add category…"
/// while the panel is already up moves the form rather than being ignored.
final class CategoryEditorPanelModel: ObservableObject {
    @Published var ticket: CategoryEditorTicket?
}

/// A small floating window for making or changing a category, opened straight
/// from any picker. Settings keeps the full list; this is the short path —
/// the user asked for a category, not for a trip through preferences.
@MainActor final class CategoryEditorPanel {
    static let shared = CategoryEditorPanel()

    private var panel: NSPanel?
    private var closeObserver: NSObjectProtocol?
    private let panelModel = CategoryEditorPanelModel()
    private var ticketCount: UInt64 = 0
    /// Set on each `show`, since the store that should adopt a new category
    /// is the caller's.
    private var onSaved: ((WorkTypeDefinition, Bool) -> Void)?

    static let width: CGFloat = 520

    var isVisible: Bool { panel?.isVisible ?? false }
    var title: String? { panel?.title }

    func show(_ request: CategoryEditorRequest, model: SettingsModel,
              onSaved: ((WorkTypeDefinition, Bool) -> Void)? = nil) {
        self.onSaved = onSaved
        ticketCount &+= 1
        panelModel.ticket = CategoryEditorTicket(id: ticketCount, request: request)
        let panel = self.panel ?? makePanel(model: model)
        panel.title = CategoryEditorPanel.title(for: request)
        if !panel.isVisible { position(panel) }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// Every `show` starts the form afresh, so nothing in a closed panel is
    /// worth keeping: its window and SwiftUI tree, which would otherwise go on
    /// following the store, are let go and built again on the next `show`.
    func close() {
        guard let panel else { return }
        panel.orderOut(nil)
        release(panel)
    }

    private func release(_ closing: NSPanel) {
        guard panel === closing else { return }
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        closing.contentView = nil
        panel = nil
    }

    static func title(for request: CategoryEditorRequest) -> String {
        switch request {
        case .new: return "New category"
        case .edit: return "Edit categories"
        }
    }

    private func makePanel(model: SettingsModel) -> NSPanel {
        let content = CategoryEditorPanelView(
            model: model, panelModel: panelModel,
            onClose: { [weak self] in self?.close() },
            onSaved: { [weak self] definition, wasNew in self?.onSaved?(definition, wasNew) })
        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = [.preferredContentSize]
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: CategoryEditorPanel.width, height: 600),
                            styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.hideStandardButtons()
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        self.panel = panel
        // A system close (⌘W) ends the panel the same way `close` does.
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: panel, queue: .main) { [weak self, weak panel] _ in
                MainActor.assumeIsolated {
                    guard let self, let panel else { return }
                    self.release(panel)
                }
            }
        return panel
    }

    /// Centred on the screen the pointer is on: that is where the picker was.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { panel.center(); return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2,
                                     y: frame.midY - size.height / 2 + frame.height * 0.08))
    }
}

/// The panel's content: a row of chips to pick which category the form edits
/// — or "New" — above the shared editor form.
struct CategoryEditorPanelView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var panelModel: CategoryEditorPanelModel
    @ObservedObject private var catalog = WorkTypeCatalog.shared
    @StateObject private var editor = CategoryEditorState()
    var onClose: () -> Void
    var onSaved: (WorkTypeDefinition, Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Categories",
                        subtitle: "What a session is filed under. Pick one to change it, or make a new one.",
                        onClose: onClose)
            VStack(alignment: .leading, spacing: Tokens.Space.m) {
                chips
                Divider()
                CategoryEditorForm(model: model, editor: editor, onFinished: onClose, onSaved: onSaved)
            }
            .padding(Tokens.Space.xl)
        }
        .frame(width: CategoryEditorPanel.width)
        .background(Tokens.Colour.ground)
        .tint(Tokens.Colour.focus)
        .onAppear(perform: consumeTicket)
        .onChange(of: panelModel.ticket) { _ in consumeTicket() }
    }

    private func consumeTicket() {
        guard let ticket = panelModel.ticket, ticket.id != editor.consumedRequestID else { return }
        editor.consumedRequestID = ticket.id
        switch ticket.request {
        case .new: editor.beginNew()
        case .edit(let type): editor.edit(catalog.definition(for: type))
        }
    }

    /// Whether the form is on a category that does not exist yet.
    private var editingNew: Bool {
        guard let id = editor.selectedID else { return false }
        return !catalog.allDefinitions.contains { $0.id == id }
    }

    private var chips: some View {
        // Wraps rather than scrolls: every category, and "New", stays in view
        // at once. A scrolling row hid Break and the way to add one.
        ChipFlow(spacing: Tokens.Space.xs) {
            chip(title: "New", selected: editingNew) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .background(Tokens.Colour.elevated, in: Circle())
                    .accessibilityHidden(true)
            } action: {
                editor.beginNew()
            }
            ForEach(catalog.activeTypes) { type in
                chip(title: type.displayName, selected: editor.selectedID == type.rawValue) {
                    WorkTypeMark(workType: type, size: 20)
                } action: {
                    editor.edit(catalog.definition(for: type))
                }
            }
        }
        .accessibilityLabel("Category to edit")
    }

    private func chip<Mark: View>(title: String, selected: Bool,
                                  @ViewBuilder mark: () -> Mark,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Tokens.Space.xs) {
                mark()
                Text(title)
                    .font(Tokens.Typography.metadata.weight(selected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .padding(.leading, 4)
            .padding(.trailing, Tokens.Space.s)
            .frame(minHeight: 28)
            .background(selected ? StoryStyle.well : Color.clear, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? StoryStyle.line : Color.clear))
            .contentShape(Capsule())
        }
        .buttonStyle(StoryPressStyle(hovers: true, cornerRadius: 14))
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Lays its children left to right and wraps to a new line when the width
/// runs out. The one flowing arrangement the app needs; it makes no attempt
/// at alignment beyond that.
struct ChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        return arrange(subviews, in: width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(subviews, in: bounds.width)
        for (index, origin) in arrangement.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                                  proposal: .unspecified)
        }
    }

    private func arrange(_ subviews: Subviews, in width: CGFloat) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (origins, CGSize(width: widest, height: y + lineHeight))
    }
}
