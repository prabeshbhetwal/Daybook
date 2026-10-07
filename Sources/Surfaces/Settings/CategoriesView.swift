import SwiftUI
import AppKit

/// The form behind one category: what it is called, how it is drawn, what
/// colour it wears. Built-ins keep their meaning and can only change their
/// look; a category the user made can also say whether watching counts, and
/// can be retired and brought back.
final class CategoryEditorState: ObservableObject {
    @Published var selectedID: String?
    @Published var name = ""
    @Published var symbolName = WorkTypeSymbols.fallback
    @Published var hue: WorkTypeHue = .blue
    @Published var countsWhileWatching = false
    @Published var dailyGoal: TimeInterval = 0
    @Published var remindsBreaks = true
    @Published var typedSymbol = ""
    @Published var validationMessage: String?
    /// Which half of the icon section is in use: a symbol, or a letter or
    /// number drawn in a shape. Both end as an SF Symbol name.
    @Published var iconMode: IconMode = .symbol
    @Published var glyphText = ""
    @Published var glyphStyle: WorkTypeSymbols.GlyphStyle = .circle

    enum IconMode: String, CaseIterable {
        case symbol, glyph

        var displayName: String { self == .symbol ? "Symbol" : "Letter or number" }
    }
    /// The last editor request acted on, so a ticket is consumed once. Not
    /// published: consuming it must not redraw the form.
    var consumedRequestID: UInt64 = 0
    /// Bumped when the reader opens the form, so it comes into view with the
    /// cursor in its name field.
    @Published private(set) var focusRequest = 0
    /// The last focus request acted on; not published, for the same reason.
    var consumedFocusRequest = 0

    func requestFocus() { focusRequest += 1 }

    var isBuiltIn: Bool { selectedID.map { WorkType(rawValue: $0).isBuiltIn } ?? false }

    func edit(_ definition: WorkTypeDefinition) {
        selectedID = definition.id
        name = definition.name
        symbolName = definition.symbolName
        hue = definition.hue
        countsWhileWatching = definition.countsWhileWatching
        dailyGoal = definition.dailyGoal ?? 0
        remindsBreaks = definition.remindsBreaks
        if let glyph = WorkTypeSymbols.glyphText(of: definition.symbolName) {
            iconMode = .glyph
            glyphText = glyph.text
            glyphStyle = glyph.style
            typedSymbol = ""
        } else {
            iconMode = .symbol
            glyphText = ""
            typedSymbol = WorkTypeSymbols.curated.contains(definition.symbolName) ? "" : definition.symbolName
        }
        validationMessage = nil
    }

    func beginNew() {
        selectedID = WorkTypeCatalog.newCustomID()
        name = ""
        symbolName = WorkTypeSymbols.fallback
        hue = CategoryEditorState.nextHue()
        countsWhileWatching = false
        dailyGoal = 0
        remindsBreaks = true
        typedSymbol = ""
        iconMode = .symbol
        glyphText = ""
        glyphStyle = .circle
        validationMessage = nil
    }

    /// Takes the letter or number as the icon the moment it is valid; says
    /// what is accepted when it is not.
    func acceptGlyph() {
        let trimmed = glyphText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let symbol = WorkTypeSymbols.glyph(for: trimmed, style: glyphStyle) {
            symbolName = symbol
            glyphText = trimmed.uppercased()
            validationMessage = nil
        } else {
            validationMessage = "Use one letter, or a number from 0 to \(WorkTypeSymbols.glyphNumberLimit)."
        }
    }

    func pickSymbol(_ symbol: String) {
        symbolName = symbol
        typedSymbol = ""
        validationMessage = nil
    }

    func close() {
        selectedID = nil
        validationMessage = nil
    }

    /// Whether macOS has a symbol by this name. The grid only offers names
    /// that do, but a typed name is anyone's guess.
    static func symbolExists(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return NSImage(systemSymbolName: trimmed, accessibilityDescription: nil) != nil
    }

    /// Takes a typed symbol name the moment it resolves, and says so when it
    /// does not, so the preview is never a guess.
    func acceptTypedSymbol() {
        let trimmed = typedSymbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if CategoryEditorState.symbolExists(trimmed) {
            symbolName = trimmed
            validationMessage = nil
        } else {
            validationMessage = "No SF Symbol is called “\(trimmed)”."
        }
    }

    /// The category as it will be kept, or nil with the reason shown.
    func definitionForSaving(existing: [WorkTypeDefinition]) -> WorkTypeDefinition? {
        guard let id = selectedID else { return nil }
        let cleanName = WorkTypeDefinition.normalisedName(name)
        guard !cleanName.isEmpty else {
            validationMessage = "Give the category a name."
            return nil
        }
        guard cleanName.count <= WorkTypeDefinition.nameLimit else {
            validationMessage = "Keep the name to \(WorkTypeDefinition.nameLimit) characters."
            return nil
        }
        let taken = existing.contains { other in
            other.id != id && !other.isRetired
                && other.name.caseInsensitiveCompare(cleanName) == .orderedSame
        }
        guard !taken else {
            validationMessage = "Another category is already called “\(cleanName)”."
            return nil
        }
        guard CategoryEditorState.symbolExists(symbolName) else {
            validationMessage = "Choose an icon."
            return nil
        }
        validationMessage = nil
        let base = WorkTypeCatalog.builtInDefinitions.first { $0.id == id }
        let isRest = id == WorkType.breakTime.rawValue
        return WorkTypeDefinition(
            id: id, name: cleanName, symbolName: symbolName,
            hue: base?.hue == .grey ? .grey : hue,
            countsWhileWatching: base?.countsWhileWatching ?? countsWhileWatching,
            isRetired: existing.first { $0.id == id }?.isRetired ?? false,
            dailyGoal: isRest || dailyGoal <= 0 ? nil : dailyGoal,
            remindsBreaks: isRest ? true : remindsBreaks)
    }

    /// A colour no active category is wearing, so a new one is told apart at
    /// a glance; the first selectable hue when they are all taken.
    static func nextHue(active: [WorkTypeDefinition] = WorkTypeCatalog.shared.allDefinitions) -> WorkTypeHue {
        let worn = Set(active.filter { !$0.isRetired }.map(\.hue))
        return WorkTypeHue.selectable.first { !worn.contains($0) } ?? WorkTypeHue.selectable[0]
    }
}

/// The Categories settings section: every category the app knows, and the
/// form for the one being edited. "Add category…" in any picker lands here
/// with the form already open.
struct CategoriesView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject private var catalog = WorkTypeCatalog.shared
    /// Held by `SettingsDrafts`, not by this page: Settings rebuilds the page
    /// on every page switch or search, and a draft kept here went with it.
    @ObservedObject private var editor: CategoryEditorState
    @Environment(\.categoryEditorRequest) private var request
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let editorID = "category-editor"

    init(model: SettingsModel) {
        self.model = model
        _editor = ObservedObject(wrappedValue: SettingsDrafts.of(model).category)
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: Tokens.Space.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("What a session is filed under. Rename or re-icon any of them; "
                         + "add your own for work these do not describe.")
                        .font(Tokens.Typography.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Tokens.Space.m)
                    Button("New category") {
                        editor.beginNew()
                        editor.requestFocus()
                    }
                    .buttonStyle(.bordered)
                }
                VStack(spacing: 2) {
                    ForEach(catalog.allDefinitions) { definition in
                        row(definition)
                    }
                }
                if editor.selectedID != nil { editorForm.id(Self.editorID) }
            }
            .onChange(of: editor.focusRequest) {
                // The form opens under the whole list, out of sight.
                DispatchQueue.main.async {
                    withAnimation(Tokens.Motion.animation(Tokens.Motion.reveal, reduceMotion: reduceMotion)) {
                        proxy.scrollTo(Self.editorID, anchor: .top)
                    }
                }
            }
        }
        .onAppear(perform: consumeRequest)
        .onChange(of: request) { consumeRequest() }
    }

    private func consumeRequest() {
        guard let request, request.id != editor.consumedRequestID else { return }
        editor.consumedRequestID = request.id
        switch request.request {
        case .new:
            editor.beginNew()
        case .edit(let type):
            editor.edit(catalog.definition(for: type))
        }
        editor.requestFocus()
    }

    private func row(_ definition: WorkTypeDefinition) -> some View {
        let type = definition.workType
        let isSelected = editor.selectedID == definition.id
        let isEdited = type.isBuiltIn && model.workTypeDefinitions.contains { $0.id == definition.id }
        return Button {
            editor.edit(definition)
            editor.requestFocus()
        } label: {
            HStack(spacing: Tokens.Space.m) {
                WorkTypeMark(workType: type, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(definition.name)
                        .font(Tokens.Typography.rowTitle)
                        .foregroundStyle(definition.isRetired ? AnyShapeStyle(.secondary)
                                                              : AnyShapeStyle(.primary))
                    Text(rowDetail(definition, edited: isEdited))
                        .font(Tokens.Typography.body)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: Tokens.Space.s)
                Image(systemName: "chevron.right")
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Tokens.Space.s)
            .frame(minHeight: 40)
            .background(isSelected ? StoryStyle.well : Color.clear,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.well, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(StoryPressStyle(hovers: true, cornerRadius: Tokens.Radius.well))
        .accessibilityLabel("\(definition.name), \(rowDetail(definition, edited: isEdited))")
        .accessibilityHint("Edit this category")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func rowDetail(_ definition: WorkTypeDefinition, edited: Bool) -> String {
        if definition.isRetired { return "Retired · kept for old sessions" }
        var parts = [definition.workType.isBuiltIn ? "Built in" : "Yours"]
        if edited { parts.append("edited") }
        if let goal = definition.dailyGoal { parts.append("\(Tokens.duration(goal)) a day") }
        if definition.countsWhileWatching { parts.append("counts while watching") }
        if !definition.remindsBreaks, definition.workType != .breakTime { parts.append("no break reminders") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Form

    private var editorForm: some View {
        CategoryEditorForm(model: model, editor: editor, onFinished: { editor.close() })
            .padding(Tokens.Space.m)
            .background(StoryStyle.well, in: RoundedRectangle(cornerRadius: Tokens.Radius.nested))
    }
}

/// The form for one category: preview and name, colour, icon, what watching
/// means, and the actions that fit the category's kind. Shared by the
/// Settings section and the floating panel the pickers open, so the two never
/// drift apart.
struct CategoryEditorForm: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var editor: CategoryEditorState
    @ObservedObject private var catalog = WorkTypeCatalog.shared
    /// Called when the form is done with — saved, cancelled, or retired.
    var onFinished: () -> Void
    /// Called after a save with the kept definition and whether it was new,
    /// so a picker that opened the form can select what was just made.
    var onSaved: ((WorkTypeDefinition, Bool) -> Void)?
    @StateObject private var confirmingReset = BoolBox()
    @FocusState private var nameFocused: Bool

    private var selectedDefinition: WorkTypeDefinition? {
        editor.selectedID.flatMap { id in catalog.allDefinitions.first { $0.id == id } }
    }

    private var isNew: Bool { selectedDefinition == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            HStack(spacing: Tokens.Space.m) {
                WorkTypeMark(workType: WorkType(rawValue: editor.selectedID ?? ""), size: 44,
                             symbolOverride: editor.symbolName,
                             hueOverride: editor.selectedID == WorkType.breakTime.rawValue ? .grey : editor.hue)
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    Text(isNew ? "New category" : (editor.isBuiltIn ? "Built-in category" : "Your category"))
                        .font(Tokens.Typography.body)
                        .foregroundStyle(.secondary)
                    TextField("Category name", text: $editor.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                        .onChange(of: editor.name) { _, value in
                            if value.count > WorkTypeDefinition.nameLimit {
                                editor.name = String(value.prefix(WorkTypeDefinition.nameLimit))
                            }
                        }
                        .focused($nameFocused)
                        .onSubmit(save)
                        .accessibilityLabel("Category name")
                }
            }
            if editor.selectedID != WorkType.breakTime.rawValue {
                colourRow
            }
            iconGrid
            if editor.selectedID != WorkType.breakTime.rawValue {
                behaviourRows
            }
            if !editor.isBuiltIn {
                Toggle("Counts while watching", isOn: $editor.countsWhileWatching)
                Text("On for things attended rather than done, such as a call or a lecture. "
                     + "Off, watching without typing pauses the clock.")
                    .font(Tokens.Typography.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message = editor.validationMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(Tokens.Typography.body)
                    .foregroundStyle(Tokens.Colour.danger)
                    .accessibilityLabel("Category error: \(message)")
            }
            HStack(spacing: Tokens.Space.s) {
                Button(isNew ? "Add category" : "Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                // No Escape shortcut here: the sheet's or panel's own Close
                // holds it, and two made which one won a guess. Escape inside
                // the form cancels it through `onExitCommand` below.
                Button("Cancel", action: onFinished)
                Spacer(minLength: Tokens.Space.s)
                if let definition = selectedDefinition {
                    if definition.workType.isBuiltIn,
                       model.workTypeDefinitions.contains(where: { $0.id == definition.id && !$0.isRetired }) {
                        Button("Reset to default") { confirmingReset.value = true }
                            .confirmationDialog("Reset “\(definition.name)” to default?",
                                                isPresented: $confirmingReset.value,
                                                titleVisibility: .visible) {
                                Button("Reset", role: .destructive) {
                                    model.resetCategory(id: definition.id)
                                    editor.edit(catalog.definition(for: definition.workType))
                                }
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text("Its name, icon and colour return to the originals. Its daily goal "
                                     + "is removed, and break reminders go back to the default.")
                            }
                    }
                    if definition.isRetired {
                        Button("Restore") {
                            model.setCategoryRetired(id: definition.id, false)
                            editor.edit(catalog.definition(for: definition.workType))
                        }
                    } else if definition.workType != .breakTime {
                        // Built in or your own: any category but Break can go.
                        // The last one that can start a session stays.
                        let lastStartable = WorkType.startable.filter { $0 != definition.workType }.isEmpty
                        Button("Retire", role: .destructive) {
                            model.setCategoryRetired(id: definition.id, true)
                            onFinished()
                        }
                        .disabled(lastStartable)
                        .help(lastStartable
                              ? "The last category that can start a session stays."
                              : "Stops offering this category. Sessions already filed under it keep it.")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Category editor")
        .onExitCommand(perform: onFinished)
        .preference(key: OpenInlineFormKey.self,
                    value: OpenInlineForm(name: "category", cancel: onFinished))
        .announcesChanges(to: editor.validationMessage)
        .onAppear(perform: takeFocusIfAsked)
        .onChange(of: editor.focusRequest) { takeFocusIfAsked() }
    }

    private func takeFocusIfAsked() {
        guard editor.focusRequest != editor.consumedFocusRequest else { return }
        editor.consumedFocusRequest = editor.focusRequest
        // The field must be installed before it can take focus.
        DispatchQueue.main.async { nameFocused = true }
    }

    /// What the category means for the day: its own goal, and whether break
    /// reminders run during it.
    private var behaviourRows: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack(spacing: Tokens.Space.s) {
                Text("Daily goal")
                    .font(Tokens.Typography.body)
                    .foregroundStyle(.secondary)
                Picker("Daily goal", selection: $editor.dailyGoal) {
                    Text("None").tag(0.0)
                    ForEach(WorkTypeDefinition.goalOptions, id: \.self) { seconds in
                        Text(Tokens.duration(seconds)).tag(seconds)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
                .accessibilityLabel("Daily goal for this category")
                Text("Its own line under Focus time, beside the day's goal.")
                    .font(Tokens.Typography.body)
                    .foregroundStyle(.secondary)
            }
            Toggle("Remind me to take breaks during this category", isOn: $editor.remindsBreaks)
            Text("Off, break reminders wait while a session of this category runs. "
                 + "Meetings starts off: nobody wants to be told to stand up mid-call.")
                .font(Tokens.Typography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func save() {
        let wasNew = isNew
        guard let definition = editor.definitionForSaving(existing: catalog.allDefinitions) else { return }
        model.saveCategory(definition)
        onSaved?(definition, wasNew)
        onFinished()
    }

    /// The save path without a click, for verification.
    func commitForTesting() { save() }

    private var colourRow: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text("Colour")
                .font(Tokens.Typography.body)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            HStack(spacing: Tokens.Space.s) {
                ForEach(WorkTypeHue.selectable, id: \.self) { hue in
                    let isSelected = editor.hue == hue
                    Button { editor.hue = hue } label: {
                        Circle()
                            .fill(Tokens.Palette.hue(hue))
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle().strokeBorder(Color.primary.opacity(isSelected ? 0.9 : 0),
                                                      lineWidth: 2)
                                    .padding(-3))
                            .frame(width: 28, height: 28)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(hue.displayName)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        // The caption names the group, so a swatch is heard as a colour.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Colour")
    }

    private var iconGrid: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            HStack(spacing: Tokens.Space.s) {
                Text("Icon")
                    .font(Tokens.Typography.body)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Picker("Icon kind", selection: $editor.iconMode) {
                    ForEach(CategoryEditorState.IconMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Icon kind")
                Spacer(minLength: 0)
                if editor.iconMode == .symbol { browseMenu }
            }
            if editor.iconMode == .symbol {
                symbolGrid
                HStack(spacing: Tokens.Space.s) {
                    TextField("Or any SF Symbol name, such as “cpu.fill”", text: $editor.typedSymbol)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                        .onSubmit { editor.acceptTypedSymbol() }
                        .accessibilityLabel("SF Symbol name")
                    Button("Use") { editor.acceptTypedSymbol() }
                        .disabled(editor.typedSymbol.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel("Use symbol")
                }
            } else {
                glyphPane
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Icon")
    }

    /// Every curated symbol, grouped, as a pull-down: for finding by name
    /// what the grid shows only as a picture.
    private var browseMenu: some View {
        Menu {
            ForEach(WorkTypeSymbols.groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.symbols, id: \.self) { symbol in
                        Button { editor.pickSymbol(symbol) } label: {
                            Label(WorkTypeSymbols.title(for: symbol), systemImage: symbol)
                                .labelStyle(.titleAndIcon)
                        }
                    }
                }
            }
        } label: {
            Label("Browse", systemImage: "square.grid.2x2")
                .labelStyle(.titleAndIcon)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .fixedSize()
        .help("Choose a symbol by name")
        .accessibilityLabel("Browse symbols")
    }

    private var symbolGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 34, maximum: 40), spacing: Tokens.Space.xs)],
                  spacing: Tokens.Space.xs) {
            ForEach(WorkTypeSymbols.curated, id: \.self) { symbol in
                iconCell(symbol, selected: editor.symbolName == symbol,
                         label: WorkTypeSymbols.title(for: symbol)) {
                    editor.pickSymbol(symbol)
                }
            }
        }
    }

    /// A letter or number in a circle or square: "B" for Browsing, "1" for
    /// the first thing of the day, however the user thinks of it.
    private var glyphPane: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 34, maximum: 40), spacing: Tokens.Space.xs)],
                      spacing: Tokens.Space.xs) {
                ForEach(WorkTypeSymbols.glyphChoices, id: \.self) { text in
                    let symbol = WorkTypeSymbols.glyph(for: text, style: editor.glyphStyle) ?? WorkTypeSymbols.fallback
                    iconCell(symbol, selected: editor.symbolName == symbol, label: text) {
                        editor.glyphText = text
                        editor.acceptGlyph()
                    }
                }
            }
            HStack(spacing: Tokens.Space.s) {
                TextField("Letter, or a number up to \(WorkTypeSymbols.glyphNumberLimit)", text: $editor.glyphText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                    .onSubmit { editor.acceptGlyph() }
                    .accessibilityLabel("Letter or number")
                Button("Use") { editor.acceptGlyph() }
                    .disabled(editor.glyphText.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Use letter or number")
                Spacer(minLength: Tokens.Space.s)
                Picker("Shape", selection: $editor.glyphStyle) {
                    ForEach(WorkTypeSymbols.GlyphStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Shape")
                .onChange(of: editor.glyphStyle) {
                    // The shape changed under a chosen letter: re-cut it.
                    if !editor.glyphText.isEmpty { editor.acceptGlyph() }
                }
            }
        }
    }

    private func iconCell(_ symbol: String, selected: Bool, label: String,
                          action: @escaping () -> Void) -> some View {
        // A letter cut out of a filled shape reads smaller than a pictogram
        // of the same point size; give it a little more.
        let symbolFont = WorkTypeSymbols.glyphText(of: symbol) == nil ? Tokens.Typography.heading : Tokens.Typography.headline
        return Button(action: action) {
            Image(systemName: symbol)
                .font(symbolFont)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(selected ? Tokens.Palette.hue(editor.hue) : Color.primary.opacity(0.75))
                .frame(width: 34, height: 34)
                .background(selected ? Tokens.Palette.hue(editor.hue).opacity(0.16) : Color.clear,
                            in: RoundedRectangle(cornerRadius: Tokens.Radius.control, style: .continuous))
                // The colour swatches' ring, so the chosen icon is not told by
                // tint alone.
                .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.control, style: .continuous)
                    .strokeBorder(Color.primary.opacity(selected ? 0.9 : 0), lineWidth: 2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
