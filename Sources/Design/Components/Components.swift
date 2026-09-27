import SwiftUI
import Charts

// Small views over plain values — no store dependency — so the gallery can drive
// them directly from fixtures.

/// A sentence-case section title with an optional contextual value. Uppercase
/// micro-labels remain reserved for charts and compact metric context.
struct SectionHeader: View {
    let title: String
    var trailing: String?
    /// In the menu bar panel the hero's title is the panel's title; a section
    /// beneath it is a step down, not a rival.
    var compact = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
            Text(title)
                .font(compact ? Tokens.Typography.rowTitle.weight(.semibold)
                              : Tokens.Typography.sectionTitle)
            Spacer(minLength: Tokens.Space.s)
            if let trailing {
                Text(trailing)
                    .font(Tokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct StartButton: View {
    var title: String = "Start focus"
    /// The caller decides how wide. It used to force `maxWidth: .infinity`,
    /// which was right in a 320pt panel and absurd in a 560pt one.
    var fills: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "play.fill")
                .font(Tokens.Typography.metadata.weight(.semibold))
                .frame(maxWidth: fills ? .infinity : nil,
                       minHeight: AccessibilityMetrics.minimumTargetSize)
                .padding(.horizontal, Tokens.Space.m)
                .background(Tokens.Colour.focus,
                            in: RoundedRectangle(cornerRadius: Tokens.Radius.nested,
                                                 style: .continuous))
                .foregroundStyle(Tokens.Colour.onFocus)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title)
    }
}

struct IntentField: View {
    @Binding var text: String
    let onSubmit: () -> Void

    var body: some View {
        TextField("What are you working on?", text: $text)
            .textFieldStyle(.plain)
            .font(Tokens.Typography.rowTitle)
            .onSubmit(onSubmit)
            .accessibilityLabel("Session intent")
    }
}

/// A pull-down, not a pop-up.
///
/// `Picker(.menu)` is a *pop-up*: AppKit positions the list so the selected row
/// sits over the button. Pick the third of four and it needs two rows above the
/// button — and this button lives a few points below the menu bar, so the list
/// ran off the top of the screen and appeared scrolled, with "Deep work" hidden
/// behind a chevron. A `Menu` always opens downward from its label, so the list
/// is whole whichever item is selected and wherever the panel sits.
struct WorkTypePicker: View {
    @Binding var selection: WorkType
    /// The menu bar panel's variant: drawn in the app's own box, the height
    /// of the activity field beside it, so it never draws greyed the way an
    /// AppKit bordered control does in a panel that is not the key window.
    var quiet = false
    @Environment(\.openCategoryEditor) private var openCategoryEditor
    /// Renames and new icons land here without a store in between.
    @ObservedObject private var catalog = WorkTypeCatalog.shared

    var body: some View {
        if quiet { quietBody } else { borderedBody }
    }

    private var quietBody: some View {
        Menu {
            menuItems
        } label: {
            HStack(spacing: Tokens.Space.xs) {
                Image(systemName: selection.symbolName)
                    .font(Tokens.Typography.metadata.weight(.medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Tokens.Palette.workType(selection))
                Text(selection.displayName)
                    .font(Tokens.Typography.control)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(Tokens.Typography.microLabel.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Tokens.Space.m)
            .frame(height: 34)
            .background(Tokens.Colour.elevated,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous)
                .strokeBorder(Tokens.Colour.line))
            .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.nested, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Category")
        .accessibilityLabel("Category, \(selection.displayName)")
    }

    private var borderedBody: some View {
        Menu {
            menuItems
        } label: {
            Label(selection.displayName, systemImage: selection.symbolName)
                .lineLimit(1)
        }
        // `.borderlessButton` sizes its AppKit popup to the label's own text:
        // 18pt tall whatever padding or frame is wrapped around it, well under
        // the 28pt floor the rest of this app holds itself to. A large bordered
        // menu button is the only style that clears it, and it stays a
        // pull-down, so the list still opens whole and downward.
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.large)
        // Neutral on purpose: the platform's own bezel and label. A
        // near-transparent tint used to stand in for "no tint" and went
        // invisible the moment the window was inactive.
        .foregroundStyle(.primary)
        .fixedSize()
        .help("Category")
        .accessibilityLabel("Category, \(selection.displayName)")
    }

    @ViewBuilder private var menuItems: some View {
        Group {
            // An inline picker, not a run of buttons: the menu then marks the
            // current category with a check, and every row keeps its symbol
            // — macOS draws a menu `Label` title-only unless told otherwise,
            // which left the list as bare words until one was chosen.
            Picker("Category", selection: $selection) {
                ForEach(WorkType.startable) { type in
                    Label(type.displayName, systemImage: type.symbolName)
                        .labelStyle(.titleAndIcon)
                        .tag(type)
                }
            }
            .pickerStyle(.inline)
            if let openCategoryEditor {
                Divider()
                Button { openCategoryEditor(.new) } label: {
                    Label("Add category…", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
                Button { openCategoryEditor(.edit(selection)) } label: {
                    Label("Edit categories…", systemImage: "slider.horizontal.3")
                        .labelStyle(.titleAndIcon)
                }
            }
        }
    }
}

private struct SessionControlsVisibleKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while the session strip is showing under the chrome. The running
    /// card then leaves Pause and Stop to the strip rather than repeating them
    /// a few hundred points lower.
    var sessionControlsVisible: Bool {
        get { self[SessionControlsVisibleKey.self] }
        set { self[SessionControlsVisibleKey.self] = newValue }
    }
}

/// What a request to open the activity editor is for.
enum ActivityEditorRequest: Equatable {
    case new
    case edit
}

private struct OpenActivityEditorKey: EnvironmentKey {
    static let defaultValue: ((ActivityEditorRequest) -> Void)? = nil
}

extension EnvironmentValues {
    /// Set by each root that can show the floating activity editor; read by
    /// the activity menu so "Add activity…" appears only where it can act.
    var openActivityEditor: ((ActivityEditorRequest) -> Void)? {
        get { self[OpenActivityEditorKey.self] }
        set { self[OpenActivityEditorKey.self] = newValue }
    }
}

/// What a request to open the category editor is for: a blank form, or one
/// category's row already selected.
enum CategoryEditorRequest: Equatable {
    case new
    case edit(WorkType)
}

/// One ask to open the editor. The counter makes two identical asks two
/// events, so the editor reopens on a second "Add category…" after the first
/// form was closed.
struct CategoryEditorTicket: Equatable {
    let id: UInt64
    let request: CategoryEditorRequest
}

private struct CategoryEditorRequestKey: EnvironmentKey {
    static let defaultValue: CategoryEditorTicket? = nil
}

extension EnvironmentValues {
    /// Read by the Categories settings section; written by Settings from the
    /// window model whenever a picker asked for the editor.
    var categoryEditorRequest: CategoryEditorTicket? {
        get { self[CategoryEditorRequestKey.self] }
        set { self[CategoryEditorRequestKey.self] = newValue }
    }
}

/// Set by each root — the main window and the menu bar panel — to open the
/// floating category editor, and read by every category picker, so "Add
/// category…" appears wherever a category is chosen and nowhere it could not
/// be acted on.
private struct OpenCategoryEditorKey: EnvironmentKey {
    static let defaultValue: ((CategoryEditorRequest) -> Void)? = nil
}

extension EnvironmentValues {
    var openCategoryEditor: ((CategoryEditorRequest) -> Void)? {
        get { self[OpenCategoryEditorKey.self] }
        set { self[OpenCategoryEditorKey.self] = newValue }
    }
}

/// The title band of a floating panel: title, one line of what it is for,
/// and the close control, drawn the way the app's sheets draw theirs. The
/// window's own buttons are hidden so there is one way to close.
struct PanelHeader: View {
    let title: String
    var subtitle: String?
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: Tokens.Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Tokens.Typography.sectionTitle)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle)
                            .font(Tokens.Typography.metadata)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Tokens.Space.m)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(Tokens.Typography.metadata.weight(.semibold))
                        .frame(width: 28, height: 28)
                        .background(Tokens.Colour.elevated, in: Circle())
                }
                .buttonStyle(StoryPressStyle(hovers: true, cornerRadius: 14))
                .keyboardShortcut(.cancelAction)
                .help("Close")
                .accessibilityLabel("Close \(title)")
            }
            .padding(.horizontal, Tokens.Space.xl)
            .padding(.vertical, Tokens.Space.m)
            .background(Tokens.Colour.surface)
            Divider()
        }
    }
}

extension NSPanel {
    /// One way to close: the app's own control in the title band.
    func hideStandardButtons() {
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(kind)?.isHidden = true
        }
    }
}

/// A category's symbol in its own colour on a tinted disc — the one way a
/// category is drawn as a mark, in continuation rows, the category list and
/// the editor's preview. Anywhere text sits beside it, `Label` with the
/// category's symbol is the inline form.
struct WorkTypeMark: View {
    let workType: WorkType
    var size: CGFloat = 30
    var symbolOverride: String?
    var hueOverride: WorkTypeHue?

    private var tint: Color { Tokens.Palette.hue(hueOverride ?? workType.hue) }

    var body: some View {
        Image(systemName: symbolOverride ?? workType.symbolName)
            .font(.system(size: size * 0.45, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.13), in: Circle())
            .accessibilityHidden(true)
    }
}

/// Observing wrapper for the menu bar label. A `Scene` body does not observe
/// an `ObservableObject`, so the label must be a `View` holding
/// `@ObservedObject` or it renders once, at launch, and never again. It holds
/// the label's own model, not the store: the store changes every second, the
/// label only when what it shows does.
struct MenuBarLabelView: View {
    @ObservedObject var model: MenuBarLabelModel

    var body: some View {
        MenuBarLabel(display: model.display)
            .accessibilityLabel(model.display.accessibilityLabel)
    }
}

/// The menu bar's ambient state: a goal ring always, elapsed while a session
/// runs, a pause mark when paused, a dot when a question is waiting.
struct MenuBarLabel: View {
    let display: MenuBarDisplay

    var body: some View {
        HStack(spacing: Tokens.Space.xs) {
            if let glyph = MenuBarGlyph.image(progress: display.progress,
                                              paused: display.isPaused,
                                              attention: display.needsAttention,
                                              isMet: display.isMet) {
                Image(nsImage: glyph)
            } else {
                Image(systemName: display.needsAttention ? "exclamationmark.circle.fill" : "infinity")
            }
            if let time = display.time {
                Text(time)
                    .font(Tokens.Typography.menuBar)
            }
        }
        .foregroundStyle(display.isPaused ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
    }
}
