import SwiftUI

/// A duration preference the way the rest of Settings states one: the usual
/// choices in a menu, plus your own number and, where it makes sense, Never.
/// A value that is not in the list shows as the custom field, so a setting
/// typed in once is still readable when the page opens again.
struct ThresholdControl: View {
    let label: String
    @Binding var selection: TimeInterval
    let options: [TimeInterval]
    var allowsNever = false
    /// What the store reads as Never: a span nothing reaches, or 0 where the
    /// store treats 0 as off.
    var neverValue: TimeInterval = FocusConstants.never
    @StateObject private var custom = BoolBox()
    @StateObject private var draft = TextBox()
    /// Set when "Custom…" is chosen, so the field takes the cursor once it is
    /// on screen rather than leaving the reader to hunt for it.
    @StateObject private var wantsFocus = BoolBox()
    /// Set when the typed number was refused; the stored value is unchanged.
    @StateObject private var rejected = BoolBox()
    @FocusState private var fieldFocused: Bool

    private let customTag: TimeInterval = -1
    static let rejection = "Enter 1 to 1,440 minutes."

    private var isNever: Bool {
        neverValue == 0 ? selection <= 0 : FocusConstants.isNever(selection)
    }

    private var pickerSelection: Binding<TimeInterval> {
        Binding(
            get: {
                if isNever { return neverValue }
                if custom.value || !options.contains(selection) { return customTag }
                return selection
            },
            set: { picked in
                rejected.value = false
                if picked == customTag {
                    custom.value = true
                    draft.text = isNever ? "" : String(Int((selection / 60).rounded()))
                    wantsFocus.value = true
                } else {
                    custom.value = false
                    selection = picked
                }
            })
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 3.zoomed) {
            HStack(spacing: Tokens.Space.s) {
                Picker(label, selection: pickerSelection) {
                    ForEach(options, id: \.self) { seconds in
                        Text(Tokens.duration(seconds)).tag(seconds)
                    }
                    Text("Custom…").tag(customTag)
                    if allowsNever {
                        Divider()
                        Text("Never").tag(neverValue)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel(label)
                // After the menu, where the eye and the Tab key go next.
                if custom.value || (!options.contains(selection) && !isNever) {
                    customField
                }
            }
            if rejected.value {
                Text(Self.rejection)
                    .font(Tokens.Typography.body)
                    .foregroundStyle(Tokens.Colour.danger)
            }
        }
    }

    /// Minutes, applied on Return or when the field loses focus.
    private var customField: some View {
        HStack(spacing: Tokens.Space.xs) {
            TextField("minutes", text: $draft.text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 64.zoomed)
                .multilineTextAlignment(.trailing)
                .focused($fieldFocused)
                .onSubmit(apply)
                .accessibilityLabel("\(label), minutes")
            Text("min")
                .font(Tokens.Typography.body)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            if draft.text.isEmpty, !isNever { draft.text = String(Int((selection / 60).rounded())) }
            focusIfWanted()
        }
        .onChange(of: wantsFocus.value) { focusIfWanted() }
        // A refusal belongs to the text that earned it.
        .onChange(of: draft.text) { rejected.value = false }
        .onChange(of: fieldFocused) { _, focused in
            // Leaving an empty field, or one already refused, is not a new answer.
            if !focused, !rejected.value, !draft.text.trimmingCharacters(in: .whitespaces).isEmpty {
                apply()
            }
        }
    }

    private func focusIfWanted() {
        guard wantsFocus.value else { return }
        wantsFocus.value = false
        // The field must be installed before it can take focus.
        DispatchQueue.main.async { fieldFocused = true }
    }

    private func apply() {
        guard let minutes = Self.minutes(from: draft.text) else {
            rejected.value = true
            Announcement.post(Self.rejection)
            return
        }
        rejected.value = false
        let seconds = TimeInterval(minutes * 60)
        if selection != seconds { selection = seconds }
        custom.value = true
    }

    /// A whole number of minutes from one to a day, or nil when the text is
    /// anything else.
    static func minutes(from text: String) -> Int? {
        guard let minutes = Int(text.trimmingCharacters(in: .whitespaces)),
              minutes >= 1, minutes <= 24 * 60 else { return nil }
        return minutes
    }
}
