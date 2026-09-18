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

    private let customTag: TimeInterval = -1

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
                if picked == customTag {
                    custom.value = true
                    draft.text = isNever ? "" : String(Int((selection / 60).rounded()))
                } else {
                    custom.value = false
                    selection = picked
                }
            })
    }

    var body: some View {
        HStack(spacing: Tokens.Space.s) {
            if custom.value || (!options.contains(selection) && !isNever) {
                customField
            }
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
            .frame(width: 130)
            .accessibilityLabel(label)
        }
    }

    /// Minutes, applied on Return or when the field loses focus.
    private var customField: some View {
        HStack(spacing: 4) {
            TextField("minutes", text: $draft.text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
                .multilineTextAlignment(.trailing)
                .onSubmit(apply)
                .accessibilityLabel("\(label), minutes")
            Text("min")
                .font(Tokens.Typography.metadata)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            if draft.text.isEmpty, !isNever { draft.text = String(Int((selection / 60).rounded())) }
        }
    }

    private func apply() {
        let trimmed = draft.text.trimmingCharacters(in: .whitespaces)
        guard let minutes = Int(trimmed), minutes >= 1, minutes <= 24 * 60 else { return }
        selection = TimeInterval(minutes * 60)
        custom.value = true
    }
}
